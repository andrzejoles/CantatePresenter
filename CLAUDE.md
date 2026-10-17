# CantatePresenter

Natywna aplikacja macOS (Apple Silicon, macOS 14+) do projekcji tekstów pieśni na projektorze lub drugim ekranie. SwiftUI + AppKit, Swift Package Manager. Jedyna zależność: **Sparkle** (automatyczne aktualizacje, wersja przypięta w `Package.swift`, decyzja właściciela 2026-10-16). Interfejs i dokumentacja użytkownika są po polsku.

## Komendy

```bash
swift build                 # szybka kompilacja debug, sprawdzaj po każdej zmianie
swift build -c release      # build release (używany przez build_app.sh)
./build_app.sh              # składa CantatePresenter.app (Info.plist inline, podpis ad-hoc)
./run.sh                    # buduje .app jeśli trzeba i uruchamia
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
- Numer wersji nie jest nigdzie zapisany ręcznie (decyzja właściciela 2026-10-16): `scripts/version.sh` (i `web/server/appversion.py`, ta sama reguła) liczy scalone PR (commity „Merge pull request #” w historii pierwszego rodzica) i commity od ostatniego z nich: 8 PR + 3 commity = 1.8.3, 10 PR = 2.0.0. PR scalaj zwykłym „Merge pull request” (nie squash), inaczej się nie policzy. Numer kompilacji to liczba wszystkich commitów. Pliku `VERSION` nie ma w repozytorium, a serwery podają `web/src/version.js` same. CI potrzebuje pełnej historii (`fetch-depth: 0`).
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
- `DataStore` (`@MainActor`, `ObservableObject`) trzyma **wszystko**: bibliotekę, plany, ustawienia i stan prezentacji na żywo. Zapis do JSON po każdej operacji.
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

Wersja formatu (`DataSchema`, obecnie 1): pole `schemaVersion` w `settings.json` i w `manifest.json` kopii; `songs.json` i `plans.json` zostają tablicami. Brak pola = 0 (ten sam format), migracja w `DataSchema.migrate`. Dane lub kopia z nowszą wersją: tylko odczyt (`PersistenceIssue.newerSchema`), przywracanie odrzucone. Tak samo w wersji webowej (`SCHEMA_VERSION` w `storage.py` i `models.js`). Zmiana formatu = nowy numer + krok migracji we wszystkich wersjach.

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
- [x] **S9** Wyszukiwanie „online”: decyzja właściciela: źródła z jasną licencją. Wikiźródła przez API MediaWiki (`OnlineSearchService`, `WikisourceParser`), źródło i licencja zapisywane w pieśni (`Song.source`, `copyright`, `ccliNumber`). DuckDuckGo, LRCLIB i wbudowany katalog usunięte. Giszowiec.org odrzucony (brak licencji i API).
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
- [ ] Przepisanie historii gita (decyzja 2026-10-16: tak): gotowy `scripts/rewrite_history.sh` (świeży klon, `git filter-branch`, kontrola wyniku, kopia `.bundle`; sprawdzony na kopii repozytorium). Uruchamia właściciel po scaleniu wszystkich PR: `scripts/rewrite_history.sh --push` (tryb automatyczny Claude blokuje force-push historii). Potem `.mufl` jest tylko lokalnie (`.gitignore`).
- [x] Podpis Developer ID i notaryzacja: przygotowane (`CANTATE_SIGN_IDENTITY`, `CANTATE_INSTALLER_IDENTITY`, `CANTATE_NOTARY_PROFILE`, `scripts/notarize.sh`, `Resources/CantatePresenter.entitlements`, `docs/RELEASE.md`). Decyzja właściciela 2026-10-16: **na razie bez konta Apple Developer** (koszt); wydania podpisane ad-hoc, nienotaryzowane (skutki: `docs/RELEASE.md`, punkt 4). Nie proponuj zakupu konta, dopóki właściciel nie wróci do tematu.
- [x] Automatyczne aktualizacje: Sparkle 2.9.6 (`UpdateService`, menu „Sprawdź uaktualnienia…”), kanał `releases/latest/download/appcast.xml`, klucz EdDSA w Pęku kluczy (konto `cantate-presenter`), wydanie `scripts/release.sh` (szkic na GitHubie). Sprawdzone lokalnie: kopia z podpisem ad-hoc zaktualizowała się sama.
- [ ] Weryfikacja aplikacji w Google (zniesienie limitu 100 testerów i ostrzeżenia przy logowaniu; wymaga m.in. polityki prywatności).
- [x] Pole `schemaVersion` (decyzja 2026-10-16: tak): w `settings.json` i manifeście kopii, bez zmiany kształtu pozostałych plików; nowsze dane tylko do odczytu.

Nowe funkcje:
- [x] **Ekran dla muzyków** (z raportu, pomysły na rozwój; dodany 2026-10-15): bieżący i następny slajd z chwytami nad tekstem. Okno na Macu (`MusicianView`, `MusicianWindowManager`, przycisk „Muzycy”) i podgląd na tabletach przez serwer pilota (`/stage`, osobny token tylko do odczytu, `MusicianStagePage`). Wspólny model `MusicianStage`; dopasowanie arkusza do slajdu `ChordSheet` (po słowach, z pożyczaniem chwytów pierwszej zwrotki, chwyty w nawiasach), wzorzec w `shared/fixtures/chordsheet.json`. Do zrobienia: ten sam ekran w wersji webowej.
- [x] **Sterowanie ze smartfona** (pilot: następny/poprzedni slajd, czarny ekran, wybór pieśni z planu). Zrobione jako strona WWW serwowana przez Maca w LAN: `RemoteControlServer` (Network.framework, port 8765 albo wolny), `RemoteHTTP` (minimalny HTTP/1.1), `RemoteRouter` (token 128 bit z kodu QR, porównanie w stałym czasie), `RemoteControlBridge` (stan i polecenia na `DataStore`), `RemoteControlPage` (HTML/JS, teksty z `labels` w języku aplikacji), `RemoteControlSheet` (QR z CoreImage). Strona odpytuje stan co sekundę. HTML stron pilota i muzyków jest w `Resources/remote_page.html` i `stage_page.html` (`WebPageResource`), wspólny z wersją Windows; `remote_page.html` ma też kopię w `web/` (po zmianie: `cp Sources/CantatePresenterCore/Resources/remote_page.html web/`). Strona nie może mieć atrybutów `style` ani `on…` (CSP wersji webowej). Wyszukiwanie pieśni (`/api/search`, ten sam `SongSearchIndex` co lista) i start/wznowienie projekcji (`start`, `song`); stronę sprawdza `web/tools/remote_check.py` (Chrome, makieta serwera, w CI). Opis pierwotnej analizy poniżej. Musi działać na **iOS i Androidzie**, więc najpierw wybrać technologię. Kandydaci: aplikacja webowa serwowana przez Maca w sieci lokalnej (HTTP + WebSocket, wejście przez kod QR, bez sklepów z aplikacjami), aplikacja natywna lub wieloplatformowa (sklepy, wyższy koszt), Bluetooth HID (bez instalacji, ale tylko proste klawisze). Uwzględnić parowanie i zabezpieczenie (PIN/token), działanie bez internetu i uprawnienia sieci lokalnej w macOS.

- [x] **Wersja webowa** (`web/`, opis w `web/README.md`): **prywatna aplikacja, nie publiczna strona** (decyzja właściciela 2026-10-15). Domyślnie logowanie hasłem + kod TOTP z aplikacji uwierzytelniającej, dane na serwerze (decyzja: serwer, nie przeglądarka). Serwer `web/server/` w Pythonie 3.10+ bez zależności (scrypt, TOTP RFC 6238, kody zapasowe, blokady, sesje HttpOnly/SameSite=Strict, CSRF, CSP, dane w formacie macOS z historią i wersjami). Front: moduły ES bez frameworka i bez budowania, logika przeniesiona 1:1 i sprawdzana `shared/fixtures/`. Bez Google Drive; kopia `.cantatebackup` zgodna z macOS. Testy: `web/run-tests.sh`, `web/server/tests`, `web/tools/ui_check.py` (Chrome przez DevTools), `web/tools/qr_check.py`.
  - Zrobione 2026-10-16: ekran muzyków (`core/chordsheet.js`, `core/stage.js`, `musicians.html`, stan przez BroadcastChannel i `/api/live` po zalogowaniu), raport CCLI (`core/ccli.js`, rodzaj danych `ccliUsage`), Wikiźródła (`core/wikisource.js`, CSP `connect-src` tylko `*.wikisource.org`), konto (`/api/account/*`: hasło, nowa aplikacja TOTP, kody zapasowe), plansza z logo (`web/logos.json`, `web/screen.css`), import Holyrics (`core/holyrics.js`, 1:1 z deserializatorem Swift, sprawdzony na prawdziwej bibliotece 901 pieśni).
  - Zrobione 2026-10-17: pilot ze smartfona (`server/remote.py`, `src/app/remote.js`, strona `/remote` wspólna z macOS i Windows, telefon loguje się tym samym kontem), przegląd duplikatów przy imporcie (`core/dedup.js`, `shared/fixtures/dedup.json`), dyktowanie (Web Speech API, `src/app/dictation.js`).
  - Różnice wobec macOS: bez Dysku Google (decyzja właściciela: celowo pominięty; kopia zapasowa tylko jako plik `.cantatebackup` pobierany z przeglądarki i wczytywany z dysku; nie proponuj integracji z Dyskiem w wersji webowej); import bez wzbogacania metadanych z wbudowanego katalogu.
- [x] **Wersja na Windows** (2026-10-16, `windows/`): .NET 8 + WinUI 3 (Windows App SDK 1.6, bez MSIX, self-contained win-x64). `CantatePresenter.Core` (bez UI, logika 1:1 z wersją JS/Swift, te same pliki danych i kopie, testy xUnit na `shared/fixtures`; działa też na Macu: `dotnet test windows/tests/CantatePresenter.Core.Tests`) i `CantatePresenter.WinUI` (UI budowane w kodzie). CI: zadanie `windows` buduje, uruchamia `--smoke-test` (zrzuty ekranu jako artefakt, ślad kroków przez `CANTATE_TRACE`) i pakuje ZIP. Pułapki: folder nie może kończyć się na `.App` (`.gitignore *.app/`); element XAML ma jednego rodzica (nie wstawiaj tych samych paneli do nowych ramek); `EnableMsixTooling` jest wymagane przy `dotnet publish`.
  - Pilot i tablety dla muzyków (2026-10-17): `CantatePresenter.Core/Remote` (`RemoteHttp`, `RemoteRouter`, `RemoteBridge`, `RemoteServer` na `TcpListener`, `QrCode` 1:1 z `web/src/core/qr.js`, wzorzec `shared/fixtures/qr.json` z `web/tools/make_qr_fixture.py`), okno `RemoteDialog` (przycisk „Pilot”). Strony telefonu i tabletu są wspólne z macOS: `Sources/CantatePresenterCore/Resources/remote_page.html` i `stage_page.html` (w Windows jako `EmbeddedResource`, LF wymuszone w `.gitattributes`); zmieniaj je tylko tam. Próba w CI sprawdza serwer przez HTTP i obie strony w WebView2.
  - Zrobione 2026-10-17: filtr „Z chwytami” i gitara na liście (`Song.HasChords`), powiększenie interfejsu (`uiScale`: układ w `Viewbox`, A−/A+, Ctrl +/−, suwak w Ustawieniach), dyktowanie (`Dictation.cs`, rozpoznawanie mowy Windows w usłudze online Microsoft, więc „tylko na tym urządzeniu” je wyłącza), Dysk Google (`Core/GoogleDrive`: loopback + PKCE, testy z podstawionym HTTP; tokeny w Menedżerze poświadczeń, `WindowsCredentialStore`; okno w Import/Eksport, kopia przy zamykaniu), instalator Inno Setup (`windows/installer`, w CI z cichą instalacją i odinstalowaniem; `scripts/release.sh` dołącza go do wydania). Klient OAuth wbudowywany z `google-oauth-client.json`/`$GOOGLE_OAUTH_CLIENT_JSON` (w CI z sekretu `GOOGLE_OAUTH_CLIENT_JSON`, opis w `docs/RELEASE.md`).
  - Przegląd duplikatów przy imporcie (2026-10-17): `Core/Import/SongDeduplication.cs` (1:1 z `web/src/core/dedup.js`, wzorzec `shared/fixtures/dedup.json`), okno `ImportReviewDialog`.
  - Aktualizacje (2026-10-17): `Core/Updates/UpdateChecker.cs` (GitHub Releases API, tylko instalator z wydań tego repozytorium, rozmiar i SHA-256 z pola `digest`), `Updater.cs` (przy starcie, gdy włączone w Ustawieniach, i „Sprawdź uaktualnienia...” w „O programie”; po pobraniu zwykłe zamknięcie, potem cichy instalator z `/RELAUNCH=1`, który uruchamia nową wersję). Wersja z ZIP-a tylko otwiera stronę wydania. Słabiej niż Sparkle: bez podpisu EdDSA, zaufanie do HTTPS i GitHuba.
- [ ] Wspólne dla wersji macOS, web i Windows, żeby wygląd i działanie były możliwie spójne: ten sam format danych i kopii zapasowej (`songs.json`, `plans.json`, kody `SlideType`, `.cantatebackup`), te same tłumaczenia (eksport z `Localizable.xcstrings`), ta sama logika podziału tekstu na slajdy, transpozycji, Auto-Fit i skrótów klawiszowych. Rozważyć wspólny zestaw plików testowych (wejście → oczekiwany wynik) sprawdzany we wszystkich wersjach.

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

- Swift tools 5.9, macOS 14. Wcięcia 4 spacje, sekcje `// MARK: -`, `public` na typach jak w istniejącym kodzie.
- Serwisy dotykające UI lub `DataStore` są `@MainActor`. Długie operacje (import, ZIP, sieć) poza wątkiem głównym.
- Teksty UI (S10): kluczem jest polski tekst. W widokach `L("…")` (odświeża się po zmianie języka), poza widokami `Lnow("…")`. Wartości wstawiane jako `{0}`, `{1}`: `L("Slajd {0}/{1}", a, b)`, nigdy interpolacja w kluczu. Każdy nowy tekst dodaj do `Sources/CantatePresenterCore/Resources/Localizable.xcstrings` z tłumaczeniem en, de, es, uk; test `LocalizationCatalogCompletenessTests` tego pilnuje.
- Nie tłumacz danych i formatów: nagłówków eksportu `.txt` („Tytuł:”), znaczników sekcji wstawianych do tekstu („[Zwrotka]”), nazw plików i folderów (`CantatePresenter_Backups`, „przed przywróceniem”), wartości technicznych (HTTP, zapytania Dysku). Do JSON zapisuj stabilne kody, nie etykiety (np. `SlideType`).
- Nowe pola modeli zapisywanych w JSON tylko z tolerancyjnym dekoderem (`decodeIfPresent` + wartość domyślna), jak w `AppSettings.init(from:)`. Inaczej stare pliki przestaną się wczytywać (K1).
- Błędy zapisu nie mogą być połykane przez `try?` bez logowania (`os.Logger`) i informacji dla użytkownika.
- Commity: konwencjonalne prefiksy po angielsku (`feat(ui):`, `fix:`, `refactor:`, `test:`, `docs:`), w treści identyfikator z raportu, np. `fix(data): quarantine unreadable songs.json instead of overwriting (K1)`.

## Wymaga decyzji właściciela, nie rób samodzielnie

- Dodawanie kolejnych zależności (GRDB/SQLite, SwiftLint itp.): zapytaj przed dodaniem.
- Przepisywanie historii gita (usunięcie `2026-10-14_16-19-00.mufl`, adresu e-mail z `data/settings.json`).
- Podpis Developer ID i notaryzacja (wymaga konta Apple Developer), konfiguracja klienta OAuth w Google Cloud Console.
- Zmiana formatu plików danych bez migracji ze starego formatu.

## Pułapki

- Menu Edycja (W1) jest potrzebne, żeby ⌘C/⌘V/⌘Z działały w polach tekstowych. Nie usuwaj go przy przebudowie menu.
- Nie dodawaj nowych monitorów `NSEvent` ani `keyDown` dla skrótów prezentacji; wszystko idzie przez `KeyboardRouter`. Okno testowe podglądu i okno instrukcji celowo nie są obsługiwane.
- Plansza startowa jest składana w pamięci (`StandbyRenderer`: logo w `<!--LOGO-->`, wersja, teksty, autor) i powiększana do szerokości ekranu (`StandbyZoom`); pliku `standby.html` nie zapisuj. Pliki `data/*.json` w repozytorium są śledzone przez git; po K2 aplikacja ich nie zmienia, ale nie commituj ich przypadkiem po ręcznych próbach.
- Stara wersja aplikacji (sprzed K1) wczytuje bibliotekę z błędem dat i nadpisuje ją przykładami. Nie uruchamiaj starych buildów na prawdziwych danych.
- Logo planszy w wersji webowej: `web/logos.json` to eksport `LogoCatalog` (`python3 -I scripts/export_web_logos.py` po każdej zmianie logo; pilnuje tego `WebLogosTests`).
- Logo END to plik `Sources/CantatePresenterCore/Resources/end_logo.png` (zasób pakietu), wczytywany przez `ENDLogoAsset`.
- `Package.swift` nie deklaruje zasobów; `data/` i `Resources/AppIcon.icns` są kopiowane ręcznie przez `build_app.sh`.
