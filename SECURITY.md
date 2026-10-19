# Bezpieczeństwo

## Wspierane wersje

Poprawki bezpieczeństwa trafiają tylko do najnowszego wydania (macOS, Windows i wersja webowa mają wspólny numer wersji). Aplikacje na macOS i Windows aktualizują się same; wersję webową aktualizuje się, podmieniając katalog `web/` (`web/README.md`).

| Wersja | Wsparcie |
| --- | --- |
| najnowsze wydanie z [Releases](https://github.com/andrzejoles/CantatePresenter/releases/latest) | tak |
| starsze | nie, zaktualizuj aplikację |

## Zgłaszanie podatności

Nie opisuj podatności w publicznych zgłoszeniach (Issues). Użyj prywatnego formularza GitHuba: zakładka **Security** → **Report a vulnerability** ([bezpośredni odnośnik](https://github.com/andrzejoles/CantatePresenter/security/advisories/new)).

Przydatne informacje: wersja i system, czego dotyczy problem (aplikacja macOS, Windows, serwer webowy, pilot w sieci lokalnej, aktualizacje, kopie zapasowe), kroki do odtworzenia i możliwe skutki. Odpowiedź w ciągu 7 dni; poprawka trafia do kolejnego wydania, a zgłaszający jest wymieniony w opisie wydania, jeśli tego chce.

English: please report vulnerabilities privately via **Security → Report a vulnerability** on GitHub, not in public issues.

## Model bezpieczeństwa

- **Dane** są lokalne (macOS: `~/Library/Application Support/CantatePresenter`, Windows: `%APPDATA%\CantatePresenter`, web: katalog danych serwera). Aplikacja nie wysyła ich nigdzie poza kopiami na Dysk Google, gdy użytkownik je włączy.
- **Dysk Google:** logowanie OAuth w przeglądarce (loopback `127.0.0.1` + PKCE), dostęp tylko do plików utworzonych przez aplikację. Tokeny wyłącznie w Pęku kluczy macOS albo w Menedżerze poświadczeń Windows, nigdy w plikach ustawień ani kopiach.
- **Aktualizacje:** macOS przez Sparkle z podpisem EdDSA każdego archiwum; Windows pobiera instalator tylko z wydań tego repozytorium przez HTTPS i sprawdza rozmiar i sumę SHA-256 podaną przez GitHub. Wydania nie są podpisane certyfikatem Apple Developer ID ani Authenticode (macOS i SmartScreen pokazują ostrzeżenie przy pierwszym uruchomieniu).
- **Pilot i ekran dla muzyków** (sieć lokalna): serwer działa tylko po włączeniu, dostęp wymaga losowego tokenu 128-bitowego z kodu QR (porównanie w stałym czasie); kod dla muzyków pozwala tylko na podgląd. „Nowy kod” unieważnia stare połączenia. Ruch w sieci lokalnej nie jest szyfrowany, więc pilota używaj w zaufanej sieci.
- **Wersja webowa:** prywatny serwer z logowaniem hasłem (scrypt) i kodem TOTP, blokadą prób, sesjami HttpOnly/SameSite=Strict, ochroną CSRF i polityką CSP; szczegóły w `web/README.md`. Serwer należy wystawiać przez HTTPS.
- **Import plików i kopie zapasowe:** archiwum kopii rozpakowuje się do katalogu tymczasowego, a do danych trafiają tylko znane pliki (`songs.json`, `plans.json`, `settings.json` i kilka innych); poprzedni stan zostaje do cofnięcia. Czytnik plików Holyrics sprawdza zakresy i ma limit zagnieżdżenia. Nieczytelne pliki danych trafiają do kwarantanny zamiast być nadpisane.
