# CantatePresenter

Natywna aplikacja macOS (Apple Silicon, macOS 14+) do projekcji tekstów pieśni na projektorze lub drugim ekranie. SwiftUI + AppKit, Swift Package Manager, **zero zależności zewnętrznych**. Interfejs i dokumentacja użytkownika są po polsku.

## Komendy

```bash
swift build                 # szybka kompilacja debug, sprawdzaj po każdej zmianie
swift build -c release      # build release (używany przez build_app.sh)
./build_app.sh              # składa CantatePresenter.app (Info.plist inline, podpis ad-hoc)
./run.sh                    # buduje .app jeśli trzeba i uruchamia
open CantatePresenter.app   # uruchomienie już zbudowanej aplikacji
./build_installer.sh        # PKG + DMG do dist/
xed .                       # otwarcie pakietu w Xcode
swift test                  # testy, gdy powstanie cel testowy (patrz „Testy”)
```

- `swift run` działa, ale wtedy katalog danych to `./data` względem bieżącego katalogu terminala, a mikrofon/dyktowanie nie mają uprawnień (brak Info.plist). Do sprawdzania funkcji używaj `./build_app.sh` + `open`.
- Nie ma lintera ani formatera w projekcie. Trzymaj się stylu istniejącego kodu.

## Architektura

```
Sources/CantatePresenter/
  main.swift, App/AppDelegate.swift   start, ręcznie budowane NSMenu, okno główne, zamykanie
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
- Kopie: `BackupService` (ZIP przez `/usr/bin/ditto`), `GoogleDriveService` (REST).
- Klawiatura: lokalne monitory `NSEvent` w `MainView.setupGlobalKeyMonitor` i `ScreenManager`, plus `PresentationWindow.keyDown`.

### Dane

Obecnie katalog `data/` jest wyznaczany jako folder **obok pakietu .app** (albo bieżący katalog przy `swift run`). Ta logika jest powielona w `DataStore`, `LocalizationService`, `BackupService`, `StandbyWebView` i `AppDelegate`. Pliki: `songs.json`, `plans.json`, `settings.json`, `custom_languages.json`, `standby.html`, `logos/`.

Docelowo (uwaga K2 z przeglądu): `~/Library/Application Support/CantatePresenter` przez jeden typ `AppPaths` z migracją ze starej lokalizacji.

## Plan prac: przegląd kodu

Pełny przegląd: `docs/code-review-2026-10-15.html` (kopia: https://claude.ai/artifact/TSYx6Lzfp91dACae9tGZxZ). Identyfikatory K1–K3, W1–W8, S1–S11, N1–N11 w commitach i PR-ach odnoszą się do tego raportu. Numery linii w raporcie dotyczą commita `1069375` i mogą się przesunąć.

Kolejność, jeden PR na etap:
1. **Dane i klawiatura**: K1 (bezpieczny odczyt JSON, kwarantanna, kopie rotacyjne), K2 (`AppPaths`), K3 + W5 (jeden `KeyboardRouter` działający tylko dla okna głównego bez arkusza i okna projekcji), W1 (menu Edycja), W8 (unikalne UUID przy imporcie). Najpierw cel testowy.
2. **Kopie i importy**: W2 (backup w `applicationShouldTerminate` z `.terminateLater`), W3 + W4 (OAuth loopback + PKCE, tokeny w Pęku kluczy), W6 (zabezpieczenia deserializera), W7 + S7 (transpozycja, nagłówki sekcji), S3–S6.
3. **Jakość**: S2 (`@Observable`, podział `DataStore`, cache wyszukiwania i Auto-Fit), N1 (wspólny `SlideRenderer`), S10 (String Catalog), CI, porządki (N9, N10, S11).

## Testy

Projekt nie ma jeszcze celu testowego. Zalecany pierwszy krok: wydzielić kod do biblioteki `CantatePresenterCore`, zostawić w celu wykonywalnym tylko `main.swift`, dodać `.testTarget(name: "CantatePresenterCoreTests", dependencies: ["CantatePresenterCore"])` i używać Swift Testing (`import Testing`). Wymaga pełnego Xcode, nie samych Command Line Tools.

- Priorytet testów: `Song.parseLyrics`, `GuitarChordsService.transpose`, `HolyricsJavaDeserializer` (pliki z `data/holyrics_samples/` oraz ich obcięte/uszkodzone kopie), `TextImporter.readTextWithBestEncoding`, deduplikacja, zgodność wstecz dekoderów modeli (stary JSON musi się wczytać).
- Testy nigdy nie mogą czytać ani zapisywać prawdziwego katalogu danych. Ścieżki wstrzykuj, używaj katalogów tymczasowych.
- Każdy błąd naprawiany z raportu: najpierw test, który go odtwarza, potem poprawka.

## Weryfikacja zmian

- Po każdej zmianie: `swift build`, a gdy istnieją testy, `swift test`.
- Zmiany w UI, klawiaturze, oknach lub projekcji sprawdzaj w działającej aplikacji (`./build_app.sh && open CantatePresenter.app`). Bez drugiego monitora użyj „Otwórz okno testowe” w prawym panelu.
- Scenariusze do ręcznego sprawdzenia przy K3/W5: Esc przy otwartym arkuszu Ustawień w trakcie projekcji nie może zatrzymać projekcji; Enter w arkuszu nie może jej uruchomić; strzałki na liście pieśni zmieniają zaznaczenie.
- Przed testami na prawdziwej bibliotece zrób kopię `data/` (albo Application Support po K2).

## Konwencje

- Swift tools 5.9, macOS 14. Wcięcia 4 spacje, sekcje `// MARK: -`, `public` na typach jak w istniejącym kodzie.
- Serwisy dotykające UI lub `DataStore` są `@MainActor`. Długie operacje (import, ZIP, sieć) poza wątkiem głównym.
- Teksty UI po polsku; nowe teksty w miarę możliwości przez `loc(...)`, docelowo String Catalog (S10). Do JSON zapisuj stabilne kody, nie polskie etykiety.
- Nowe pola modeli zapisywanych w JSON tylko z tolerancyjnym dekoderem (`decodeIfPresent` + wartość domyślna), jak w `AppSettings.init(from:)`. Inaczej stare pliki przestaną się wczytywać (K1).
- Błędy zapisu nie mogą być połykane przez `try?` bez logowania (`os.Logger`) i informacji dla użytkownika.
- Commity: konwencjonalne prefiksy po angielsku (`feat(ui):`, `fix:`, `refactor:`, `test:`, `docs:`), w treści identyfikator z raportu, np. `fix(data): quarantine unreadable songs.json instead of overwriting (K1)`.

