#!/usr/bin/env python3
"""Statyczny serwer do testów i podglądu wersji webowej (tylko biblioteka standardowa).

Serwuje wyłącznie web/, shared/ i VERSION z repozytorium (nigdy np. google-oauth-client.json).
http.server przy starcie pyta DNS o nazwę komputera (socket.getfqdn), co w niektórych sieciach
trwa kilkadziesiąt sekund; tutaj tego zapytania nie ma.

Użycie: python3 -I web/tools/serve.py PORT
"""
import http.server
import os
import socketserver
import sys
from functools import partial

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOWED = ("web/", "shared/")
ALLOWED_FILES = ("VERSION",)


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

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name, self.server_port = host, port


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    with Server(("127.0.0.1", port), partial(Handler, directory=ROOT)) as server:
        print(f"http://127.0.0.1:{server.server_port}/web/", flush=True)
        server.serve_forever()
