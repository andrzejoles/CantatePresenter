#!/usr/bin/env python3
"""Strony pilota i ekranu dla muzyków z aplikacji macOS w Chrome bez okna, na makiecie serwera.

Pilot (Sources/CantatePresenterCore/Resources/remote_page.html): start i wznawianie projekcji, wyszukiwanie pieśni,
wybór wyniku, brak przewijania w poziomie na ekranie telefonu i brak błędów JS.
Muzycy (stage_page.html, R1-02): bieżący i następny slajd z chwytami, transpozycja, tytuły ze znakami `$`,
brak przewijania w poziomie na tablecie i brak błędów JS.
Uruchomienie: python3 -I scripts/remote_check.py [zrzut-pilota.png [zrzut-muzyków.png]]
"""
import http.server, json, os, sys, threading, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cdp
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RESOURCES = os.path.join(ROOT, "Sources/CantatePresenterCore/Resources")


def resource(name):
    with open(os.path.join(RESOURCES, name), encoding="utf-8") as f:
        return f.read().replace("{{LANG}}", "pl")


remote_page = resource("remote_page.html")
stage_page = resource("stage_page.html")
labels = {k: k.upper() for k in "next previous nextSong previousSong black clearText stop slides plan notLive offline title start resume search searchPlaceholder noResults".split()}
stage_labels = {"title": "Ekran dla muzyków", "key": "Tonacja: {0}", "next": "Następny slajd", "nextSong": "Następnie: {0}",
                "borrowed": "Chwyty jak w: {0}", "noChords": "Brak chwytów", "notLive": "Brak aktywnej prezentacji",
                "black": "CZARNY EKRAN", "clear": "TEKST UKRYTY", "transpose": "Transpozycja", "font": "Czcionka", "offline": "OFFLINE"}
# Tytuł z wzorcami `$'` i `$&`, które String.replace z tekstem zamiany by rozwinął (R3-13).
NEXT_SONG = "Pieśń $' za $& 5$"
songs = [{"id": "11111111-1111-1111-1111-111111111111", "title": "Święty", "author": "A", "firstLine": "Hosanna", "slides": ["S1", "S2"]},
         {"id": "22222222-2222-2222-2222-222222222222", "title": "Alleluja", "author": "", "firstLine": "Pan", "slides": ["P1"]}]
st = {"live": False, "song": None, "slide": 0, "stageLive": True}
log = []
CHORDS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def state():
    s = st["song"]
    return {"isLive": st["live"], "isBlackScreen": False, "isClearText": False, "songTitle": s["title"] if s else "",
            "slideIndex": st["slide"], "slideText": s["slides"][st["slide"]] if s and st["live"] else "",
            "slides": [{"label": f"Z{i+1}", "preview": t} for i, t in enumerate(s["slides"])] if s else [],
            "planName": "", "plan": [], "labels": labels, "canStart": not st["live"] and s is not None,
            "startTitle": s["title"] if s and not st["live"] else ""}


def stage(semitones):
    chord = CHORDS[semitones % 12]
    stage = {"isLive": st["stageLive"], "isBlackScreen": False, "isClearText": False, "songTitle": "Barka", "author": "",
             "key": chord, "semitones": semitones, "position": "1/2", "hasChords": True, "nextSongTitle": NEXT_SONG,
             "current": None, "next": None}
    if st["stageLive"]:
        stage["current"] = {"label": "Zwrotka 1", "borrowedFrom": "Zwrotka $'1", "lines": [
            {"chords": f"{chord}          a", "text": "Pan kiedyś stanął nad brzegiem,"},
            {"text": "szukał ludzi gotowych pójść za Nim"}]}
        stage["next"] = {"label": "Refren", "lines": [{"chords": "G  e", "text": "O Panie, to Ty na mnie spojrzałeś"}]}
    return {"stage": stage, "labels": stage_labels}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send(self, body, ct):
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", len(b))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/": return self.send(remote_page, "text/html")
        if u.path == "/stage": return self.send(stage_page, "text/html")
        if u.path == "/api/state": return self.send(json.dumps(state()), "application/json")
        if u.path == "/api/stage":
            semitones = int(q.get("transpose", ["0"])[0])
            log.append(("stage", semitones))
            return self.send(json.dumps(stage(semitones)), "application/json")
        if u.path == "/api/search":
            term = q.get("q", [""])[0].lower()
            log.append(("search", term))
            return self.send(json.dumps([s for s in songs if term in s["title"].lower()]), "application/json")
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        log.append(body)
        c = body["command"]
        if c == "song": st.update(song=next(s for s in songs if s["id"] == body["id"]), live=True, slide=0)
        elif c == "stop": st["live"] = False
        elif c == "start" and st["song"]: st["live"] = True
        elif c == "next" and st["live"]: st["slide"] = min(st["slide"] + 1, len(st["song"]["slides"]) - 1)
        self.send(json.dumps(state()), "application/json")


