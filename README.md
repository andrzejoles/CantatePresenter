# CantatePresenter dla Windows 11 (Intel / AMD x64)

> **Profesjonalny prezenter pieśni, chwytów gitarowych i slajdów liturgicznych dla Windows 11.**  
> Natywna aplikacja **C# / .NET 8 (WPF + Microsoft Edge WebView2)** zoptymalizowana pod kątem procesorów Intel oraz AMD (x64).

---

## 🚀 Jak uruchomić i skompilować na komputerze z Windows 11

### Metoda 1: W Visual Studio 2022 (Rekomendowane)
1. Otwórz plik rozwiązania `CantatePresenter.sln` w **Visual Studio 2022** (z zaznaczonym pakietem *.NET desktop development*).
2. Wybierz konfigurację **Release** lub **Debug** oraz platformę **x64** / **Any CPU**.
3. Naciśnij **F5** (lub *Uruchom*), aby skompilować i włączyć program.

### Metoda 2: Za pomocą jednego kliknięcia (Skrypt BAT)
1. Uruchom dwuklikiem plik `build_windows_x64.bat`.
2. Skrypt automatycznie pobierze pakiety NuGet, skompiluje projekt i utworzy samodzielny plik wykonywalny w folderze `publish\CantatePresenter.exe`.

### Metoda 3: Z wiersza poleceń (dotnet CLI / PowerShell)
```powershell
# 1. Przywrócenie zależności
dotnet restore

# 2. Uruchomienie w trybie developerskim
dotnet run --project CantatePresenter

# 3. Zbudowanie pojedynczego pliku EXE (Self-contained, nie wymaga instalacji .NET na docelowym komputerze)
dotnet publish CantatePresenter\CantatePresenter.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish\
```

---

## 🌟 Główne Funkcje Wersji Windows 11

* **Układ 3-panelowy:**
  * **Lewy panel:** Biblioteka pieśni z wyszukiwaniem niewrażliwym na polskie znaki diakrytyczne oraz Zestawy pieśni (plany nabożeństw).
  * **Środkowy panel:** Podgląd slajdów z chwytami gitarowymi i transpozycją akordów (`+1` / `-1` półton).
  * **Prawy panel:** Podgląd na żywo (Live Monitor), podgląd następnego slajdu i kontrola rzutnika.
* **Projekcja i Ekrany:**
  * Automatyczne wykrywanie monitorów i projektorów (Display 1, Display 2).
  * Projekcja pełnoekranowa bez ramek (*Borderless Fullscreen*).
  * **Prezentacja na jednym ekranie:** Natychmiastowe wyjście klawiszem **`ESC`**.
  * **Okno testowe:** Podgląd rzutnika w oknie bez podłączania drugiego ekranu.
* **Plansza czuwania i Galeria Logo:**
  * Domyślna plansza startowa wyświetla nazwę `CantatePresenter`, wersję `Wersja 1.0.0` oraz wybrane logo (bez żadnych zbędnych napisów placeholderowych).
  * **23 propozycje logotypów SVG** (w tym oficjalne logo **Equipes Notre-Dame**, złota gitara, harfa, lira, krzyż z projektorem).
* **Edytor z podziałem sekcji:**
  * Przyciski szybkiego wstawiania: `[Zwrotka]`, `[Refren]`, `[Coda]`, `[Bridge]`, `[Przejście]`, `[Zakończenie]`.
  * Podgląd podziału na kafelki slajdów na żywo.
* **Obsługa Chwytów Gitarowych:**
  * Wyszukiwanie chwytów online i wbudowana baza.
  * Transpozycja akordów i zapisywanie ich do bazy pieśni.
* **Import i Weryfikacja Autorów:**
  * Import z formatów **Holyrics** (`.mufl`, `.muf`, `.hly`), **plików tekstowych** (`.txt`) oraz **JSON** (`.json`).
  * Automatyczne wykrywanie kodowania: **UTF-8**, **Windows-1250 (CP1250)**, **ISO-8859-2**.
  * Weryfikacja autorów: możliwość odznaczenia fałszywych autorów (np. *„Łysa Góra”* zapisywane jako *„Nieznany”*).
  * Automatyczna naprawa polskich znaków diakrytycznych (naprawa Mojibake).
* **Kopie Zapasowe i Dysk Google:**
  * Archiwizacja całej bazy do formatu `.cantatebackup` (standard ZIP).
  * Bezpieczne przywracanie stanu programu.

---

## ⌨️ Skróty Klawiszowe

| Skrót | Działanie |
| :--- | :--- |
| **Spacja / → / ↓** | Następny slajd |
| **← / ↑** | Poprzedni slajd |
| **[ / ]** | Poprzednia / Następna pieśń |
| **B** | Czarny ekran (*Black Screen*) |
| **C** | Ukryj tekst (*Clear Text*) |
| **ESC** | Natychmiastowe wyjście z pełnego ekranu |
| **F5 / Enter** | Włączenie projekcji na pełnym ekranie |
| **Ctrl + / Ctrl -** | Powiększenie / pomniejszenie interfejsu (*Zoom*) |
| **Ctrl 0** | Przywrócenie 100% rozmiaru interfejsu |

---

## 📁 Struktura Projektu

```text
CantatePresenter.sln            - Rozwiązanie Visual Studio 2022
build_windows_x64.bat           - Skrypt automatycznego budowania .EXE
build_windows_x64.ps1           - Skrypt PowerShell
CantatePresenter/
  ├── CantatePresenter.csproj   - Plik projektu .NET 8 WPF
  ├── App.xaml / App.xaml.cs    - Style Fluent Windows 11 i start aplikacji
  ├── Models/                   - Song, Slide, Plan, AppSettings, LogoCatalog
  ├── Services/                 - DataStore, ScreenManager, Chords, Importers, Backup
  ├── Views/
  │     ├── MainWindow          - 3-panelowy główny pulpit
  │     ├── PresentationWindow  - Silnik rzutnika Edge WebView2
  │     ├── SongEditorDialog    - Edytor pieśni i sekcji
  │     ├── SettingsDialog      - Ustawienia, ekrany, 23 logo, kopia
  │     ├── ImportReviewDialog  - Weryfikacja importu i autorów
  │     ├── ChordsSearchDialog  - Chwyty gitarowe i transpozycja
  │     └── UserManualDialog    - Podręcznik użytkownika i pomoc
  ├── Assets/                   - Ikony i szablony graficzne
  └── data/                     - Domyślna baza pieśni, ustawień i planszy
```
