# CantatePresenter

Natywna aplikacja macOS (Apple Silicon, macOS 14+) do projekcji tekstów pieśni na projektorze lub drugim ekranie. SwiftUI + AppKit, Swift Package Manager. Jedyna zależność: **Sparkle** (automatyczne aktualizacje, wersja przypięta w `Package.swift`, decyzja właściciela 2026-10-16). Interfejs i dokumentacja użytkownika są po polsku.

## Komendy

```bash
swift build                 # szybka kompilacja debug, sprawdzaj po każdej zmianie
swift build -c release      # build release (używany przez build_app.sh)
./build_app.sh              # składa CantatePresenter.app (Info.plist inline, podpis ad-hoc z Hardened Runtime)
./run.sh                    # buduje .app (przyrostowo) i uruchamia
open CantatePresenter.app   # uruchomienie już zbudowanej aplikacji
./build_installer.sh        # PKG + DMG do dist/
scripts/version.sh          # wersja: (1 + PR/10).(PR mod 10).(commity od ostatniego scalonego PR)
xed .                       # otwarcie pakietu w Xcode
swift test                  # testy (Swift Testing, wymaga pełnego Xcode); to samo robi CI na GitHubie
gh run list --limit 3       # wyniki CI (gh zalogowane, token z uprawnieniem workflow)
```