## Wymaga decyzji właściciela, nie rób samodzielnie

- Dodawanie zależności (Sparkle, GRDB/SQLite, SwiftLint): zapytaj przed dodaniem.
- Przepisywanie historii gita (usunięcie `2026-10-14_16-19-00.mufl`, adresu e-mail z `data/settings.json`).
- Podpis Developer ID i notaryzacja (wymaga konta Apple Developer), konfiguracja klienta OAuth w Google Cloud Console.
- Zmiana formatu plików danych bez migracji ze starego formatu.

## Pułapki

- Brak menu Edycja w `AppDelegate.setupMainMenu`: ⌘C/⌘V/⌘Z nie działają w polach tekstowych, dopóki W1 nie zostanie naprawione.
- Esc jest obsługiwany w pięciu miejscach (monitor `ScreenManager`, `PresentationWindow.cancelOperation`/`performKeyEquivalent`/`keyDown`, `PresentationWKWebView`) oraz w monitorze `MainView`. Zmieniając jedno, sprawdź pozostałe.
- `DataStore.updateActiveLogo` nadpisuje `data/standby.html` na dysku; pliki `data/*.json` i `standby.html` są śledzone przez git i zmieniają się przy uruchomieniu. Nie commituj ich przypadkiem.
- Twarde ścieżki `/Users/aoles/dev_gem/...` w `ImportExportSheet.swift` i `AppDelegate.swift` (S11).
- `Models/ENDLogoAsset.swift` to ~50 KB base64; nie czytaj go w całości.
- `Package.swift` nie deklaruje zasobów; `data/` i `Resources/AppIcon.icns` są kopiowane ręcznie przez `build_app.sh`.
