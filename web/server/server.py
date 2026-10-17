#!/usr/bin/env python3
"""CantatePresenter Web: prywatny serwer aplikacji (tylko biblioteka standardowa Pythona 3.10+).

Aplikacja i dane są dostępne wyłącznie po zalogowaniu: hasło + kod z aplikacji uwierzytelniającej (TOTP).
Dane w katalogu danych w formacie wersji macOS (songs.json, plans.json, settings.json).

  python3 web/server/server.py adduser NAZWA --data DANE      # nowe konto (hasło z klawiatury)
  python3 web/server/server.py serve --data DANE --port 8443 --tls-cert cert.pem --tls-key key.pem
  python3 web/server/server.py serve --data DANE --behind-proxy  # HTTPS w reverse proxy (np. Caddy)

Bez HTTPS ciasteczko sesji nie ma flagi Secure; dozwolone tylko na adresie lokalnym (--insecure-local).
"""
import argparse
import getpass
import http.server
import ipaddress
import json
import mimetypes
import os
import secrets
import socketserver
import ssl
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auth  # noqa: E402
import remote  # noqa: E402
import appversion  # noqa: E402
from storage import KINDS, MAX_BODY, Conflict, Storage  # noqa: E402

WEB_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_VERSION = appversion.current(os.path.dirname(WEB_ROOT))
MAX_LIVE = 2 * 1024 * 1024
SESSION_IDLE = 12 * 3600
SESSION_MAX = 7 * 24 * 3600
PENDING_MAX = 5 * 60
IP_WINDOW, IP_MAX_FAILURES = 15 * 60, 20

# Pliki dostępne bez logowania: tylko to, czego potrzebuje strona logowania.
PUBLIC_FILES = {
    "/login.html", "/styles.css", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png",
    "/i18n/Localizable.xcstrings", "/src/i18n.js", "/src/login.js", "/src/core/qr.js", "/src/version.js",
}
# Katalogi, których serwer nigdy nie udostępnia (kod serwera, narzędzia, testy).
HIDDEN_PREFIXES = ("/server/", "/tools/", "/tests/")

CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self' https://*.wikisource.org; "
       "font-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")


def log(message: str):
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}", file=sys.stderr, flush=True)


