#!/usr/bin/env python3
"""Statyczny serwer do testów i podglądu wersji webowej (tylko biblioteka standardowa).

Serwuje wyłącznie web/, shared/ i VERSION z repozytorium (nigdy np. google-oauth-client.json).
http.server przy starcie pyta DNS o nazwę komputera (socket.getfqdn), co w niektórych sieciach
trwa kilkadziesiąt sekund; tutaj tego zapytania nie ma.

Użycie: python3 -I web/tools/serve.py PORT [PLIK_WYNIKU]
Z PLIK_WYNIKU strona testów wysyła wynik (POST /__test-result), a serwer zapisuje go do pliku.
"""
import http.server
import os
import socketserver
import sys
from functools import partial

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "web", "server"))
import appversion  # noqa: E402

APP_VERSION = appversion.current(ROOT)
ALLOWED = ("web/", "shared/")
ALLOWED_FILES = ("VERSION",)
RESULT_FILE = None


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".webmanifest": "application/manifest+json",
        ".svg": "image/svg+xml",
        "": "text/plain",
    }

    def translate_path(self, path):
        relative = path.split("?", 1)[0].split("#", 1)[0].lstrip("/")
        if not (relative.startswith(ALLOWED) or relative in ALLOWED_FILES):
            return os.path.join(ROOT, ".forbidden-path")
        return super().translate_path(path)

    def do_GET(self):
        # Wersja liczona z commitów zamiast plików z repozytorium (VERSION nie jest śledzony przez git).
        relative = self.path.split("?", 1)[0].lstrip("/")
        generated = {"VERSION": (APP_VERSION + "\n").encode(), "web/src/version.js": appversion.module_source(APP_VERSION)}
        if relative in generated:
            body = generated[relative]
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript" if relative.endswith(".js") else "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):
        pass

    def do_POST(self):
        if self.path != "/__test-result" or not RESULT_FILE:
            self.send_error(404)
            return
        length = min(int(self.headers.get("Content-Length", "0")), 1_000_000)
        with open(RESULT_FILE, "wb") as output:
            output.write(self.rfile.read(length))
        self.send_response(204)
        self.end_headers()


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name, self.server_port = host, port


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    RESULT_FILE = sys.argv[2] if len(sys.argv) > 2 else None
    with Server(("127.0.0.1", port), partial(Handler, directory=ROOT)) as server:
        print(f"http://127.0.0.1:{server.server_port}/web/", flush=True)
        server.serve_forever()
