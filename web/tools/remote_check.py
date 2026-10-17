#!/usr/bin/env python3
"""Strona pilota z aplikacji macOS i Windows (Sources/CantatePresenterCore/Resources/remote_page.html) w Chrome bez okna, na makiecie serwera.

Sprawdza: start i wznawianie projekcji, wyszukiwanie pieśni, wybór wyniku, brak przewijania w poziomie
na ekranie telefonu i brak błędów JS. Uruchomienie: python3 -I web/tools/remote_check.py [zrzut.png]
"""
import http.server, json, os, re, sys, threading, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cdp
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
page = open(os.path.join(ROOT, "Sources/CantatePresenterCore/Resources/remote_page.html"), encoding="utf-8").read().replace("{{LANG}}", "pl")
labels = {k: k.upper() for k in "next previous nextSong previousSong black clearText stop slides plan notLive offline title start resume search searchPlaceholder noResults".split()}
songs = [{"id": "11111111-1111-1111-1111-111111111111", "title": "Święty", "author": "A", "firstLine": "Hosanna", "slides": ["S1", "S2"]},
         {"id": "22222222-2222-2222-2222-222222222222", "title": "Alleluja", "author": "", "firstLine": "Pan", "slides": ["P1"]}]
st = {"live": False, "song": None, "slide": 0}
log = []
def state():
    s = st["song"]
    return {"isLive": st["live"], "isBlackScreen": False, "isClearText": False, "songTitle": s["title"] if s else "",
            "slideIndex": st["slide"], "slideText": s["slides"][st["slide"]] if s and st["live"] else "",
            "slides": [{"label": f"Z{i+1}", "preview": t} for i, t in enumerate(s["slides"])] if s else [],
            "planName": "", "plan": [], "labels": labels, "canStart": not st["live"] and s is not None,
            "startTitle": s["title"] if s and not st["live"] else ""}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, body, ct):
        b = body.encode(); self.send_response(200); self.send_header("Content-Type", ct); self.send_header("Content-Length", len(b)); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        if u.path == "/": return self.send(page, "text/html")
        if u.path == "/api/state": return self.send(json.dumps(state()), "application/json")
        if u.path == "/api/search":
            term = q.get("q", [""])[0].lower(); log.append(("search", term))
            return self.send(json.dumps([s for s in songs if term in s["title"].lower()]), "application/json")
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"]))); log.append(body)
        c = body["command"]
        if c == "song": st.update(song=next(s for s in songs if s["id"] == body["id"]), live=True, slide=0)
        elif c == "stop": st["live"] = False
        elif c == "start" and st["song"]: st["live"] = True
        elif c == "next" and st["live"]: st["slide"] = min(st["slide"] + 1, len(st["song"]["slides"]) - 1)
        self.send(json.dumps(state()), "application/json")
class S(http.server.ThreadingHTTPServer):
    def server_bind(self): self.socket.bind(self.server_address); self.server_address = self.socket.getsockname()
srv = S(("127.0.0.1", 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]
c = cdp.Browser(width=390, height=844)
problems = []
def check(cond, msg):
    if not cond: problems.append(msg)
try:
    c.goto(f"http://127.0.0.1:{port}/?t=x")
    c.wait_for("document.getElementById('next').textContent === 'START'")
    check(c.evaluate("document.getElementById('next').disabled"), "start powinien być nieaktywny bez pieśni")
    c.click("#query"); c.type("ś")
    c.wait_for("document.querySelectorAll('#results .item').length === 1")
    check(log[-1] == ("search", "ś"), f"zapytanie {log[-1]}")
    c.click("#results .item")
    c.wait_for("document.getElementById('screen').textContent === 'S1'")
    check(c.evaluate("document.getElementById('next').textContent") == "NEXT", "po starcie przycisk Dalej")
    c.click("#next"); c.wait_for("document.getElementById('screen').textContent === 'S2'")
    c.click("#stop"); c.wait_for("document.getElementById('next').textContent === 'RESUME'")
    check("Święty" in c.evaluate("document.getElementById('screen').textContent"), "tytuł do wznowienia")
    check(not c.evaluate("document.getElementById('next').disabled"), "wznów aktywny")
    c.click("#next"); c.wait_for("document.getElementById('screen').textContent === 'S2'")
    c.evaluate("document.getElementById('query').value='zzz'; document.getElementById('query').dispatchEvent(new Event('input'))")
    c.wait_for("document.querySelector('#results .empty')?.textContent === 'NORESULTS'")
    check(c.evaluate("document.documentElement.scrollWidth <= 390"), "przewijanie w poziomie")
    c.screenshot(sys.argv[1] if len(sys.argv) > 1 else "/dev/null")
    check(not c.console_errors(), f"błędy konsoli {c.console_errors()}")
finally:
    c.close()
print("Polecenia:", [l for l in log if isinstance(l, dict)])
if problems:
    print("Problemy:", *problems, sep="\n  ")
    sys.exit(1)
print("Strona pilota: 0 problemów")