class State:
    def __init__(self, data_dir: str, secure_cookies: bool, trust_proxy: bool):
        self.storage = Storage(data_dir)
        self.users = auth.Users(os.path.join(data_dir, "users.json"))
        self.secure_cookies = secure_cookies
        self.trust_proxy = trust_proxy
        self.lock = threading.Lock()
        self.sessions: dict[str, dict] = {}
        # Bieżąca projekcja dla ekranów muzyków na innych urządzeniach (tylko w pamięci).
        self.live_source: dict | None = None
        # Pilot ze smartfona: stan od karty operatora i polecenia od telefonów (tylko w pamięci).
        self.remote = remote.RemoteRelay()
        self.pending: dict[str, dict] = {}
        self.ip_failures: dict[str, list[float]] = {}

    def ip_blocked(self, ip: str) -> bool:
        with self.lock:
            recent = [t for t in self.ip_failures.get(ip, []) if t > time.time() - IP_WINDOW]
            self.ip_failures[ip] = recent
            return len(recent) >= IP_MAX_FAILURES

    def ip_failure(self, ip: str):
        with self.lock:
            self.ip_failures.setdefault(ip, []).append(time.time())

    def end_other_sessions(self, user: str, keep: str | None):
        """Po zmianie hasła lub aplikacji uwierzytelniającej: wylogowanie innych urządzeń."""
        with self.lock:
            for token in [t for t, s in self.sessions.items() if s["user"] == user and t != keep]:
                del self.sessions[token]

    def new_session(self, user: str) -> str:
        token = secrets.token_urlsafe(32)
        with self.lock:
            now = time.time()
            self.sessions[token] = {"user": user, "created": now, "seen": now}
        return token

    def session(self, token: str | None) -> dict | None:
        if not token:
            return None
        with self.lock:
            session = self.sessions.get(token)
            now = time.time()
            if not session or now - session["seen"] > SESSION_IDLE or now - session["created"] > SESSION_MAX \
                    or session["user"] not in self.users.users:
                self.sessions.pop(token, None)
                return None
            session["seen"] = now
            return session

    def end_sessions(self, user: str):
        with self.lock:
            for token in [t for t, s in self.sessions.items() if s["user"] == user]:
                del self.sessions[token]


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "CantatePresenter"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    state: State

    # MARK: - Odpowiedzi

    def security_headers(self, csp: str = CSP):
        self.send_header("Content-Security-Policy", csp)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(self), geolocation=()")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        if self.state.secure_cookies:
            self.send_header("Strict-Transport-Security", "max-age=31536000")

    def respond(self, status: int, body: bytes = b"", content_type: str = "application/json; charset=utf-8",
                headers: list[tuple[str, str]] | None = None, cache: bool = False, csp: str = CSP):
        self.send_response(status)
        self.security_headers(csp)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "private, max-age=300" if cache else "no-store")
        for name, value in headers or []:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, status: int, value, headers=None):
        self.respond(status, json.dumps(value, ensure_ascii=False).encode(), headers=headers)

    def cookie(self, name: str, value: str, max_age: int | None) -> tuple[str, str]:
        parts = [f"{name}={value}", "Path=/", "HttpOnly", "SameSite=Strict"]
        if self.state.secure_cookies:
            parts.append("Secure")
        if max_age is not None:
            parts.append(f"Max-Age={max_age}")
        return ("Set-Cookie", "; ".join(parts))

    def log_message(self, format, *args):
        pass

    # MARK: - Żądanie

    def client_ip(self) -> str:
        if self.state.trust_proxy:
            forwarded = self.headers.get("X-Forwarded-For", "").split(",")[0].strip()
            if forwarded:
                return forwarded
        return self.client_address[0]

    def cookies(self) -> dict[str, str]:
        result = {}
        for part in self.headers.get("Cookie", "").split(";"):
            if "=" in part:
                name, value = part.strip().split("=", 1)
                result[name] = value
        return result

    def current_session(self) -> dict | None:
        return self.state.session(self.cookies().get("cantate_session"))

    def read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            raise ValueError("too large")
        body = self.rfile.read(length) if length else b""
        return json.loads(body or b"null")

    def same_origin_request(self) -> bool:
        """CSRF: nagłówek, którego zwykły formularz z innej strony nie wyśle, i zgodne Origin."""
        if self.headers.get("X-Cantate-Request") != "1":
            return False
        origin = self.headers.get("Origin")
        if origin:
            host = self.headers.get("X-Forwarded-Host") if self.state.trust_proxy and self.headers.get("X-Forwarded-Host") else self.headers.get("Host")
            return urllib.parse.urlparse(origin).netloc == host
        return True

    # MARK: - GET

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/session":
            session = self.current_session()
            return self.json(200, {"user": session["user"]}) if session else self.json(401, {"error": "unauthorized"})
        if path == "/api/data":
            if not self.current_session():
                return self.json(401, {"error": "unauthorized"})
            return self.json(200, self.state.storage.snapshot())
        if path == "/api/live":
            if not self.current_session():
                return self.json(401, {"error": "unauthorized"})
            with self.state.lock:
                return self.json(200, {"source": self.state.live_source})
        if path in ("/remote", "/api/state", "/api/search", "/api/remote/commands"):
            return self.remote_get(path)
        if path == "/api/account":
            session = self.current_session()
            if not session:
                return self.json(401, {"error": "unauthorized"})
            user = self.state.users.users.get(session["user"], {})
            return self.json(200, {"user": session["user"], "backupCodesLeft": len(user.get("backupCodes", [])),
                                   "minPasswordLength": auth.MIN_PASSWORD_LENGTH})
        if path.startswith("/api/"):
            return self.json(404, {"error": "not found"})
        if path in ("/", ""):
            path = "/index.html"
        if path not in PUBLIC_FILES and not self.current_session():
            if path.endswith(".html"):
                self.send_response(302)
                self.security_headers()
                self.send_header("Location", "/login.html?next=" + urllib.parse.quote(path))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            return self.json(401, {"error": "unauthorized"})
        self.serve_static(path)

    def serve_static(self, path: str):
        relative = urllib.parse.unquote(path).lstrip("/")
        if relative == "src/version.js":
            return self.respond(200, appversion.module_source(APP_VERSION), "text/javascript; charset=utf-8", cache=False)
        if any(path.startswith(prefix) for prefix in HIDDEN_PREFIXES) or any(part.startswith(".") for part in relative.split("/")):
            return self.json(404, {"error": "not found"})
        full = os.path.realpath(os.path.join(WEB_ROOT, relative))
        if not full.startswith(WEB_ROOT + os.sep) or not os.path.isfile(full):
            return self.json(404, {"error": "not found"})
        content_type = {
            ".js": "text/javascript; charset=utf-8", ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
            ".webmanifest": "application/manifest+json", ".xcstrings": "application/json; charset=utf-8",
        }.get(os.path.splitext(full)[1], mimetypes.guess_type(full)[0] or "application/octet-stream")
        with open(full, "rb") as source:
            self.respond(200, source.read(), content_type, cache=full.endswith(".png"))

    # MARK: - POST / PUT

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.same_origin_request():
            return self.json(403, {"error": "forbidden"})
        try:
            body = self.read_json()
        except ValueError:
            return self.json(400, {"error": "bad request"})
        if path == "/api/login":
            return self.login(body)
        if path == "/api/login/totp":
            return self.second_factor(body)
        if path == "/api/login/enroll":
            return self.enroll(body)
        if path == "/api/logout":
            token = self.cookies().get("cantate_session")
            with self.state.lock:
                self.state.sessions.pop(token or "", None)
            return self.json(200, {"ok": True}, headers=[self.cookie("cantate_session", "", 0)])
        session = self.current_session()
        if not session:
            return self.json(401, {"error": "unauthorized"})
        if path.startswith("/api/account/"):
            return self.account(path, body, session)
        if path == "/api/live":
            if not isinstance(body, dict) or len(json.dumps(body)) > MAX_LIVE:
                return self.json(400, {"error": "bad request"})
            with self.state.lock:
                self.state.live_source = body
            return self.json(200, {"ok": True})
        if path in ("/api/command", "/api/remote/state", "/api/remote/stop"):
            return self.remote_post(path, body)
        if path == "/api/data/restore":
            return self.restore(body, session)
        if path == "/api/data/undo-restore":
            if not self.state.storage.undo_restore():
                return self.json(404, {"error": "nothing to undo"})
            log(f"cofnięto przywrócenie kopii: {session['user']!r}")
            return self.json(200, {"ok": True})
        return self.json(404, {"error": "not found"})

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.same_origin_request():
            return self.json(403, {"error": "forbidden"})
        session = self.current_session()
        if not session:
            return self.json(401, {"error": "unauthorized"})
        kind = path.removeprefix("/api/data/")
        if not path.startswith("/api/data/") or kind not in KINDS:
            return self.json(404, {"error": "not found"})
        try:
            body = self.read_json()
            expected = self.headers.get("If-Match")
            revision = self.state.storage.save(kind, body, int(expected) if expected is not None else None)
        except Conflict:
            return self.json(409, {"error": "conflict", "revisions": self.state.storage.revisions})
        except PermissionError:
            return self.json(423, {"error": "locked"})
        except ValueError:
            return self.json(400, {"error": "bad request"})
        return self.json(200, {"revision": revision})

    # MARK: - Logowanie

    def login(self, body):
        ip = self.client_ip()
        if self.state.ip_blocked(ip):
            return self.json(429, {"error": "too many attempts"})
        username = str((body or {}).get("username", "")).strip()
        password = str((body or {}).get("password", ""))
        users = self.state.users
        if users.is_locked(username):
            log(f"login zablokowany: {username!r} z {ip}")
            return self.json(429, {"error": "locked"})
        if not users.check_password(username, password):
            users.record_failure(username)
            self.state.ip_failure(ip)
            log(f"błędne hasło: {username!r} z {ip}")
            return self.json(401, {"error": "invalid credentials"})
        token = secrets.token_urlsafe(32)
        user = users.users[username]
        pending = {"user": username, "created": time.time()}
        reply = {"step": "totp"}
        if not user.get("totpSecret"):
            pending["enrollSecret"] = auth.new_totp_secret()
            reply = {"step": "enroll", "secret": pending["enrollSecret"], "uri": auth.otpauth_uri(pending["enrollSecret"], username)}
        with self.state.lock:
            self.state.pending[token] = pending
        return self.json(200, reply, headers=[self.cookie("cantate_pending", token, PENDING_MAX)])

    def pending_login(self) -> tuple[str, dict] | tuple[None, None]:
        token = self.cookies().get("cantate_pending")
        with self.state.lock:
            pending = self.state.pending.get(token or "")
            if not pending or time.time() - pending["created"] > PENDING_MAX:
                self.state.pending.pop(token or "", None)
                return None, None
            return token, pending

    def finish_login(self, token: str, username: str, extra: dict | None = None):
        with self.state.lock:
            self.state.pending.pop(token, None)
        self.state.users.record_success(username)
        session = self.state.new_session(username)
        log(f"zalogowano: {username!r} z {self.client_ip()}")
        self.json(200, {"user": username, **(extra or {})},
                  headers=[self.cookie("cantate_session", session, SESSION_MAX), self.cookie("cantate_pending", "", 0)])

    def second_factor(self, body):
        token, pending = self.pending_login()
        if not pending or "enrollSecret" in pending:
            return self.json(401, {"error": "login expired"})
        username = pending["user"]
        if self.state.users.is_locked(username) or self.state.ip_blocked(self.client_ip()):
            return self.json(429, {"error": "locked"})
        if not self.state.users.check_second_factor(username, str((body or {}).get("code", ""))):
            self.state.users.record_failure(username)
            self.state.ip_failure(self.client_ip())
            log(f"błędny kod: {username!r} z {self.client_ip()}")
            return self.json(401, {"error": "invalid code"})
        self.finish_login(token, username)

    def enroll(self, body):
        token, pending = self.pending_login()
        if not pending or "enrollSecret" not in pending:
            return self.json(401, {"error": "login expired"})
        codes = self.state.users.enroll_totp(pending["user"], pending["enrollSecret"], str((body or {}).get("code", "")))
        if codes is None:
            self.state.ip_failure(self.client_ip())
            return self.json(401, {"error": "invalid code"})
        log(f"skonfigurowano aplikację uwierzytelniającą: {pending['user']!r}")
        self.finish_login(token, pending["user"], {"backupCodes": codes})

    # MARK: - Konto (zmiana hasła i aplikacji uwierzytelniającej)

    def account(self, path, body, session):
        """Każda zmiana wymaga obecnego hasła; błędne hasło liczy się do blokady jak przy logowaniu."""
        username = session["user"]
        body = body if isinstance(body, dict) else {}
        users = self.state.users
        if users.is_locked(username) or self.state.ip_blocked(self.client_ip()):
            return self.json(429, {"error": "locked"})
        token = self.cookies().get("cantate_session")
        if path == "/api/account/totp/confirm":
            secret = session.get("enrollSecret")
            if not secret or time.time() - session.get("enrollStarted", 0) > PENDING_MAX:
                return self.json(401, {"error": "start again"})
            codes = users.enroll_totp(username, secret, str(body.get("code", "")))
            if codes is None:
                self.state.ip_failure(self.client_ip())
                return self.json(401, {"error": "invalid code"})
            session.pop("enrollSecret", None)
            self.state.end_other_sessions(username, token)
            log(f"zmieniono aplikację uwierzytelniającą: {username!r}")
            return self.json(200, {"backupCodes": codes})
        if not users.check_password(username, str(body.get("current", ""))):
            users.record_failure(username)
            self.state.ip_failure(self.client_ip())
            log(f"błędne hasło przy zmianie konta: {username!r} z {self.client_ip()}")
            return self.json(401, {"error": "invalid credentials"})
        users.record_success(username)
        if path == "/api/account/password":
            try:
                users.set_password(username, str(body.get("new", "")))
            except ValueError:
                return self.json(400, {"error": "weak password", "minPasswordLength": auth.MIN_PASSWORD_LENGTH})
            self.state.end_other_sessions(username, token)
            log(f"zmieniono hasło: {username!r}")
            return self.json(200, {"ok": True})
        if path == "/api/account/totp/start":
            secret = auth.new_totp_secret()
            session.update(enrollSecret=secret, enrollStarted=time.time())
            return self.json(200, {"secret": secret, "uri": auth.otpauth_uri(secret, username)})
        if path == "/api/account/backup-codes":
            log(f"nowe kody zapasowe: {username!r}")
            return self.json(200, {"backupCodes": users.regenerate_backup_codes(username)})
        return self.json(404, {"error": "not found"})

    # MARK: - Pilot ze smartfona

    def phone_id(self) -> str:
        return self.cookies().get("cantate_session", "")

    def remote_get(self, path: str):
        session = self.current_session()
        if not session:
            if path == "/remote":
                self.send_response(302)
                self.security_headers()
                self.send_header("Location", "/login.html?next=/remote")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            return self.json(401, {"error": "unauthorized"})
        relay = self.state.remote
        if path == "/remote":
            try:
                with open(os.path.join(WEB_ROOT, "remote_page.html"), encoding="utf-8") as source:
                    template = source.read()
            except OSError:
                return self.json(404, {"error": "not found"})
            settings = self.state.storage.snapshot()["data"].get("settings") or {}
            body, csp = remote.page_with_csp(template, str(settings.get("appLanguage", "pl")) if isinstance(settings, dict) else "pl")
            return self.respond(200, body, "text/html; charset=utf-8", csp=csp)
        if path == "/api/state":
            state = relay.phone_state(self.phone_id())
            return self.respond(200, remote.encode_state(state)) if state is not None else self.json(503, {"error": "no operator"})
        if path == "/api/search":
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("q", [""])[0]
            songs = self.state.storage.snapshot()["data"].get("songs") or []
            return self.respond(200, json.dumps(remote.search(songs if isinstance(songs, list) else [], query), ensure_ascii=False).encode())
        # /api/remote/commands: długie odpytywanie przez kartę operatora.
        try:
            wait = min(25.0, max(0.0, float(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("wait", ["25"])[0])))
        except ValueError:
            wait = 25.0
        commands = relay.take_commands(wait)
        return self.json(200, {"commands": commands, "phones": relay.connected_phones()})

    def remote_post(self, path: str, body):
        relay = self.state.remote
        if path == "/api/command":
            command = remote.validate_command(body)
            if command is None:
                return self.json(400, {"error": "unknown command"})
            state = relay.send(self.phone_id(), command)
            return self.respond(200, remote.encode_state(state)) if state is not None else self.json(503, {"error": "no operator"})
        if path == "/api/remote/state":
            if not isinstance(body, dict) or len(json.dumps(body)) > remote.MAX_STATE:
                return self.json(400, {"error": "bad request"})
            relay.publish(body)
            return self.json(200, {"ok": True, "phones": relay.connected_phones()})
        relay.stop()
        return self.json(200, {"ok": True})

    def restore(self, body, session):
        if not isinstance(body, dict) or not isinstance(body.get("songs"), list):
            return self.json(400, {"error": "bad request"})
        try:
            revisions = self.state.storage.restore(body)
        except PermissionError:
            return self.json(423, {"error": "locked"})
        except ValueError:
            return self.json(400, {"error": "bad request"})
        log(f"przywrócono kopię: {session['user']!r}")
        return self.json(200, {"revisions": revisions})


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def server_bind(self):
        # Bez socket.getfqdn(): w niektórych sieciach zapytanie DNS trwa kilkadziesiąt sekund.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def make_server(data_dir: str, host: str, port: int, secure_cookies: bool, trust_proxy: bool) -> Server:
    handler = type("BoundHandler", (Handler,), {"state": State(data_dir, secure_cookies, trust_proxy)})
    return Server((host, port), handler)


