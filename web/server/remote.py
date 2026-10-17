"""Pilot ze smartfona w wersji webowej: telefon (zalogowany tym samym kontem) wysyła polecenia przez serwer
do karty przeglądarki, która prowadzi projekcję, a ta publikuje stan dla telefonu.

Strona telefonu jest wspólna z macOS i Windows (Sources/CantatePresenterCore/Resources/remote_page.html,
kopia w web/remote_page.html). Polecenia i stan mają ten sam JSON co RemoteCommand/RemoteState w macOS.
"""
import base64
import hashlib
import json
import re
import threading
import time
import unicodedata
import uuid

# Karta operatora uznawana za połączoną, jeśli pytała o polecenia w tym czasie (długie odpytywanie trwa do 25 s).
OPERATOR_WINDOW = 35.0
# Telefon liczy się jako połączony, jeśli pytał o stan w tym czasie (strona pyta co sekundę), jak w macOS.
PHONE_WINDOW = 5.0
# Polecenie, którego nikt nie odebrał w tym czasie, jest odrzucane (stare kliknięcia nie mogą zadziałać później).
COMMAND_TTL = 10.0
MAX_STATE = 512 * 1024
SIMPLE_COMMANDS = {"next", "previous", "nextSong", "previousSong", "black", "clearText", "stop", "start"}

# MARK: - Wyszukiwanie (jak foldString / searchFold / songMatches w web/src/core/text.js)

_CASE_FOLD = {"ß": "ss", "ẞ": "ss", "ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl"}


def fold(value: str) -> str:
    text = str(value or "").replace("ł", "l").replace("Ł", "l")
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.category(c).startswith("M"))
    text = "".join(_CASE_FOLD.get(c, c) for c in text)
    return text.lower().strip()


def search_fold(value: str) -> str:
    folded = "".join(c if unicodedata.category(c)[0] in "LMN" else " " for c in fold(value))
    return re.sub(r" +", " ", folded).strip()


def song_matches(song: dict, query: str, title_and_author_only: bool = False) -> bool:
    q = search_fold(query)
    if not q:
        return True
    if q in search_fold(song.get("title", "")) or q in search_fold(song.get("author", "")):
        return True
    if title_and_author_only:
        return False
    tags = song.get("tags") if isinstance(song.get("tags"), list) else []
    return any(q in search_fold(tag) for tag in tags if isinstance(tag, str)) or q in search_fold(song.get("rawLyrics", ""))


def search(songs: list, query: str, limit: int = 40) -> list[dict]:
    """Pieśni pasujące do zapytania (jak RemoteControlBridge.search w macOS): najpierw trafienia w tytule lub autorze."""
    if not search_fold(query):
        return []
    songs = [s for s in songs if isinstance(s, dict) and isinstance(s.get("title"), str)]
    matching = [s for s in songs if song_matches(s, query)]
    titled = [s for s in matching if song_matches(s, query, title_and_author_only=True)]
    rest = [s for s in matching if not song_matches(s, query, title_and_author_only=True)]
    results = []
    for song in (titled + rest)[:limit]:
        slides = song.get("slides") if isinstance(song.get("slides"), list) else []
        first = slides[0].get("text", "") if slides and isinstance(slides[0], dict) else ""
        results.append({"id": str(song.get("id", "")), "title": song["title"], "author": str(song.get("author", "")),
                        "firstLine": str(first).split("\n")[0]})
    return results


# MARK: - Polecenia


def validate_command(body) -> dict | None:
    """Polecenie z telefonu w postaci kanonicznej albo None (jak RemoteCommand(json:) w macOS)."""
    if not isinstance(body, dict) or not isinstance(body.get("command"), str):
        return None
    name = body["command"]
    if name in SIMPLE_COMMANDS:
        return {"command": name}
    if name in ("slide", "planItem"):
        index = body.get("index")
        return {"command": name, "index": index} if isinstance(index, int) and not isinstance(index, bool) and index >= 0 else None
    if name == "song":
        try:
            return {"command": "song", "id": str(uuid.UUID(str(body.get("id"))))}
        except ValueError:
            return None
    return None


# MARK: - Przekaźnik