- `swift run` działa, ale mikrofon/dyktowanie nie mają wtedy uprawnień (brak Info.plist). Do sprawdzania funkcji używaj `./build_app.sh` + `open`.
- Logowanie Google: `build_app.sh` wbudowuje klienta OAuth (typ „Aplikacja komputerowa”, projekt `CantatePresenter` w Google Cloud Console) z pliku `google-oauth-client.json` w katalogu głównym (albo `$GOOGLE_OAUTH_CLIENT_JSON`) do Info.plist (`CantateGoogleClientID`, `CantateGoogleClientSecret`). Plik jest w `.gitignore`; nigdy go nie commituj ani nie wypisuj jego zawartości. Bez pliku przycisk logowania jest nieaktywny. Aplikacja jest niezweryfikowana: logować mogą się tylko użytkownicy testowi dodani w konsoli (do 100).
- Próby na kopii danych: `CANTATE_DATA_DIR=/ścieżka/do/kopii CantatePresenter.app/Contents/MacOS/CantatePresenter`. Zmiana `HOME` **nie** przekierowuje Application Support.
- Numer wersji nie jest nigdzie zapisany ręcznie (decyzja właściciela 2026-10-16): `scripts/version.sh` liczy scalone PR (commity „Merge pull request #” w historii pierwszego rodzica) i commity od ostatniego z nich: 8 PR + 3 commity = 1.8.3, 10 PR = 2.0.0. PR scalaj zwykłym „Merge pull request” (nie squash), inaczej się nie policzy. Numer kompilacji to liczba wszystkich commitów. Pliku `VERSION` nie ma w repozytorium. CI potrzebuje pełnej historii (`fetch-depth: 0`).
- Nie ma lintera ani formatera w projekcie. Trzymaj się stylu istniejącego kodu.

## Architektura

```
Sources/CantatePresenter/main.swift  cel wykonywalny: tylko start NSApplication
Sources/CantatePresenterCore/        biblioteka z całym kodem aplikacji
  App/AppDelegate.swift  ręcznie budowane NSMenu, okno główne, zamykanie
  Models/        Song, SongSlide (SlideType), ServicePlan, AppSettings (+ShortcutSettings, GoogleDriveSettings), LogoPreset
  Services/      logika i I/O, prawie wszystko jako singletony `.shared`
  Views/         SwiftUI; MainView = 3 panele HSplitView + pasek skrótów
  Helpers/       Color(hex:), skalowanie UI
```

Kluczowe elementy:
- `DataStore` (`@MainActor`, `@Observable`) trzyma **wszystko**: bibliotekę, plany, ustawienia i stan prezentacji na żywo. Zapis do JSON po każdej operacji.
- `ScreenManager` tworzy okno projekcji (`PresentationWindow`, borderless, poziom `.screenSaver`) i okno testowe podglądu.
- `AutoFitEngine` dobiera rozmiar czcionki wyszukiwaniem binarnym. Ten sam render jest skopiowany w `PresentationContentView` (projektor) i `PresentationSlidePreviewCanvas` (podglądy); muszą wyglądać identycznie.
- `Song.parseLyrics` dzieli tekst na slajdy (bloki rozdzielone pustą linią, nagłówki `[Zwrotka 1]`, `[Refren]`, `R:` itd.).
- Import: `TextImporter` → `HolyricsImporter` → `HolyricsJavaDeserializer` (pliki `.mufl`/`.muf` to Java ObjectStream) → `SongDeduplicationService` → `ImportReviewSheet`.
- Kopie: `BackupService` (ZIP przez `/usr/bin/ditto`), przywracanie przez `BackupRestorer` (walidacja, podmiana katalogu, cofnięcie), kopia przy zamykaniu przez `ExitBackupCoordinator`.
- Dysk Google: `GoogleDriveService` (REST), logowanie `GoogleOAuth` (loopback `127.0.0.1` + PKCE, W3). Client Secret i tokeny tylko w Pęku kluczy (`GoogleCredentialStore`, usługa `com.cantate.presenter.gdrive`, W4); w `settings.json` jest tylko Client ID, folder i flagi. Nie dodawaj sekretów do `AppSettings`.
- Klawiatura: jeden `KeyboardMonitor` (rejestrowany w `AppDelegate`) i czysta logika `KeyboardRouter` (K3, W5). Działa tylko w oknie głównym bez arkusza oraz w `PresentationWindow`. W jednowierszowym polu (wyszukiwanie) przepuszcza klawisze piszące, obsługuje tylko Page Up/Down, F1–F12 i Esc (wyjście z pola); w polu wielowierszowym nie obsługuje nic. Okno główne startuje bez fokusu w polu wyszukiwania. Skróty z ustawień mają pierwszeństwo przed stałymi klawiszami (strzałki, Page Up/Down, Esc, R, cyfry).

### Dane

Katalog danych wyznacza wyłącznie `AppPaths` (K2): `~/Library/Application Support/CantatePresenter`, albo katalog ze zmiennej `CANTATE_DATA_DIR`. Pliki: `songs.json`, `plans.json`, `settings.json`, `custom_languages.json`, `ccli_usage.json`, `standby.html`, `logos/`, `templates/`, `history/` (5 ostatnich wersji przed zapisem, K1).

Przy pierwszym uruchomieniu, gdy w Application Support nie ma `songs.json`/`plans.json`/`settings.json`, dane są **kopiowane** ze starej lokalizacji (`data/` obok pakietu .app, a przy `swift run` z bieżącego katalogu). Stary katalog zostaje. Jeśli kopiowanie się nie uda, aplikacja w tej sesji używa starego katalogu i pokazuje alert.

Wersja formatu (`DataSchema`, obecnie 1): pole `schemaVersion` w `settings.json` i w `manifest.json` kopii; `songs.json` i `plans.json` zostają tablicami. Brak pola = 0 (ten sam format), migracja w `DataSchema.migrate`. Dane lub kopia z nowszą wersją: tylko odczyt (`PersistenceIssue.newerSchema`), przywracanie odrzucone. Zmiana formatu = nowy numer + krok migracji.

Odczyt i zapis JSON tylko przez `JSONFileStore` (K1): nieczytelny plik nie jest nadpisywany, trafia do `<nazwa>.corrupt-<data>.json`, a zapis do niego jest zablokowany do udanego wczytania.

`data/` w repozytorium to już tylko stara lokalizacja i źródło migracji; aplikacja go nie modyfikuje.

## Plan prac: przegląd kodu

Pełny przegląd: `docs/code-review-2026-10-15.html` (kopia: https://claude.ai/artifact/TSYx6Lzfp91dACae9tGZxZ). Identyfikatory K1–K3, W1–W8, S1–S11, N1–N11 w commitach i PR-ach odnoszą się do tego raportu. Numery linii w raporcie dotyczą commita `1069375` i mogą się przesunąć.

Kolejność, jeden PR na etap:
1. **Dane i klawiatura**: K1 (bezpieczny odczyt JSON, kwarantanna, kopie rotacyjne), K2 (`AppPaths`), K3 + W5 (jeden `KeyboardRouter` działający tylko dla okna głównego bez arkusza i okna projekcji), W1 (menu Edycja), W8 (unikalne UUID przy imporcie). Najpierw cel testowy.
2. **Kopie i importy**: W2 (backup w `applicationShouldTerminate` z `.terminateLater`), W3 + W4 (OAuth loopback + PKCE, tokeny w Pęku kluczy), W6 (zabezpieczenia deserializera), W7 + S7 (transpozycja, nagłówki sekcji), S3–S6.
3. **Jakość**: S2 (`@Observable`, podział `DataStore`, cache wyszukiwania i Auto-Fit), N1 (wspólny `SlideRenderer`), S10 (String Catalog), CI, porządki (N9, N10, S11).

Stan na 2026-10-15: etapy 1 i 2 scalone (PR #1, #2, #3); w etapie 3 zrobione S2, N1, S10 (gałąź `stage3-quality`, jeszcze bez PR).

## Do zrobienia

Z przeglądu kodu (kolejność proponowana):
- [x] **S1** Projekcja po odłączeniu projektora: zapamiętywać ekran po `CGDirectDisplayID`, po zniknięciu ukryć okno projekcji zamiast przenosić je na ekran operatora, wrócić po ponownym podłączeniu.
- [x] **S11** Twarde ścieżki `/Users/aoles/dev_gem/...` w kodzie i README; `INSTRUKCJA.md` i próbka jako zasoby pakietu.
- [x] **N11** Po „szybkim tekście” następna pieśń to pierwsza z planu zamiast kolejnej.
- [x] **N9** Higiena repozytorium. Decyzja właściciela: `2026-10-14_16-19-00.mufl`, `data/songs.json`, `data/plans.json` i `data/holyrics_samples/` zostają w repozytorium jako przykłady dla dewelopera (testy, migracja K2 przy uruchamianiu z repozytorium), ale nigdy w aplikacji ani instalatorze; `build_app.sh` przerywa budowanie, jeśli trafią do pakietu.
- [x] **N10** Skrypty budowania ukrywają błędy podpisu; wersja w trzech miejscach.
- [x] **S8** Logo wstawiane regexem i zapisywane do `standby.html` (dwie kopie logiki); przy okazji tłumaczenie tekstów planszy („Wersja”, „GOTOWY DO PROJEKCJI”).
- [x] **S9** Wyszukiwanie „online”: decyzja właściciela: źródła z jasną licencją. Wikiźródła przez API MediaWiki (`OnlineSearchService`, `WikisourceParser`), źródło i licencja zapisywane w pieśni (`Song.source`, `copyright`, `ccliNumber`). DuckDuckGo, LRCLIB i wbudowany katalog usunięte; chwyty od 2026-10-26 tylko z wbudowanej bazy (R4-12). Giszowiec.org odrzucony (brak licencji i API).
- [x] **CCLI SongSelect** (konto płatne parafii): API partnerskie zamknięte dla nowych aplikacji, więc import plików z SongSelect (`SongSelectImporter`: `.txt`, `.usr`, ChordPro), przycisk „Szukaj w SongSelect” (przeglądarka), numer licencji CCLI w Ustawieniach, linia © i numer CCLI na slajdzie (`CopyrightNotice`, rysowana w `SlideTextView`, poza Auto-Fit), pola © i CCLI w edytorze.
- [x] **Raport użycia CCLI**: `DataStore.ccliUsage` (`ccli_usage.json`, raz na pieśń dziennie przy `present(song:)`), eksport CSV w Ustawieniach (`CCLIUsageReport`).
- Decyzja właściciela (2026-10-15): bez klucza partnera API CCLI; nie prosić CCLI o dostęp i nie pobierać z SongSelect automatycznie.
- [x] **N2** Ustawienia typowane stringami (`"left"`, `"lewo"`) → enumy z tolerancyjnym dekoderem.
- [x] **N3** Ostatni regex kompilowany w pętli (`HolyricsImporter`).
- [x] **N4** Dyktowanie: podwójny callback, mylący komentarz o rozpoznawaniu na urządzeniu.
- [x] **N5** Import Holyrics gubi tonację; XML parsowany regexem.
- [x] **N6** Przestarzałe API (ostrzeżenia kompilatora).
- [x] **N7** Pozostałe ciche `try?` przy zapisie (np. własne języki).
- [x] **N8** Indeks deduplikacji nieaktualizowany po zamianie pieśni głównej.
- [x] **CI** `.github/workflows/ci.yml`: `swift build`, `swift test`, `build_app.sh` i `codesign --verify` na najnowszym Xcode runnera macOS (2026-10-15: Xcode 26.6). Starsze SwiftPM nie kompilują `Localizable.xcstrings` do `.lproj`; `Localization.rawCatalog` czyta wtedy katalog JSON.
- [x] PR etapu 3 (#4).
- [x] Nowe instalatory w `dist/` (2026-10-15, wersja 1.0.0, kompilacja 70; `dist/` jest w `.gitignore`).

Decyzje właściciela (zadania; przed wykonaniem potwierdzić z właścicielem):
- [x] Przepisanie historii gita: zrobione 2026-10-17 (jednorazowym skryptem, usuniętym 2026-10-26, jest w historii gita; kopie w `dist/history-backup-*.bundle`). Plik `.mufl` jest tylko lokalnie (`.gitignore`). Stare commity zostają jeszcze w odnośnikach zamkniętych PR na GitHubie; usunąć je może tylko GitHub Support. Uwaga: `git reset --keep` po przepisaniu kasuje `.mufl` z dysku (był śledzony w starej historii); odtworzenie: `git show <stary commit>:2026-10-14_16-19-00.mufl > 2026-10-14_16-19-00.mufl` albo z kopii `.bundle`.
- [x] Podpis Developer ID i notaryzacja: przygotowane (`CANTATE_SIGN_IDENTITY`, `CANTATE_INSTALLER_IDENTITY`, `CANTATE_NOTARY_PROFILE`, `scripts/notarize.sh`, `Resources/CantatePresenter.entitlements`, `docs/RELEASE.md`). Decyzja właściciela 2026-10-16: **na razie bez konta Apple Developer** (koszt); wydania podpisane ad-hoc, nienotaryzowane (skutki: `docs/RELEASE.md`, punkt 4). Nie proponuj zakupu konta, dopóki właściciel nie wróci do tematu. Hardened Runtime przy każdym podpisie, także ad-hoc (R3-01); przy ad-hoc `build_app.sh` dodaje tylko `com.apple.security.cs.disable-library-validation` (inaczej dyld odrzuca Sparkle.framework).
- [x] Automatyczne aktualizacje: Sparkle 2.10.1 (`UpdateService`, menu „Sprawdź uaktualnienia…”), kanał `releases/latest/download/appcast.xml`, klucz EdDSA w Pęku kluczy (konto `cantate-presenter`), wydanie `scripts/release.sh` (szkic na GitHubie). Sprawdzone lokalnie: kopia z podpisem ad-hoc zaktualizowała się sama. Kanał podpisany (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`, R3-09).
- [ ] Weryfikacja aplikacji w Google (zniesienie limitu 100 testerów i ostrzeżenia przy logowaniu; wymaga m.in. polityki prywatności).
- [x] Pole `schemaVersion` (decyzja 2026-10-16: tak): w `settings.json` i manifeście kopii, bez zmiany kształtu pozostałych plików; nowsze dane tylko do odczytu.

Nowe funkcje:
- [x] **Ekran dla muzyków** (z raportu, pomysły na rozwój; dodany 2026-10-15): bieżący i następny slajd z chwytami nad tekstem. Okno na Macu (`MusicianView`, `MusicianWindowManager`, przycisk „Muzycy”) i podgląd na tabletach przez serwer pilota (`/stage`, osobny token tylko do odczytu, `MusicianStagePage`). Wspólny model `MusicianStage`; dopasowanie arkusza do slajdu `ChordSheet` (po słowach, z pożyczaniem chwytów pierwszej zwrotki, chwyty w nawiasach), wzorzec w `shared/fixtures/chordsheet.json`.
- [x] **Sterowanie ze smartfona** (pilot: następny/poprzedni slajd, czarny ekran, wybór pieśni z planu). Zrobione jako strona WWW serwowana przez Maca w LAN: `RemoteControlServer` (Network.framework, port 8765 albo wolny), `RemoteHTTP` (minimalny HTTP/1.1), `RemoteRouter` (token 128 bit z kodu QR, porównanie w stałym czasie), `RemoteControlBridge` (stan i polecenia na `DataStore`), `RemoteControlPage` (HTML/JS, teksty z `labels` w języku aplikacji), `RemoteControlSheet` (QR z CoreImage). Strona odpytuje stan co sekundę. HTML stron pilota i muzyków jest w `Resources/remote_page.html` i `stage_page.html` (`WebPageResource`). Wyszukiwanie pieśni (`/api/search`, ten sam `SongSearchIndex` co lista) i start/wznowienie projekcji (`start`, `song`); strony pilota i muzyków sprawdza `scripts/remote_check.py` (Chrome, makieta serwera, w CI). Działa w przeglądarce na iOS i Androidzie, bez internetu.

- Wersje webowa i Windows: **porzucone** (decyzja właściciela 2026-10-26), usunięte z repozytorium razem z zadaniem Windows w CI i tekstami tylko dla nich w `Localizable.xcstrings`. Kod został w historii gita (ostatni commit z nimi: `4cbe6ad`). Nie proponuj ich odtwarzania.
- [x] Pliki wzorcowe `shared/fixtures` (opis w `shared/README.md`): slajdy, wyszukiwanie, transpozycja, chwyty dla muzyków, duplikaty, skróty klawiszowe, Holyrics, Wikiźródła, kopia zapasowa, Auto-Fit (`autofit.json` ze stałym pomiarem z `scripts/make_autofit_fixture.py`; AppKit mierzy inaczej, więc dokładnie porównywane są tylko przypadki `anyMeasurer`).

Weryfikacja przez właściciela:
- [ ] Przejrzenie tłumaczeń interfejsu (en, de, es, uk), najlepiej z osobami znającymi język.

## Testy

Cel testowy `CantatePresenterCoreTests` (katalog `Tests/CantatePresenterCoreTests/`) testuje bibliotekę `CantatePresenterCore` przez `@testable import`, więc typy nie muszą być `public`. Używaj Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`); przed indeksowaniem wyników używaj `try #require(...)`, bo przekroczenie zakresu wywraca cały proces testowy. Wymaga pełnego Xcode, nie samych Command Line Tools.

- Priorytet testów: `Song.parseLyrics`, `GuitarChordsService.transpose`, `HolyricsJavaDeserializer` (pliki z `data/holyrics_samples/` oraz ich obcięte/uszkodzone kopie), `TextImporter.readTextWithBestEncoding`, deduplikacja, zgodność wstecz dekoderów modeli (stary JSON musi się wczytać).
- Testy nigdy nie mogą czytać ani zapisywać prawdziwego katalogu danych. Ścieżki wstrzykuj, używaj katalogów tymczasowych.
- Każdy błąd naprawiany z raportu: najpierw test, który go odtwarza, potem poprawka.

## Weryfikacja zmian

- Po każdej zmianie: `swift build`, a gdy istnieją testy, `swift test`.
- Zmiany w UI, klawiaturze, oknach lub projekcji sprawdzaj w działającej aplikacji (`./build_app.sh && open CantatePresenter.app`). Bez drugiego monitora użyj „Otwórz okno testowe” w prawym panelu.
- Scenariusze do ręcznego sprawdzenia przy K3/W5: Esc przy otwartym arkuszu Ustawień w trakcie projekcji nie może zatrzymać projekcji; Enter w arkuszu nie może jej uruchomić; strzałki na liście pieśni zmieniają zaznaczenie.
- Przed testami na prawdziwej bibliotece zrób kopię `~/Library/Application Support/CantatePresenter`, a najlepiej pracuj na kopii przez `CANTATE_DATA_DIR`.

## Konwencje

- Swift tools 6.0 (tryb języka Swift 6, pełne sprawdzanie współbieżności), macOS 14. Wcięcia 4 spacje, sekcje `// MARK: -`, `public` na typach jak w istniejącym kodzie.
- Typy wartości współdzielone między wątkami są `Sendable`; serwisy bez stanu albo z niezmiennym stanem (`let`) też. Globalny stan zmienny tylko jako pamięć podręczna chroniona `NSLock` (`Localization`, `AutoFitEngine`).
- Domknięcia, które system wywołuje poza wątkiem głównym (wątek audio, kolejki Speech/AVFoundation), nie mogą powstawać w kodzie `@MainActor`: w trybie Swift 6 takie wywołanie zatrzymuje aplikację. Twórz je w funkcji `nonisolated` albo oznacz jako `@Sendable` (przykład: `DictationService.installTap`, `recognize`).
- Serwisy dotykające UI lub `DataStore` są `@MainActor`. Długie operacje (import, ZIP, sieć) poza wątkiem głównym.
- Teksty UI (S10): kluczem jest polski tekst. W widokach `L("…")` (odświeża się po zmianie języka), poza widokami `Lnow("…")`. Wartości wstawiane jako `{0}`, `{1}`: `L("Slajd {0}/{1}", a, b)`, nigdy interpolacja w kluczu. Każdy nowy tekst dodaj do `Sources/CantatePresenterCore/Resources/Localizable.xcstrings` z tłumaczeniem en, de, es, uk (`python3 -I scripts/add_translation.py "Tekst" en de es uk`, usuwanie: `--remove "Tekst"`; zachowuje format pliku); test `LocalizationCatalogCompletenessTests` tego pilnuje.
- Nie tłumacz danych i formatów: nagłówków eksportu `.txt` („Tytuł:”), znaczników sekcji wstawianych do tekstu („[Zwrotka]”), nazw plików i folderów (`CantatePresenter_Backups`, „przed przywróceniem”), wartości technicznych (HTTP, zapytania Dysku). Do JSON zapisuj stabilne kody, nie etykiety (np. `SlideType`).
- Nowe pola modeli zapisywanych w JSON tylko z tolerancyjnym dekoderem (`decodeIfPresent` + wartość domyślna), jak w `AppSettings.init(from:)`. Inaczej stare pliki przestaną się wczytywać (K1).
- Błędy zapisu nie mogą być połykane przez `try?` bez logowania (`os.Logger`) i informacji dla użytkownika.
- Commity: konwencjonalne prefiksy po angielsku (`feat(ui):`, `fix:`, `refactor:`, `test:`, `docs:`), w treści identyfikator z raportu, np. `fix(data): quarantine unreadable songs.json instead of overwriting (K1)`.

## Wymaga decyzji właściciela, nie rób samodzielnie

- Dodawanie kolejnych zależności (GRDB/SQLite, SwiftLint itp.): zapytaj przed dodaniem.
- Podpis Developer ID i notaryzacja (wymaga konta Apple Developer), konfiguracja klienta OAuth w Google Cloud Console.
- Zmiana formatu plików danych bez migracji ze starego formatu.

## Pułapki

- Menu Edycja (W1) jest potrzebne, żeby ⌘C/⌘V/⌘Z działały w polach tekstowych. Nie usuwaj go przy przebudowie menu.
- Nie dodawaj nowych monitorów `NSEvent` ani `keyDown` dla skrótów prezentacji; wszystko idzie przez `KeyboardRouter`. Okno testowe podglądu i okno instrukcji celowo nie są obsługiwane.
- Plansza startowa jest składana w pamięci (`StandbyRenderer`: logo w `<!--LOGO-->`, wersja, teksty, autor) i powiększana do szerokości ekranu (`StandbyZoom`); pliku `standby.html` nie zapisuj. Pliki `data/*.json` w repozytorium są śledzone przez git; po K2 aplikacja ich nie zmienia, ale nie commituj ich przypadkiem po ręcznych próbach.
- Stara wersja aplikacji (sprzed K1) wczytuje bibliotekę z błędem dat i nadpisuje ją przykładami. Nie uruchamiaj starych buildów na prawdziwych danych.
- Logo END to plik `Sources/CantatePresenterCore/Resources/end_logo.png` (zasób pakietu), wczytywany przez `ENDLogoAsset`.
- Zasoby biblioteki (`Sources/CantatePresenterCore/Resources`: tłumaczenia, strony pilota, logo END) deklaruje `Package.swift` (`.process`); `build_app.sh` kopiuje ich paczkę oraz ręcznie `Resources/AppIcon.icns`, `INSTRUKCJA.md` i `LICENSE`. `data/` nie trafia do aplikacji (N9).
