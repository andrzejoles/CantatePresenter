#!/usr/bin/env python3
"""Wzorzec kodów QR dla innych wersji (shared/fixtures/qr.json): macierze z web/src/core/qr.js w Chrome.

Koder JS sprawdza niezależny dekoder CoreImage (web/tools/qr_check.py); wersja Windows musi dać te same moduły.
Użycie: python3 -I web/tools/make_qr_fixture.py
"""
import json
import os
import socket
import subprocess
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(TOOLS, "..", ".."))
sys.path.insert(0, TOOLS)
from cdp import Browser  # noqa: E402

TEXTS = ["hello", "Zażółć gęślą jaźń", "x" * 60, "y" * 106, "z" * 152, "https://example.org/" + "a" * 180,
         "http://192.168.1.20:8765/?t=Qm9ndXNfdG9rZW5fMTIzNDU2", "http://10.0.0.5:51234/stage?t=AbCdEfGhIjKlMnOpQrStUv"]

with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
server = subprocess.Popen([sys.executable, "-I", os.path.join(TOOLS, "serve.py"), str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.5)
browser = Browser(width=400, height=300)
try:
    browser.goto(f"http://127.0.0.1:{port}/web/tests/qr-render.html?t=%5B%5D")
    browser.wait_for("document.body.dataset.ready === '1'")
    cases = browser.evaluate(
        "import('/web/src/core/qr.js').then(m => JSON.stringify(" + json.dumps(TEXTS)
        + ".map(text => ({ text, rows: m.encodeQR(text).map(r => r.map(d => d ? '1' : '0').join('')) }))))")
finally:
    browser.close()
    server.terminate()
cases = json.loads(cases)
with open(os.path.join(ROOT, "shared", "fixtures", "qr.json"), "w", encoding="utf-8") as out:
    json.dump(cases, out, ensure_ascii=False, indent=1)
    out.write("\n")
print(f"qr.json: {len(cases)} kodów")
