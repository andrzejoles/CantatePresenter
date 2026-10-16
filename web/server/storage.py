"""Dane aplikacji na serwerze: songs.json, plans.json, settings.json w formacie wersji macOS.

Jak JSONFileStore w macOS (K1): zapis atomowy, 5 poprzednich wersji w history/, nieczytelny plik
trafia do kwarantanny zamiast zostać nadpisanym. Każdy plik ma numer wersji (revision), żeby zmiany
z dwóch komputerów nie nadpisywały się po cichu.
"""
import datetime
import json
import os
import shutil
import threading

KINDS = ("songs", "plans", "settings", "extraFiles")
# extraFiles: pliki z kopii macOS, których wersja webowa nie używa (logo, raport CCLI); ścieżka → base64.
OBJECT_KINDS = ("settings", "extraFiles")
HISTORY_LIMIT = 5
# Wersja formatu danych, jak DataSchema.current w macOS: pole schemaVersion w settings.json.
# Dane z nowszej wersji są tylko do odczytu, żeby nie zgubić pól, których ta wersja nie zna.
SCHEMA_VERSION = 1
MAX_BODY = 50 * 1024 * 1024


class Conflict(Exception):
    pass


class Storage:
    def __init__(self, directory: str):
        self.directory = directory
        self.lock = threading.RLock()
        os.makedirs(os.path.join(directory, "history"), exist_ok=True)
        self.revisions = {kind: 0 for kind in KINDS}
        self.locked = set()
        meta = self._read_meta()
        self.revisions.update({k: int(v) for k, v in meta.get("revisions", {}).items() if k in KINDS})

    def path(self, kind: str) -> str:
        return os.path.join(self.directory, f"{kind}.json")

    def _read_meta(self) -> dict:
        try:
            with open(os.path.join(self.directory, "meta.json"), encoding="utf-8") as source:
                return json.load(source)
        except (OSError, ValueError):
            return {}

    def _write_atomic(self, path: str, data: bytes):
        temporary = f"{path}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "wb") as target:
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)

    def load(self, kind: str):
        """Wartość z pliku albo None (brak). Nieczytelny plik → kwarantanna, zapis zablokowany."""
        with self.lock:
            path = self.path(kind)
            if not os.path.exists(path):
                return None
            try:
                with open(path, encoding="utf-8") as source:
                    return json.load(source)
            except (OSError, ValueError):
                stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
                shutil.copy2(path, os.path.join(self.directory, f"{kind}.corrupt-{stamp}.json"))
                self.locked.add(kind)
                return None

    @staticmethod
    def schema_version_of(settings) -> int:
        value = settings.get("schemaVersion", 0) if isinstance(settings, dict) else 0
        return value if isinstance(value, int) and not isinstance(value, bool) else 0

    def newer_schema(self) -> int | None:
        """Numer formatu, gdy dane zapisała nowsza wersja aplikacji; inaczej None."""
        version = self.schema_version_of(self.load("settings"))
        return version if version > SCHEMA_VERSION else None

    def snapshot(self) -> dict:
        with self.lock:
            newer = self.newer_schema()
            locked = set(KINDS) if newer else self.locked
            return {"data": {kind: self.load(kind) for kind in KINDS}, "revisions": dict(self.revisions),
                    "locked": sorted(locked), "canUndoRestore": os.path.exists(self.before_restore_path),
                    "newerSchema": newer, "schemaVersion": SCHEMA_VERSION}

    @property
    def before_restore_path(self) -> str:
        return os.path.join(self.directory, "before-restore.json")

    def restore(self, data: dict) -> dict:
        """Podmienia dane z kopii; poprzedni stan zostaje w before-restore.json (do cofnięcia)."""
        if self.schema_version_of(data.get("settings")) > SCHEMA_VERSION:
            raise ValueError("newer schema")
        with self.lock:
            if self.newer_schema():
                raise PermissionError("newer schema")
            current = {kind: self.load(kind) for kind in KINDS}
            self._write_atomic(self.before_restore_path, json.dumps(current, ensure_ascii=False).encode())
            return {kind: self.save(kind, data.get(kind, {} if kind in OBJECT_KINDS else []), None) for kind in KINDS}

    def undo_restore(self) -> bool:
        with self.lock:
            if not os.path.exists(self.before_restore_path):
                return False
            with open(self.before_restore_path, encoding="utf-8") as source:
                previous = json.load(source)
            for kind in KINDS:
                value = previous.get(kind)
                self.save(kind, value if value is not None else ({} if kind in OBJECT_KINDS else []), None)
            os.remove(self.before_restore_path)
            return True

    def save(self, kind: str, value, expected_revision: int | None) -> int:
        if kind not in KINDS:
            raise KeyError(kind)
        if not isinstance(value, dict if kind in OBJECT_KINDS else list):
            raise ValueError("invalid shape")
        with self.lock:
            if kind in self.locked or self.newer_schema():
                raise PermissionError(kind)
            if expected_revision is not None and expected_revision != self.revisions[kind]:
                raise Conflict(kind)
            path = self.path(kind)
            if os.path.exists(path):
                stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S-%f")
                shutil.copy2(path, os.path.join(self.directory, "history", f"{kind}-{stamp}.json"))
                history = sorted(f for f in os.listdir(os.path.join(self.directory, "history")) if f.startswith(f"{kind}-"))
                for old in history[:-HISTORY_LIMIT]:
                    os.remove(os.path.join(self.directory, "history", old))
            self._write_atomic(path, json.dumps(value, ensure_ascii=False, indent=2).encode())
            self.revisions[kind] += 1
            self._write_atomic(os.path.join(self.directory, "meta.json"), json.dumps({"revisions": self.revisions}).encode())
            return self.revisions[kind]

    def unlock(self, kind: str):
        """Po ręcznym naprawieniu pliku: odblokowanie zapisu."""
        with self.lock:
            self.locked.discard(kind)
