# CantatePresenter — Prezenter Pieśni & Słowa dla macOS

Natywna, wysoce zoptymalizowana aplikacja na system **macOS** (procesory **Apple Silicon: M1–M5 Pro**, kompilowana natywnie dla `arm64`, bez użycia Rosetta).

Aplikacja oferuje zaawansowane możliwości projekcji tekstów pieśni na zewnętrznych ekranach/projektorach oraz pojedynczym ekranie z zachowaniem natychmiastowej prostoty obsługi przez operatora, obsługą chwytów gitarowych, dyktowaniem głosem, pełnym backupem na Dysku Google oraz importem baz z Holyrics, OpenLyrics i plików tekstowych.

---

## 🚀 Jak uruchomić program

Możesz uruchomić aplikację na dwa sposoby:

1. **Przez skrypt w terminalu**:
   ```bash
   ./run.sh
   ```
2. **Bezpośrednio z Findera**:
   Kliknij dwukrotnie w plik aplikacji **`CantatePresenter.app`** w folderze projektu.

Jeżeli chcesz ponownie przebudować aplikację po edycji kodu:
```bash
./build_app.sh
```

---

## 🎯 Główne funkcje i spełnione wymagania

### 1. 🖥️ Pełna obsługa wielu ekranów (Multi-Screen)
- Wykrywanie w czasie rzeczywistym wszystkich podłączonych wyświetlaczy (`NSScreen`), w tym projektorów HDMI, ekranów zewnętrznych i tabletów graficznych (kamvas, monitory 1440p, 4K itd.).
- **Projekcja pełnoekranowa**: Tworzy bezramkowe okno (`borderless`) pokrywające wybrany monitor zewnętrzny na poziomie `.screenSaver`, ukrywając pasek menu i Dock.
- **Okno testowe podglądu**: Możliwość włączenia skalowalnego okna testowego, co pozwala testować projekcję bez konieczności podłączania fizycznego projektora.

### 2. 🔠 Inteligentne dopasowanie rozmiaru czcionki (Auto-Fit)
- Tekst każdej zwrotki i refrenu jest analizowany w czasie rzeczywistym przy użyciu szybkiego algorytmu binarnego.
- Rozmiar czcionki jest automatycznie maksymalizowany tak, aby tekst wypełnił ekran projektora w optymalny sposób, **bez obcinania słów i bez potrzeby przewijania**.
- Krótkie refreny uzyskują dużą, monumentalną czcionkę (np. 150-180 pt), natomiast dłuższe strofy dostosowują się idealnie do wysokości ekranu.

### 3. 🔍 Wyszukiwanie w treści pieśni (Full-Text Search)
- Błyskawiczne wyszukiwanie po tytule, autorze oraz **występowaniu słów w dowolnym miejscu tekstu pieśni**.
- Obsługa polskich znaków diakrytycznych (folding): wpisanie `swiety`, `laska`, `bog`, `brzegiem` bezbłędnie wyszukuje pieśni `Święty`, `Twoja łaska`, `Bóg`, `Pan kiedyś stanął nad brzegiem`.
- W wynikach wyszukiwania prezentowany jest fragment tekstu (snippet) z podglądem znalezionego słowa.

### 4. 📝 Łatwa edycja i dodawanie pieśni podczas trwania prezentacji
- Podczas gdy na ekranie zewnętrznym trwa projekcja pieśni, operator może **dowolnie wyszukiwać inne pieśni w bibliotece, przeglądać je, dodawać nowe pieśni oraz edytować istniejące**.
- Prezentacja na rzutniku trwa nieprzerwanie w tle.
- Wyraźny czerwony pasek informuje operatora: `PROJEKTOR: Trwa projekcja 'Tytuł' (slajd X/Y)` z przyciskiem `Wróć do prezentowanej pieśni`.
- Dedykowany edytor pieśni z podglądem na żywo podziału na slajdy.
- Rozpoznawanie znaczników takich jak `[Zwrotka 1]`, `[Refren]`, `[Bridge]`, `[R]`, `[Z1]`, lub automatyczny podział pustą linią (`\n\n`).

### 5. 📂 Zaawansowany Import i Eksport pieśni
- Przycisk **„Import/Eksport”** w bibliotece, skróty w menu systemowym macOS (*Plik -> Importuj... / Eksportuj...*), oraz opcje w menu kontekstowym pod prawym przyciskiem myszy.
- **Import**:
  - Obsługa pojedynczych plików oraz wsadowego importu wielu plików naraz.
  - Automatyczne wykrywanie kodowania (**UTF-8**, **Windows-1250**, **ISO-8859-2**, **MacOS Roman**).
  - Import plików tekstowych (`.txt`), plików kopii bazy (`.json`) oraz całych folderów z utworami.
  - W folderze `przykladowe_piesni/` przygotowano gotowe pliki testowe.