class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()


problems = []


def check(cond, msg):
    if not cond: problems.append(msg)


def text(browser, selector):
    return browser.evaluate(f"document.querySelector({json.dumps(selector)})?.textContent")


def check_remote(port, screenshot):
    c = cdp.Browser(width=390, height=844)
    try:
        c.goto(f"http://127.0.0.1:{port}/?t=x")
        c.wait_for("document.getElementById('next').textContent === 'START'")
        check(c.evaluate("document.getElementById('next').disabled"), "pilot: start powinien być nieaktywny bez pieśni")
        c.click("#query"); c.type("ś")
        c.wait_for("document.querySelectorAll('#results .item').length === 1")
        check(log[-1] == ("search", "ś"), f"pilot: zapytanie {log[-1]}")
        c.click("#results .item")
        c.wait_for("document.getElementById('screen').textContent === 'S1'")
        check(c.evaluate("document.getElementById('next').textContent") == "NEXT", "pilot: po starcie przycisk Dalej")
        c.click("#next"); c.wait_for("document.getElementById('screen').textContent === 'S2'")
        c.click("#stop"); c.wait_for("document.getElementById('next').textContent === 'RESUME'")
        check("Święty" in c.evaluate("document.getElementById('screen').textContent"), "pilot: tytuł do wznowienia")
        check(not c.evaluate("document.getElementById('next').disabled"), "pilot: wznów aktywny")
        c.click("#next"); c.wait_for("document.getElementById('screen').textContent === 'S2'")
        c.evaluate("document.getElementById('query').value='zzz'; document.getElementById('query').dispatchEvent(new Event('input'))")
        c.wait_for("document.querySelector('#results .empty')?.textContent === 'NORESULTS'")
        check(c.evaluate("document.documentElement.scrollWidth <= 390"), "pilot: przewijanie w poziomie")
        c.screenshot(screenshot)
        check(not c.console_errors(), f"pilot: błędy konsoli {c.console_errors()}")
    finally:
        c.close()


def check_stage(port, screenshot):
    width = 768
    c = cdp.Browser(width=width, height=1024)
    try:
        c.goto(f"http://127.0.0.1:{port}/stage?t=m")
        c.wait_for("document.querySelector('#main .label')?.textContent === 'Zwrotka 1'")
        check(text(c, "#song") == "Barka", f"muzycy: tytuł {text(c, '#song')!r}")
        check(text(c, "#meta .key") == "Tonacja: C", f"muzycy: tonacja {text(c, '#meta .key')!r}")
        check(c.evaluate("document.querySelector('#main .row.chords').textContent.startsWith('C ')"), "muzycy: chwyty nad tekstem")
        check(text(c, "#main .note") == "Chwyty jak w: Zwrotka $'1", f"muzycy: pożyczone chwyty {text(c, '#main .note')!r}")
        check(text(c, ".next-title") == "Następnie: " + NEXT_SONG, f"muzycy: następna pieśń {text(c, '.next-title')!r}")
        check(c.evaluate("document.documentElement.scrollWidth <= %d" % width), "muzycy: przewijanie w poziomie")
        c.click("#tUp")
        c.wait_for("document.getElementById('tValue').textContent === '+1'")
        c.wait_for("document.querySelector('#meta .key')?.textContent === 'Tonacja: C#'")
        check(("stage", 1) in log, "muzycy: transpozycja nie trafiła do serwera")
        c.screenshot(screenshot)
        st["stageLive"] = False
        c.wait_for("document.querySelector('#main .empty')?.textContent === 'Brak aktywnej prezentacji'")
        check(c.evaluate("[...document.querySelectorAll('#main .empty')].map(e => e.textContent)[1]") == "Następnie: " + NEXT_SONG,
              "muzycy: następna pieśń bez projekcji")
        check(not c.console_errors(), f"muzycy: błędy konsoli {c.console_errors()}")
    finally:
        c.close()


server = Server(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    check_remote(server.server_address[1], sys.argv[1] if len(sys.argv) > 1 else "/dev/null")
    check_stage(server.server_address[1], sys.argv[2] if len(sys.argv) > 2 else "/dev/null")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print("Polecenia:", [l for l in log if isinstance(l, dict)])
if problems:
    print("Problemy:", *problems, sep="\n  ")
    sys.exit(1)
print("Strony pilota i muzyków: 0 problemów")
