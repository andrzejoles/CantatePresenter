#!/usr/bin/env python3
"""Test interfejsu wersji webowej przez prawdziwy serwer: logowanie z TOTP, aplikacja, zapis danych, zrzuty.

Użycie: python3 -I web/tools/ui_check.py [KATALOG_NA_ZRZUTY]
"""
import base64
import os
import socket
import subprocess
import sys
import tempfile
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(TOOLS))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(ROOT, "web/server"))
from cdp import Browser  # noqa: E402
import auth  # noqa: E402

out = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="cantate-ui-")
os.makedirs(out, exist_ok=True)
data = tempfile.mkdtemp(prefix="cantate-data-")
PASSWORD = "haslo-testowe-123"
NEW_PASSWORD = "nowe-haslo-testowe-456"
auth.Users(os.path.join(data, "users.json")).add("ala", PASSWORD)

with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
server = subprocess.Popen([sys.executable, "-I", os.path.join(ROOT, "web/server/server.py"), "serve", "--data", data,
                           "--port", str(port), "--insecure-local"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(100):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
        break
    except OSError:
        time.sleep(0.05)
base = f"http://127.0.0.1:{port}"
browser = Browser()
failures = []


def check(name, condition):
    print(("✔ " if condition else "✘ ") + name)
    if not condition:
        failures.append(name)


def count(selector):
    return browser.evaluate(f"document.querySelectorAll({selector!r}).length")


def login_password(password=PASSWORD):
    browser.wait_for("document.querySelector('input[name=username]') !== null")
    browser.click("input[name=username]")
    browser.type("ala")
    browser.click("input[name=password]")
    browser.type(password)
    browser.key("Enter", "Enter", "\r")


try:
    browser.goto(f"{base}/")
    browser.wait_for("location.pathname === '/login.html'")
    check("bez logowania: przekierowanie na stronę logowania", True)
    browser.wait_for("document.querySelector('input[name=username]') !== null")
    browser.screenshot(os.path.join(out, "0-login.png"))

    login_password()
    browser.wait_for("document.querySelector('.qr svg') !== null")
    check("pierwsze logowanie: kod QR do aplikacji uwierzytelniającej", True)
    browser.screenshot(os.path.join(out, "0-enroll.png"))
    secret = browser.evaluate("document.querySelector('.secret').textContent.replace(/\\s+/g, '')")
    browser.click(".code-input")
    browser.type("000000")
    browser.key("Enter", "Enter", "\r")
    browser.wait_for("document.querySelector('.login-error').textContent.length > 0")
    check("błędny kod odrzucony", True)
    browser.evaluate("document.querySelector('.code-input').value = ''")
    browser.type(auth.totp(secret, auth.totp_counter()))
    browser.key("Enter", "Enter", "\r")
    browser.wait_for("document.querySelectorAll('.backup-codes li').length === 8")
    check("kody zapasowe pokazane raz (8)", True)
    browser.screenshot(os.path.join(out, "0-backup-codes.png"))
    browser.click("input[type=checkbox]")
    browser.click("button.primary")

    browser.wait_for("document.querySelectorAll('.song-row').length > 0")
    check("po zalogowaniu: biblioteka z przykładowymi pieśniami", count(".song-row") == 2)
    check("nazwa użytkownika na pasku", "ala" in browser.evaluate("document.querySelector('.user-chip').textContent"))
    browser.screenshot(os.path.join(out, "1-start.png"))

    browser.click(".song-row")
    browser.wait_for("document.querySelectorAll('.slide-card').length > 0")
    check("wybór pieśni pokazuje slajdy", count(".slide-card") >= 2)
    browser.key("Enter", "Enter", "\r")
    browser.wait_for("document.querySelector('.slide-card.live') !== null")
    check("Enter: start projekcji", browser.evaluate("document.querySelector('.live-head .pill').classList.contains('on')"))
    browser.key("ArrowRight", "ArrowRight")
    check("strzałka w prawo: następny slajd", browser.evaluate("[...document.querySelectorAll('.slide-card')].findIndex(c => c.classList.contains('live'))") == 1)
    # Podgląd rysuje się po zmianie slajdu asynchronicznie; bez czekania test bywał niestabilny.
    browser.wait_for("document.querySelector('.preview.live .slide-text > div') !== null")
    check("tekst mieści się w podglądzie (Auto-Fit)", browser.evaluate(
        "(() => { const p = document.querySelector('.preview.live'); const t = p.querySelector('.slide-text > div'); if (!t) return false; const a = p.getBoundingClientRect(), b = t.getBoundingClientRect(); return b.top >= a.top - 1 && b.bottom <= a.bottom + 1 && b.width <= a.width + 1; })()"))
    browser.key("KeyB", "b", "b")
    check("B: czarny ekran", browser.evaluate("[...document.querySelectorAll('.controls button')].some(b => b.classList.contains('on'))"))
    browser.key("KeyB", "b", "b")
    browser.screenshot(os.path.join(out, "2-live.png"))

    browser.click("#search")
    browser.type("ocalil")
    time.sleep(0.2)
    check("wyszukiwanie bez polskich znaków", count(".song-row") == 1)
    check("fragment tekstu przy wyniku", "ocalił" in (browser.evaluate("document.querySelector('.snippet')?.textContent") or ""))
    browser.key("KeyB", "b", "b")
    check("B w polu wyszukiwania pisze literę", browser.evaluate("document.getElementById('search').value") == "ocalilb")
    browser.key("Escape", "Escape")
    check("Esc wychodzi z pola wyszukiwania", browser.evaluate("document.activeElement?.id") != "search")
    browser.key("Escape", "Escape")
    check("Esc poza polem kończy projekcję", not browser.evaluate("document.querySelector('.live-head .pill').classList.contains('on')"))

    browser.click(".tabs button:nth-child(2)")
    browser.wait_for("document.querySelectorAll('.plan-item').length > 0")
    check("plan z pieśniami", count(".plan-item") == 2)

    browser.key("KeyT", "t", None, 4)
    browser.wait_for("document.querySelector('dialog[open]') !== null")
    browser.type("Ogłoszenie parafialne")
    browser.click("dialog .primary")
    time.sleep(0.2)
    check("szybki tekst na ekranie", browser.evaluate("document.querySelector('.song-head .title')?.textContent") == "Szybki tekst")

    # Nowa pieśń zapisuje się na serwerze i jest po przeładowaniu.
    browser.click(".toolbar button[title='Nowa pieśń']")
    browser.wait_for("document.querySelector('dialog[open] input') !== null")
    browser.type("Pieśń z przeglądarki")
    browser.evaluate("document.querySelectorAll('dialog textarea')[0].value = 'Pierwsza zwrotka\\n\\nDruga zwrotka'")
    browser.evaluate("document.querySelectorAll('dialog textarea')[1].value = 'G        D\\nPierwsza zwrotka\\n\\nDruga zwrotka'")
    browser.click("dialog .primary")
    time.sleep(1.0)
    browser.goto(f"{base}/")
    browser.wait_for("document.querySelectorAll('.song-row').length > 0")
    check("nowa pieśń zapisana na serwerze", count(".song-row") == 3)

    # Ekran dla muzyków na innym urządzeniu: stan projekcji przez serwer, chwyty nad tekstem, transpozycja.
    browser.evaluate("[...document.querySelectorAll('.song-row')].find(r => r.textContent.includes('Pieśń z przeglądarki')).click()")
    browser.wait_for("document.querySelector('.song-head .title')?.textContent === 'Pieśń z przeglądarki'")
    browser.key("Enter", "Enter", "\r")
    browser.wait_for("document.querySelector('.live-head .pill.on') !== null")
    time.sleep(0.6)
    browser.goto(f"{base}/musicians.html")
    browser.wait_for("document.querySelector('.row.chords') !== null")
    check("muzycy: chwyty nad tekstem", browser.evaluate("document.querySelector('.row.chords').textContent.trim()") == "G        D")
    check("muzycy: tekst slajdu", "Pierwsza zwrotka" in browser.evaluate("document.getElementById('main').textContent"))
    check("muzycy: następny slajd", browser.evaluate("document.querySelector('.next') !== null"))
    browser.click("#tUp")
    browser.click("#tUp")
    browser.wait_for("document.getElementById('tValue').textContent === '+2'")
    check("muzycy: transpozycja +2", browser.evaluate("document.querySelector('.row.chords').textContent.trim()") == "A        E")
    browser.screenshot(os.path.join(out, "3-musicians.png"))
    browser.click("#tDown")
    browser.click("#tDown")
    browser.goto(f"{base}/")
    browser.wait_for("document.querySelectorAll('.song-row').length > 0")

    browser.click(".toolbar button[title='Ustawienia']")
    browser.wait_for("document.querySelector('dialog[open]') !== null")
    browser.screenshot(os.path.join(out, "3-settings.png"))
    browser.click("dialog .dialog-head button")

    # Import bazy Holyrics (.mufl): trzy pieśni, przy drugim imporcie same duplikaty.
    with open(os.path.join(ROOT, "shared/fixtures/holyrics-music-list.mufl"), "rb") as source:
        mufl = base64.b64encode(source.read()).decode()
    def import_mufl():
        browser.click(".toolbar button[title='Import/Eksport']")
        browser.wait_for("document.querySelector('dialog[open] input[type=file]') !== null")
        browser.evaluate(f"""(() => {{
          const bytes = Uint8Array.from(atob('{mufl}'), c => c.charCodeAt(0));
          const transfer = new DataTransfer();
          transfer.items.add(new File([bytes], 'biblioteka.mufl'));
          const input = document.querySelector('dialog[open] input[type=file]');
          input.files = transfer.files;
          input.dispatchEvent(new Event('change'));
        }})()""")
        browser.wait_for("document.querySelector('.toast') !== null")
        text = browser.evaluate("document.querySelector('.toast').textContent")
        browser.evaluate("document.querySelectorAll('.toast').forEach(t => t.remove())")
        return text
    first = import_mufl()
    check(f"import .mufl: trzy pieśni ({first})", first.startswith("Zaimportowano 3 pieśni.") and count(".song-row") == 6)
    second = import_mufl()
    check(f"import .mufl drugi raz: duplikaty pominięte ({second})", "Pominięto duplikaty: 3." in second and count(".song-row") == 6)

    # Konto: zmiana hasła z poziomu aplikacji, potem logowanie nowym hasłem.
    browser.click(".user-chip")
    browser.wait_for("document.querySelectorAll('dialog[open] input[type=password]').length === 3")
    browser.evaluate(f"(() => {{ const [c, n, r] = document.querySelectorAll('dialog[open] input[type=password]'); c.value = {PASSWORD!r}; n.value = r.value = {NEW_PASSWORD!r}; }})()")
    browser.evaluate("[...document.querySelectorAll('dialog[open] button')].find(b => b.textContent === 'Zmień hasło').click()")
    browser.wait_for("document.querySelector('dialog[open] [role=status]')?.textContent.startsWith('Hasło zmienione')")
    check("konto: zmiana hasła", True)
    browser.screenshot(os.path.join(out, "4-account.png"))
    browser.click("dialog .dialog-head button")

    errors = browser.console_errors()
    check(f"bez błędów w konsoli {errors[:3]}", not errors)

    browser.click(".toolbar button[title='Wyloguj']")
    browser.wait_for("location.pathname === '/login.html'")
    check("wylogowanie", True)
    login_password(NEW_PASSWORD)
    browser.wait_for("document.querySelector('.code-input') !== null")
    check("kolejne logowanie: pytanie o kod (bez ponownej konfiguracji)", browser.evaluate("document.querySelector('.qr') === null"))
finally:
    browser.close()
    server.terminate()

print(f"{'✔' if not failures else '✘'} Interfejs web: {len(failures)} problemów (zrzuty: {out})")
sys.exit(1 if failures else 0)