- **Eksport**:
  - **Eksport całej bazy do pliku JSON (.json)** — kompletna, przenośna kopia zapasowa do migracji na inny komputer.
  - **Eksport całej bazy do folderu (.txt)** — każdy utwór zapisywany jako osobny, czysty plik tekstowy z metadanymi i zwrotkami.
  - **Eksport pojedynczego utworu** — szybki eksport wybranej pieśni do pliku `.txt` lub `.json` (z poziomu okna dialogowego lub prawym przyciskiem myszy na liście).

### 6. 📋 Plan nabożeństwa (Lista podręczna / Setlist)
- Zakładka "Plan nabożeństwa" obok biblioteki pieśni.
- Dodawanie pieśni do planu jednym kliknięciem (`+ Do planu` lub menu kontekstowe).
- Szybkie przesuwanie kolejności pieśni (w górę/w dół) oraz usuwanie.
- Płynne przechodzenie do kolejnej pieśni w planie konfigurowalnymi klawiszami skrótu.

### 7. ⌨️ Definiowalne w ustawieniach klawisze sterowania prezentacją
W oknie **Ustawienia** operator może samodzielnie zdefiniować klawisze dla kluczowych akcji:
- **Poprzedni slajd** (domyślnie: Strzałka w lewo / Strzałka w górę)
- **Następny slajd** (domyślnie: Spacja / Strzałka w prawo / Strzałka w dół)
- **Poprzedni utwór z planu** (domyślnie: `[`)
- **Następny utwór z planu** (domyślnie: `]`)
- **Uruchomienie prezentacji** (domyślnie: `Enter / Return`)
- **Zatrzymanie prezentacji** (domyślnie: `Escape`)
- **Czarny ekran (toggle)** (domyślnie: `B`)
- **Ukrycie tekstu (toggle)** (domyślnie: `C`)
- Klawisze numeryczne **1 – 9**: Natychmiastowy skok do wybranej zwrotki
- Klawisz **R**: Natychmiastowy skok do Refrenu
- Przycisk *„Przywróć domyślne skróty”* pozwala w każdej chwili powrócić do fabrycznego układu.