# MARK: - Polecenia


def read_new_password() -> str:
    first = getpass.getpass("Nowe hasło (co najmniej 10 znaków): ")
    if first != getpass.getpass("Powtórz hasło: "):
        sys.exit("Hasła się różnią.")
    return first


def main(argv=None):
    parser = argparse.ArgumentParser(description="CantatePresenter Web: prywatny serwer")
    commands = parser.add_subparsers(dest="command", required=True)
    serve = commands.add_parser("serve", help="uruchom serwer")
    serve.add_argument("--data", required=True, help="katalog danych")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8443)
    serve.add_argument("--tls-cert")
    serve.add_argument("--tls-key")
    serve.add_argument("--behind-proxy", action="store_true", help="HTTPS w reverse proxy (zaufaj X-Forwarded-For)")
    serve.add_argument("--insecure-local", action="store_true", help="HTTP bez TLS, tylko na adresie lokalnym (testy)")
    for name in ("adduser", "passwd", "reset-2fa", "deluser"):
        command = commands.add_parser(name)
        command.add_argument("username")
        command.add_argument("--data", required=True)
    commands.add_parser("users").add_argument("--data", required=True)
    args = parser.parse_args(argv)

    os.makedirs(args.data, exist_ok=True)
    users = auth.Users(os.path.join(args.data, "users.json"))
    if args.command == "adduser":
        try:
            users.add(args.username, read_new_password())
        except ValueError as error:
            sys.exit(str(error))
        print(f"Dodano {args.username}. Przy pierwszym logowaniu skonfiguruje aplikację uwierzytelniającą.")
    elif args.command == "passwd":
        if args.username not in users.users:
            sys.exit("Nie ma takiego użytkownika.")
        try:
            users.set_password(args.username, read_new_password())
        except ValueError as error:
            sys.exit(str(error))
        print("Zmieniono hasło.")
    elif args.command == "reset-2fa":
        if args.username not in users.users:
            sys.exit("Nie ma takiego użytkownika.")
        users.reset_totp(args.username)
        print("Wyłączono kod z aplikacji; przy następnym logowaniu trzeba go skonfigurować od nowa.")
    elif args.command == "deluser":
        users.remove(args.username)
        print("Usunięto.")
    elif args.command == "users":
        for name, user in sorted(users.users.items()):
            print(f"{name}\t2FA: {'tak' if user.get('totpSecret') else 'nie skonfigurowano'}\tkody zapasowe: {len(user.get('backupCodes', []))}")
    elif args.command == "serve":
        tls = bool(args.tls_cert and args.tls_key)
        if not tls and not args.behind_proxy:
            if not args.insecure_local or not ipaddress.ip_address(args.host).is_loopback:
                sys.exit("Bez HTTPS: podaj --tls-cert/--tls-key, uruchom za reverse proxy (--behind-proxy) "
                         "albo do testów --insecure-local na 127.0.0.1.")
        if not users.users:
            print("Uwaga: brak kont. Dodaj użytkownika: server.py adduser NAZWA --data ...", file=sys.stderr)
        server = make_server(args.data, args.host, args.port, secure_cookies=tls or args.behind_proxy, trust_proxy=args.behind_proxy)
        if tls:
            context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(args.tls_cert, args.tls_key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
        log(f"CantatePresenter Web: {'https' if tls else 'http'}://{args.host}:{server.server_port}/")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