class RemoteRelay:
    """Stan od karty operatora i kolejka poleceń od telefonów (tylko w pamięci serwera)."""

    def __init__(self):
        self.condition = threading.Condition()
        self.state: dict | None = None
        self.version = 0
        self.commands: list[tuple[float, dict]] = []
        self.operator_seen = 0.0
        self.phones: dict[str, float] = {}
        # Numery poleceń: ostatnie zakolejkowane, ostatnie pobrane przez kartę i ostatnie, którego skutek karta opublikowała.
        # Telefon czeka na stan po swoim poleceniu, a nie na dowolną (np. spóźnioną) publikację.
        self.queued = 0
        self.taken = 0
        self.handled = 0
        self.reports_handled = False

    def operator_connected(self, now: float | None = None) -> bool:
        return (now or time.time()) - self.operator_seen < OPERATOR_WINDOW

    def publish(self, state: dict):
        handled = state.pop("handled", None)
        with self.condition:
            if isinstance(handled, int) and not isinstance(handled, bool):
                self.reports_handled = True
                self.handled = max(self.handled, min(handled, self.taken))
            self.state = state
            self.version += 1
            self.operator_seen = time.time()
            self.condition.notify_all()

    def _phone_count(self, moment: float) -> int:
        return sum(1 for seen in self.phones.values() if moment - seen < PHONE_WINDOW)

    def _seen(self, phone: str):
        now = time.time()
        is_new = now - self.phones.get(phone, 0.0) >= PHONE_WINDOW
        self.phones[phone] = now
        if is_new:
            # Karta operatora od razu pokazuje nowy telefon (długie odpytywanie się kończy).
            self.condition.notify_all()

    def phone_state(self, phone: str) -> dict | None:
        """Stan dla telefonu; None, gdy żadna karta nie prowadzi pilota."""
        with self.condition:
            self._seen(phone)
            return self.state if self.state is not None and self.operator_connected() else None

    def send(self, phone: str, command: dict, wait: float = 1.5) -> dict | None:
        """Kolejkuje polecenie i czeka chwilę na nowy stan od operatora (telefon od razu widzi skutek)."""
        with self.condition:
            if self.state is None or not self.operator_connected():
                return None
            self._seen(phone)
            self.queued += 1
            number = self.queued
            self.commands.append((time.time(), command))
            start_version = self.version
            self.condition.notify_all()
            # Starsza karta operatora (bez pola „handled”): wystarczy dowolny nowy stan.
            self.condition.wait_for(lambda: self.handled >= number if self.reports_handled else self.version != start_version, timeout=wait)
            return self.state

    def take_commands(self, wait: float = 25.0) -> list[dict]:
        return self.take(wait)[0]

    def take(self, wait: float = 25.0) -> tuple[list[dict], int]:
        """Długie odpytywanie przez kartę operatora: polecenia (albo pusta lista po czasie) i numer ostatniego z nich,
        który karta odsyła w polu „handled” stanu po ich wykonaniu."""
        with self.condition:
            self.operator_seen = time.time()
            phones = self._phone_count(time.time())
            self.condition.wait_for(lambda: bool(self.commands) or self._phone_count(time.time()) > phones, timeout=wait)
            now = time.time()
            self.operator_seen = now
            fresh = [command for queued, command in self.commands if now - queued < COMMAND_TTL]
            self.commands = []
            self.taken = self.queued
            return fresh, self.taken

    def connected_phones(self, now: float | None = None) -> int:
        with self.condition:
            return self._phone_count(now or time.time())

    def stop(self):
        """Operator wyłączył pilota: telefony dostają „brak połączenia”."""
        with self.condition:
            self.state = None
            self.commands = []
            self.operator_seen = 0.0
            self.condition.notify_all()


# MARK: - Strona telefonu


def page_with_csp(template: str, language: str) -> tuple[bytes, str]:
    """Strona pilota z językiem i polityką CSP dopuszczającą tylko jej własny skrypt i styl (skróty SHA-256)."""
    html = template.replace("{{LANG}}", "".join(c for c in language if c.isalpha() or c == "-"))

    def hashes(tag: str) -> str:
        found = re.findall(rf"<{tag}>(.*?)</{tag}>", html, re.S)
        return " ".join("'sha256-" + base64.b64encode(hashlib.sha256(body.encode()).digest()).decode() + "'" for body in found)

    csp = (f"default-src 'none'; script-src {hashes('script')}; style-src {hashes('style')}; connect-src 'self'; img-src 'self' data:; "
           "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
    return html.encode(), csp


def encode_state(state: dict) -> bytes:
    return json.dumps(state, ensure_ascii=False).encode()
