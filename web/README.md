# CantatePresenter Web

Prywatna aplikacja webowa z tym samym formatem danych, tłumaczeniami i logiką co wersja macOS.
Dostęp tylko po zalogowaniu: **hasło + kod z aplikacji uwierzytelniającej (TOTP)**. Dane są na serwerze,
więc ta sama biblioteka jest dostępna z każdego komputera po zalogowaniu.

- Bez zależności: przeglądarka (moduły ES, bez kroku budowania) i serwer w Pythonie 3.10+ (tylko biblioteka standardowa).
- Dane w katalogu serwera: `songs.json`, `plans.json`, `settings.json` (format macOS), `ccliUsage.json` (raport CCLI,
  w kopii jako `ccli_usage.json`), `extraFiles.json` (pliki z kopii macOS, np. własne logo), `history/` (5 poprzednich
  wersji każdego pliku), `users.json` (konta, prawa 0600), `before-restore.json` (cofnięcie przywrócenia kopii).
- Kopia `.cantatebackup` działa w obie strony między wersją webową a macOS.
- Okno projekcji: przycisk „Otwórz okno projekcji”, potem przenieś okno na projektor i kliknij dwukrotnie (pełny ekran).
  W Chrome okno może od razu otworzyć się na drugim ekranie (zgoda na zarządzanie oknami).
- Jak w macOS: plansza startowa z logo (23 wzory, wybór w Ustawieniach), wyszukiwanie w Wikiźródłach (przycisk „Online”),
  import baz Holyrics (`.mufl`, `.muf`, `.hly`, XML) i plików SongSelect, raport użycia CCLI (CSV), ekran dla muzyków.
- Ekran dla muzyków (przycisk „Muzycy”): bieżący i następny slajd z chwytami nad tekstem. Na tym samym komputerze
  otwiera się w osobnym oknie; na tabletach otwórz `https://ADRES/musicians.html` i zaloguj się (stan projekcji
  przychodzi przez serwer). Każde urządzenie ma własną transpozycję i wielkość czcionki.

## Uruchomienie na serwerze

1. Skopiuj repozytorium (wystarczy katalog `web/`) np. do `/opt/cantate` i utwórz użytkownika systemowego `cantate`. Przy kopii bez katalogu `.git` zapisz najpierw numer wersji: `scripts/version.sh > web/VERSION` (inaczej aplikacja pokaże wersję „dev”).
2. Dodaj konto (hasło co najmniej 10 znaków; drugi składnik konfiguruje się przy pierwszym logowaniu kodem QR):
   ```bash
   sudo -u cantate python3 -I /opt/cantate/web/server/server.py adduser ala --data /var/lib/cantate
   ```
3. HTTPS: [Caddy](https://caddyserver.com) z `deploy/Caddyfile` (certyfikat automatycznie), a serwer aplikacji jako
   usługa z `deploy/cantate.service` (słucha tylko na `127.0.0.1`, `--behind-proxy`).
4. Alternatywnie bez proxy: `serve --host 0.0.0.0 --port 8443 --tls-cert cert.pem --tls-key key.pem`.

Serwer nie uruchomi się bez HTTPS; wyjątek to `--insecure-local` na `127.0.0.1` (testy, praca na jednym komputerze).

### Konta

```bash
server.py users --data DANE              # lista kont i stan 2FA
server.py passwd NAZWA --data DANE        # nowe hasło
server.py reset-2fa NAZWA --data DANE     # utracony telefon: konfiguracja TOTP od nowa przy logowaniu
server.py deluser NAZWA --data DANE
```

Przy pierwszym logowaniu użytkownik skanuje kod QR (Google Authenticator, Microsoft Authenticator, 1Password itp.)
i dostaje 8 jednorazowych kodów zapasowych. Zmiana hasła, nowa aplikacja uwierzytelniająca i nowe kody zapasowe są też
w aplikacji (kliknij swoją nazwę na górnym pasku); każda zmiana wymaga obecnego hasła i wylogowuje inne urządzenia.

## Bezpieczeństwo

- Hasła: `scrypt` (N=2^15). Kody TOTP: RFC 6238, okno ±30 s, ten sam kod nie zadziała drugi raz.
- 5 nieudanych prób blokuje konto na 15 minut; 20 nieudanych prób z jednego adresu IP blokuje ten adres na 15 minut.
- Sesja w ciasteczku `HttpOnly`, `SameSite=Strict`, `Secure` (przy HTTPS); wygasa po 12 h bezczynności, najpóźniej po 7 dniach.
  Restart serwera wylogowuje wszystkich.
- Bez sesji dostępna jest tylko strona logowania; aplikacja, dane i okno projekcji wymagają zalogowania.
- Żądania zmieniające dane wymagają nagłówka `X-Cantate-Request` i zgodnego `Origin` (ochrona przed CSRF).
- Nagłówki: Content-Security-Policy bez skryptów i stylów w HTML, `frame-ancestors 'none'`, HSTS przy HTTPS.
- Serwer nie udostępnia `server/`, `tools/`, `tests/` ani plików ukrytych.
- Wyszukiwanie „Online” łączy się z przeglądarki tylko z `*.wikisource.org` (CSP `connect-src`); nic nie trafia do innych usług.

## Rozwój i testy

```bash
python3 -I -m unittest discover -s web/server/tests   # serwer: hasła, TOTP, logowanie, blokady, CSRF, dane
web/run-tests.sh                                      # logika (wspólne pliki z shared/fixtures), dane, kopie
python3 -I web/tools/ui_check.py [katalog_na_zrzuty]  # interfejs przez prawdziwy serwer z logowaniem TOTP
python3 -I web/tools/qr_check.py                      # koder QR sprawdzany dekoderem macOS
scripts/sync_web_translations.sh                      # kopia katalogu tłumaczeń z aplikacji macOS
```

Testy przeglądarkowe używają Chrome bez okna (`web/tools/cdp.py`, protokół DevTools, bez zależności).
`web/tools/serve.py` to statyczny serwer tylko do testów logiki (bez logowania).
`web/tools/remote_check.py` sprawdza stronę pilota z aplikacji macOS. Logo planszy: `python3 -I scripts/export_web_logos.py`
po zmianie `LogoPreset.swift`.

Wspólna logika ma wzorzec w wersji macOS: `shared/fixtures/` (podział na slajdy, wyszukiwanie, transpozycja, skróty,
chwyty dla muzyków, Wikiźródła, import Holyrics, kopia z macOS) sprawdzają testy Swift i JS.