### 8. 🖼️ Plansza startowa HTML (Ekran czuwania / Standby)
- Gdy prezentacja pieśni nie jest aktywna (np. przed nabożeństwem, w trakcie kazania lub po naciśnięciu *Zatrzymaj prezentację*), na ekranie projektora **automatycznie wyświetla się plansza powitalna HTML**.
- W zestawie przygotowano dopracowany plik [`data/standby.html`](file:///Users/aoles/dev_gem/data/standby.html):
  - Autorskie, nowoczesne logo wektorowe (SVG: stylizowany krzyż, otwarta księga pieśni i fale uwielbienia w gradientach indygo/błękit).
  - Nazwa aplikacji: **Holyrics Mac — Prezenter Pieśni**.
  - Wersja: **Wersja 1.0.0 (Apple Silicon Native)**.
  - Zegar czasu rzeczywistego (`HH:mm:ss`) i wskaźnik gotowości do projekcji.
  - Całość w 100% offline, bez konieczności połączenia z internetem.
- **Konfigurowalna ścieżka**: W ustawieniach można wskazać dowolny własny plik `.html`, a także powrócić do domyślnej planszy jednym kliknięciem.

### 9. 🔍 Wyszukiwanie pieśni chrześcijańskich online i import 1-klikiem
- Wbudowana funkcja **"Online"** w pasku narzędzi.
- Przeszukiwanie serwisów internetowych oraz bazy pieśni chrześcijańskich (język polski i angielski).
- Podgląd znalezionych utworów wraz ze zwrotkami i przycisk **"Importuj do programu"**, który natychmiast dodaje pieśń do lokalnej bazy.

### 10. 🎨 Konfigurowalny i skalowalny interfejs (UI Zoom)
- **Przesuwane panele**: Elastyczny `HSplitView` umożliwiający dowolną zmianę szerokości kolumn (Biblioteka / Zwrotki / Panel na żywo).
- **Skalowanie czcionki całego interfejsu**:
  - Dedykowane przyciski na górnym pasku: `[A-]`, `[100%]`, `[A+]`.
  - Skróty klawiszowe: `Cmd +` (powiększenie), `Cmd -` (pomniejszenie), `Cmd 0` (reset).
  - Skalowanie dotyczy wyłącznie interfejsu operatora — okno prezentacji zawsze niezależnie wypełnia ekran czcionką obliczoną optymalnie (Auto-Fit).

### 11. 🎸 Akordy gitarowe, taby i transpozycja na żywo
- Wbudowany moduł akordów gitarowych dla muzyków (`GuitarChordsService`).
- Chwyty są widoczne dla muzyków w aplikacji i edytorze, a nie wyświetlają się zborowi na ekranie projekcji.
- Transpozycja w czasie rzeczywistym (+1 / -1 półton).
- Automatyczne wyszukiwanie i pobieranie chwytów pieśni z internetu.

### 12. ⚡ Natywny deserializator bazy Holyrics (.mufl) i deduplikacja
- Błyskawiczny, natywny parser binarny strumienia Java ObjectStream (`AC ED 00 05`) deszyfrujący 900+ pieśni z pliku `.mufl` w 0.04 sekundy.
- Automatyczne wykrywanie duplikatów (indeksowany token similarity matcher).
- Wzbogacanie o kanonicznych autorów (baza hymnów, Taizé, pieśni oazowe, ŚDM).
- Automatyczna naprawa uszkodzonego kodowania diakrytyków (mojibake).

### 13. 🎤 Dyktowanie głosem (Speech-to-Text)
- Dyktowanie wyszukiwania pieśni, tytułów, autorów i nowych zwrotek/refrenów.
- Konfigurowalny język dyktowania w Ustawieniach.

### 14. 🎨 22 Autorskie Propozycje Logo SVG
- Interaktywna galeria 22 projektów logo zoptymalizowanych pod ekrany Retina i planszę Standby.
- Wyraziste motywy muzyczne: Złota Gitara Akustyczna, Klucz Wiolinowy ze Spektrum Audio, Symfonia i Pięciolinia, Lira Dawidowa, Fale Harmoniczne Wokalu.
- Oficjalny emblemat Ruchu **Équipes Notre-Dame (END)**: Błękitna ryba Chrystusa (*esquif*) i splecione obrączki przymierza małżeńskiego.

### 15. 🎼 Pełna struktura pieśni: Coda, Przejście, Mostek, Zakończenie
- Obsługa sekcji: Zwrotka (`Z`), Refren (`R`), Bridge (`B`), Pre-Chorus (`PC`), Coda (`CODA`), Przejście (`PRZ`), Zakończenie (`ZAK`).
- Pasek szybkiego wstawiania sekcji w edytorze jednym kliknięciem.
- Wygodna edycja zapisanych pieśni: podwójny klik w wiersz, przycisk `Edytuj` w pasku i skrót `⌘E`.

### 16. 🛡️ Kontrola autora przy imporcie z sieci
- Możliwość sprawdzenia i odznaczenia podejrzanego autora (np. "Łysa Góra").
- Opcja automatycznego zapisu jako "Nieznany".

### 17. 🌐 Wielojęzyczność i tłumaczenie dla Agenta AI
- Wbudowane języki interfejsu (Polski, English, Deutsch, Español, Українська).
- Eksport słownika interfejsu do pliku JSON z precyzyjnymi opisami kontekstu każdego elementu dla agentów AI i tłumaczy (`data/templates/holyrics_translations_template_pl.json`).
- Import przetłumaczonego pliku JSON i natychmiastowa aktywacja nowego języka w interfejsie.

---

## 📁 Struktura projektu

Wszystkie pliki i dane aplikacji znajdują się w folderze `dev_gem`:

```
CantatePresenter/
├── CantatePresenter.app/  # Gotowy pakiet aplikacji macOS (arm64)
├── Package.swift          # Konfiguracja Swift Package Manager
├── build_app.sh           # Skrypt budujący aplikację .app
├── run.sh                 # Skrypt uruchamiający
├── data/                  # Lokalne pliki danych (JSON)
│   ├── songs.json         # Baza pieśni
│   ├── plans.json         # Zapisane plany nabożeństw
│   ├── settings.json      # Zapisane preferencje i ustawienia
│   ├── standby.html       # Szablon planszy czuwania z aktywnym logo SVG
│   └── templates/         # Wzorcowe szablony tłumaczeń JSON dla AI
├── przykladowe_piesni/    # Przykładowe pliki .txt do importu
├── Sources/CantatePresenter/ # main.swift (start aplikacji)
├── Sources/CantatePresenterCore/ # Kod źródłowy w Swift
│   ├── App/               # Cykl życia aplikacji i menu systemowe
│   ├── Models/            # Modele danych (Song, SongSlide, ServicePlan, LogoPreset)
│   ├── Services/          # Silnik Auto-Fit, Importer Holyrics, Akordy, Tłumaczenia
│   ├── Views/             # Widoki SwiftUI (Main, List, Slides, Live, Editor, Sheets)
│   └── Helpers/           # Skalowanie UI i obsługa kolorów
└── Tests/CantatePresenterCoreTests/ # Testy (swift test)
```

