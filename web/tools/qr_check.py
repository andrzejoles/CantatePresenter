#!/usr/bin/env python3
"""Sprawdza koder QR (web/src/core/qr.js) niezależnym dekoderem macOS (CoreImage): wersje 1–10, polskie znaki, otpauth://.

Użycie (macOS): python3 -I web/tools/qr_check.py
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from cdp import Browser  # noqa: E402

TEXTS = ["hello", "Zażółć gęślą jaźń", "x" * 60, "y" * 106, "z" * 152, "https://example.org/" + "a" * 180,
         "otpauth://totp/CantatePresenter%3Aala?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=CantatePresenter&algorithm=SHA1&digits=6&period=30"]

with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
server = subprocess.Popen([sys.executable, "-I", os.path.join(TOOLS, "serve.py"), str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.5)
browser = Browser(width=900, height=900)
work = tempfile.mkdtemp(prefix="cantate-qr-")
failures = 0
try:
    for index, text in enumerate(TEXTS):
        browser.goto(f"http://127.0.0.1:{port}/web/tests/qr-render.html?t=" + urllib.parse.quote(json.dumps([text])))
        browser.wait_for("document.body.dataset.ready === '1' && location.search.length > 3")
        time.sleep(0.2)
        path = os.path.join(work, f"qr{index}.png")
        browser.screenshot(path)
        decoded = subprocess.run(["swift", os.path.join(TOOLS, "qr_decode.swift"), path], capture_output=True, text=True).stdout.strip()
        ok = decoded == text
        failures += not ok
        print(("✔" if ok else "✘"), f"{len(text)} znaków")
finally:
    browser.close()
    server.terminate()
print(f"{'✔' if not failures else '✘'} QR: {failures} błędów")
sys.exit(1 if failures else 0)
