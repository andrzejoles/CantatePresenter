# CantatePresenter — Instrukcja Obsługi Programu

Kompletny podręcznik użytkownika natywnej aplikacji **CantatePresenter** dla systemu **macOS** (Apple Silicon M1–M5).

---

## 📑 Spis Treści
1. [Wprowadzenie i Pierwsze Kroki](#1-wprowadzenie-i-pierwsze-kroki)
2. [Prezentacja na Żywo i Obsługa Ekranów](#2-prezentacja-na-żywo-i-obsługa-ekranów)
3. [Plansza Czuwania (Standby) i Wybór Logo](#3-plansza-czuwania-standby-i-wybór-logo)
4. [Baza Pieśni i Zaawansowany Edytor](#4-baza-pieśni-i-zaawansowany-edytor)
5. [Chwyty Gitarowe, Wikiźródła i Autorzy](#5-chwyty-gitarowe-wikiźródła-i-autorzy)
6. [Dyktowanie Głosowe](#6-dyktowanie-głosowe)
7. [Plany Nabożeństw i Spotkań](#7-plany-nabożeństw-i-spotkań)
8. [Import z Holyrics, OpenLyrics, JSON i TXT](#8-import-z-holyrics-openlyrics-json-i-txt)
9. [Kopie Zapasowe i Dysk Google](#9-kopie-zapasowe-i-dysk-google)
10. [Tłumaczenia Interfejsu (i18n)](#10-tłumaczenia-interfejsu-i18n)
11. [Tabela Skrótów Klawiszowych](#11-tabela-skrótów-klawiszowych)

---

## 1. Wprowadzenie i Pierwsze Kroki

**CantatePresenter** to profesjonalne, nowoczesne narzędzie zaprojektowane dla wspólnot chrześcijańskich, zespołów muzycznych, parafii oraz Ruchu **Equipes Notre-Dame (END)** do wyświetlania słów pieśni, chwytów gitarowych i slajdów liturgicznych na projektorach i ekranach zewnętrznych.

### Układ Trzypanelowy
Okno główne programu podzielone jest na 3 intuicyjne strefy:
* **Lewy panel**: Przełącznik między **Biblioteką pieśni** (z błyskawiczną wyszukiwarką pełnotekstową) a **Planem nabożeństwa** (listą przygotowanych utworów).
* **Środkowy panel**: Podgląd slajdów wybranej pieśni wraz z chwytami gitarowymi oraz przyciskami edycji.
* **Prawy panel (Live Monitor)**: Podgląd aktualnego stanu rzutnika na żywo, podgląd następnego slajdu, szybkie sterowanie projekcją oraz wybór docelowego monitora.

---

## 2. Prezentacja na Żywo i Obsługa Ekranów

### Projekcja na monitorze zewnętrznym lub projektorze
1. W prawym panelu w sekcji **Ekrany i Projektor** wybierz podłączony wyświetlacz (np. projektor HDMI, telewizor lub monitor zewnętrzny).
2. Kliknij **Prezentuj na pełnym ekranie**.
3. Wybierz dowolną pieśń z biblioteki lub planu i kliknij na slajd, aby natychmiast rozpocząć wyświetlanie.

### Prezentacja na pojedynczym ekranie (Single-Screen Mode)
* Bez zewnętrznego ekranu przycisk **Prezentuj na pełnym ekranie** zakrywa ekran Twojego Maca. Program nie uruchamia pełnego ekranu sam.
* **Wyjście z prezentacji**: klawisz **`Esc`** zamyka pełny ekran, kończy projekcję i wraca do okna głównego.
* Na starcie pełnego ekranu wyświetla się na chwilę podpowiedź o klawiszu `Esc`.
* Dopóki pełny ekran zakrywa okno główne (także przy obrazie lustrzanym na projektorze), polecenia menu otwierające okna i arkusze (np. **Szybki tekst**, **Importuj pieśni...**, kopia zapasowa, **Szukaj pieśni**) są nieaktywne, bo okno zostałoby pod projekcją. Najpierw zakończ projekcję klawiszem `Esc`. Pytanie przy zamykaniu programu (`⌘Q`) jest widoczne nad projekcją.

### Esc przy dwóch ekranach
* Okno główne zostaje aktywne, a klawisze działają w nim jak zwykle. **`Esc`** gasi tekst: projektor pokazuje planszę czuwania, okno projekcji zostaje otwarte.
* Jeśli klikniesz okno na projektorze, pierwsze **`Esc`** w nim gasi tekst, a dopiero drugie zamyka okno projekcji.
* Okno projekcji zamyka też przycisk **Zatrzymaj pełny ekran** w prawym panelu.

### Kontrola w trakcie projekcji
* **Następny slajd**: `Spacja`, `Strzałka w prawo`, `Strzałka w dół` lub `Page Down`. `Enter` przełącza slajd tylko w oknie projekcji; w oknie głównym uruchamia projekcję zaznaczonej pieśni od pierwszego slajdu.
* **Poprzedni slajd**: `Strzałka w lewo`, `Strzałka w górę` lub `Page Up`.
* **Refren i zwrotki**: `R` przechodzi do pierwszego refrenu, cyfry `1`–`9` do zwrotki o tym numerze. Znaczek w nawiasie na karcie slajdu (np. `[2]`, `[R]`) pokazuje, który klawisz do niej prowadzi.
* **Czarny ekran (Black Screen)**: Klawisz **`B`** — natychmiast wygasza rzutnik do czerni (np. na czas modlitwy w ciszy lub kazania).
* **Ukrycie tekstu (Clear Text)**: Klawisz **`C`** — zachowuje tło/planszę, ukrywając sam tekst pieśni.
* **Powrót do planszy czuwania**: przycisk **Stop** (`■`) albo `Esc`. Po zatrzymaniu strzałki, `Spacja`, `R` i cyfry nie zmieniają slajdów. `Enter` w oknie głównym pokazuje zaznaczoną pieśń od pierwszego slajdu (nie wraca do slajdu sprzed zatrzymania), a kliknięcie slajdu pokazuje ten slajd. Do tego samego slajdu wraca przycisk **Wznów projekcję** w pilocie.
* **Zmiana pieśni z planu**: `[` / `]` i przyciski **Poprz. pieśń** / **Nast. pieśń** działają także po zatrzymaniu: od razu pokazują poprzednią albo następną pieśń z planu.

### Ekran dla muzyków (chwyty)
Muzycy widzą bieżący slajd z chwytami nad tekstem i następny slajd:
* **Na osobnym monitorze**: przycisk **Muzycy** na górnym pasku otwiera okno, które przenosisz na monitor muzyków (pełny ekran zielonym przyciskiem okna). Okno muzyków nie obsługuje klawiszy prezentacji: po kliknięciu w nie kliknij z powrotem okno główne, żeby znów przełączać slajdy klawiaturą.
* **Na tabletach i telefonach**: w oknie **Pilot** wybierz **Muzycy (chwyty, tylko podgląd)** i daj muzykom zeskanować kod. Ten kod nie pozwala sterować prezentacją.

Każdy ekran ma własną **transpozycję** (np. pod capo) i wielkość czcionki. Gdy chwyty są zapisane tylko przy pierwszej zwrotce, kolejne zwrotki dostają te same chwyty (z dopiskiem „Chwyty jak w: …”). Chwyty dodajesz w edytorze pieśni (zakładka chwytów) albo importem ChordPro.

### Pilot ze smartfona
Slajdy można przełączać telefonem (iPhone lub Android), bez instalowania aplikacji:
1. Kliknij **Pilot** na górnym pasku i włącz przełącznik **Włącz pilota**.
2. Zeskanuj aparatem telefonu wyświetlony kod QR (albo wpisz adres w przeglądarce telefonu).
3. Na telefonie: **Dalej** / **Wstecz** (lub przesunięcie palcem po podglądzie), czarny ekran, ukrycie tekstu, zakończenie projekcji, wybór slajdu i pieśni z planu.
4. **Szukaj pieśni**: wpisz tytuł, autora albo fragment tekstu (polskie znaki można pominąć) i dotknij wyniku, żeby od razu go wyświetlić.
5. Po **Zakończ projekcję** duży przycisk zmienia się na **Wznów projekcję**: projekcja wraca do tej samej pieśni i slajdu. Dotknięcie slajdu na liście też ją wznawia, od tego slajdu.

Telefon musi być w tej samej sieci Wi-Fi co Mac. Kod zawiera jednorazowy klucz dostępu: przycisk **Nowy kod (rozłącza telefony)** odłącza wszystkie telefony. Pilot działa, dopóki aplikacja jest otwarta.

---

## 3. Plansza Czuwania (Standby) i Wybór Logo

Gdy żadna pieśń nie jest prezentowana na żywo, projektor wyświetla planszę czuwania: wybrane logo, nazwę programu, wersję, zegar i napis „Gotowy do projekcji”. W **Ustawieniach → Plansza startowa i Logo aplikacji** możesz wskazać własny plik HTML; przycisk **Otwórz plik planszy w edytorze / przeglądarce** otwiera plik, który jest aktualnie używany. Podgląd w prawym panelu okna głównego pokazuje tę samą planszę w pomniejszeniu.

### Wybór oficjalnego logo:
1. Otwórz **Ustawienia** i kliknij **Wybierz inne logo (23 propozycje)...**.
2. W galerii dostępnych jest **23 profesjonalnych propozycji**, w tym:
   * **Oficjalne logo Equipes Notre-Dame (END)** (oryginalne pobrane ze strony end.org.pl: ryba i obrączki przymierza),
   * Złota gitara akustyczna z rozetą i strunami,
   * Harfa i Lira Dawidowa z falami rezonansu,
   * Klucz wiolinowy z korektorem pasmowym audio,
   * Symfonia i falująca pięciolinia w 3D,
   * Wokal i fale harmoniczne,
   * Promienie chwały, gołębica, wschodzące słońce nad górami, monogram i wiele innych.
3. Po wybraniu logo plansza startowa automatycznie i natychmiast aktualizuje się zarówno w oknie podglądu, jak i na rzutniku.

---

## 4. Baza Pieśni i Zaawansowany Edytor

### Dodawanie i edycja pieśni
* Kliknij **Nowa pieśń**, aby otworzyć edytor nowego utworu.
* Kliknij **Edytuj** (`⌘E`) lub dwukrotnie kliknij w pieśń na liście, aby zmodyfikować istniejącą pieśń.

### Obsługiwane sekcje utworu
Edytor automatycznie rozpoznaje i formatuje oznaczenia sekcji:
* `[Zwrotka 1]`, `[Zwrotka 2]`, `[1]`, `[2]`
* `[Refren]`, `[Refren 1]`, `[R]`
* `[Coda]` lub `[Koda]` (zwieńczenie utworu)
* `[Bridge]` lub `[Mostek]`
* `[Przejście]` lub `[Interlude]`
* `[Zakończenie]` lub `[Ending]`
* `[Intro]` oraz `[Outro]`

> [!TIP]
> Jeśli nie chcesz wpisywać znaczników w nawiasach, wystarczy oddzielić poszczególne zwrotki **pustą linią** — program sam ponumeruje slajdy jako *Zwrotka 1*, *Zwrotka 2* itd.

---

## 5. Chwyty Gitarowe, Wikiźródła i Autorzy

### Wyświetlanie i transpozycja akordów
* Chwyty wpisujesz w edytorze pieśni w widoku **Chwyty gitarowe / Taby** (np. `D A h G` nad tekstem). Zborowi na projektorze się nie wyświetlają; widzą je muzycy.
* Przyciskami **Transpozycja ♭ -1 / ♯ +1** transponujesz chwyty o pół tonu w dół lub w górę (np. dostosowując je do możliwości wokalnych prowadzącego).

### Teksty z Wikiźródeł
Przycisk **Online** przeszukuje [Wikiźródła](https://pl.wikisource.org): tradycyjne pieśni w domenie publicznej lub na wolnej licencji. Przy imporcie w pieśni zapisuje się adres strony źródłowej i licencja. Współczesnych pieśni objętych prawem autorskim tam nie ma; służy do nich CCLI SongSelect (rozdział 8).

### Okno chwytów
1. Kliknij **Chwyty** w panelu środkowym albo **Wyszukaj chwyty...** w edytorze.
2. Program pokazuje pasujące opracowania z wbudowanej bazy chwytów popularnych pieśni.
3. Wybierz opracowanie, w razie potrzeby transponuj i kliknij **Zastosuj chwyty do pieśni**.

Chwyty możesz też zaimportować z pliku ChordPro (np. z CCLI SongSelect, rozdział 8).

### Weryfikacja autora i tytułu
* Przycisk **Tytuł/Autor** na górnym pasku (albo **Wyszukaj tytuł i autora online...** w menu pieśni pod prawym przyciskiem myszy) wyszukuje autora i tytuł dla zaznaczonej pieśni lub dla całej biblioteki.
* Okno podglądu pozwala odznaczyć niepewne propozycje przed zapisaniem.

---

## 6. Dyktowanie Głosowe

CantatePresenter posiada zintegrowany moduł rozpoznawania mowy:
* **Dyktowanie tekstu pieśni**: W edytorze kliknij ikonę mikrofonu i podyktuj słowa pieśni — tekst pojawi się automatycznie w polu edycji.
* **Wyszukiwanie głosowe**: Kliknij mikrofon obok paska szukania i wypowiedz tytuł lub fragment pieśni (np. *"Pan kiedyś stanął nad brzegiem"*), aby natychmiast odnaleźć utwór.
* Język dyktowania można zmienić w **Ustawieniach** (domyślnie: Polski `pl-PL`).

---

## 7. Plany Nabożeństw i Spotkań

1. Przełącz lewy panel na zakładkę **Plan nabożeństwa**.
2. Kliknij **+** (*Utwórz nowy plan*), aby utworzyć listę na nabożeństwo, mszę lub spotkanie modlitewne.
3. Dodawaj pieśni przyciskiem **+ Do planu** w panelu środkowym albo poleceniem **Dodaj do aktywnego planu** w menu pieśni pod prawym przyciskiem myszy.
4. Kolejność zmieniasz strzałkami **▲ / ▼** (*Przesuń wyżej*, *Przesuń niżej*) przy pieśni w planie.
5. W trakcie projekcji, na ostatnim slajdzie pieśni, kolejne naciśnięcie `Spacji` przełącza na pierwszy slajd następnej pieśni z planu.

---

## 8. Import z Holyrics, OpenLyrics, JSON i TXT

W oknie **Import/Eksport** (`⌘I`) możesz zasilić bazę z dowolnych istniejących zbiorów:
* **Bazy Holyrics (`.mufl`, `.muf`, `.hly`, eksport `.xml`)**: Natywny deserializator odczytuje kompletne archiwa programu Holyrics wraz z metadanymi i kodowaniem.
* **Pliki i foldery tekstowe (`.txt`)**: Możesz wskazać pojedynczy plik lub **cały folder** zawierający setki plików tekstowych — program automatycznie rozpozna kodowanie znaków (UTF-8, Windows-1250, ISO-8859-2) i naprawi polskie litery (ą, ę, ś, ć, ż, ź, ł, ó, ń).
* **Format JSON (`.json`)**: Importuje zarówno kopie zapasowe, jak i tablice obiektów z innych systemów.

### Licencja CCLI
W **Ustawieniach → Licencja CCLI i prawa autorskie** wpisz numer licencji parafii i wybierz, na którym slajdzie pokazywać informację o prawach (tytuł, autorzy, ©, numer pieśni i licencji). Dotyczy pieśni z numerem CCLI. Program zapisuje też każde wyświetlenie takiej pieśni (raz dziennie); przycisk **Eksportuj raport CCLI (CSV)** zapisuje je do pliku, z którym zgłosisz użycie na stronie CCLI.

* **Pliki z CCLI SongSelect (`.txt`, `.usr`, ChordPro `.pro`)**: Pobierz pieśń na koncie SongSelect swojej parafii (przycisk **Szukaj w SongSelect** w oknie Online otwiera wyszukiwarkę) i zaimportuj plik. Zapisują się autorzy, prawa autorskie i numer CCLI, a z ChordPro także akordy.
* **Wykrywanie duplikatów**: Przed zatwierdzeniem importu program analizuje bibliotekę i wyświetla raport, chroniąc przed powielaniem istniejących utworów.

---

## 9. Kopie Zapasowe i Dysk Google

Program dba o pełne bezpieczeństwo Twojej bazy:

### Lokalna kopia zapasowa (`.cantatebackup`)
* Wybierz z menu **Plik -> Utwórz pełną kopię zapasową...** (`⌘B`).
* Plik archiwum zawiera bazę pieśni z chwytami, plany nabożeństw, ustawienia, własne języki i raport CCLI (oraz plik `standby.html` z folderu danych, jeśli został po starszej wersji). Logo są wbudowane w program.
* Własnego pliku planszy wybranego w **Ustawieniach** kopia nie zawiera: po przywróceniu na innym Macu wskaż go ponownie (do tego czasu wyświetla się plansza wbudowana).
* Przywrócenie kopii na nowym komputerze trwa kilka sekund.

### Kopia w chmurze Google Drive
1. W **Ustawieniach** w sekcji *Kopia zapasowa i Dysk Google* kliknij **Połącz z kontem Google...** i dokończ logowanie w przeglądarce. Tokeny trafiają do Pęku kluczy macOS.
2. Kopie trafiają do folderu `CantatePresenter_Backups` na Twoim Dysku Google (nazwę folderu zmienisz w Ustawieniach).
3. Kopię wysyłasz przyciskiem **Wyślij bieżący backup na Dysk Google**, a wcześniejsze wersje przeglądasz i przywracasz przyciskiem **Przeglądaj i przywróć kopie z Dysku Google...**.
4. Opcja **Twórz i wysyłaj kopię na Dysk Google automatycznie przy zamykaniu aplikacji** wysyła kopię przy każdym zamknięciu programu. Bez niej kopie wysyłasz ręcznie.

---

## 10. Tłumaczenia Interfejsu (i18n)

Aplikacja jest w pełni przystosowana do pracy międzynarodowej:
* **Wbudowane języki**: Polski (`pl`), Angielski (`en`), Niemiecki (`de`), Hiszpański (`es`), Ukraiński (`uk`).
* **Eksport do tłumaczenia**: W Ustawieniach w sekcji *Języki i dyktowanie głosowe* przycisk **Eksportuj słownik do tłumaczenia (JSON dla AI)...** zapisuje plik JSON z opisami kontekstowymi (`context`) dla modeli AI (np. ChatGPT, Gemini, Claude).
* **Import tłumaczenia**: Wgranie przetłumaczonego pliku natychmiast dodaje nowy język do listy wyboru.

---

## 11. Tabela Skrótów Klawiszowych

Skróty prezentacji działają, gdy pole wyszukiwania jest nieaktywne (po uruchomieniu aplikacji albo po naciśnięciu `Esc` w polu). Pole aktywujesz kliknięciem albo `⌘F`. Skróty z pierwszej tabeli zmienisz w **Ustawieniach → Skróty klawiszowe**; wybrany tam klawisz ma pierwszeństwo przed klawiszem stałym. Wyjątek: `↑` i `↓` na liście pieśni zawsze zmieniają zaznaczenie.

**Domyślne skróty (do zmiany w Ustawieniach)**

| Skrót | Działanie |
|---|---|
| **Spacja** | Następny slajd / następna pieśń w planie |
| **Enter** | Uruchomienie projekcji zaznaczonej pieśni od pierwszego slajdu (w oknie projekcji: następny slajd) |
| **[** / **]** | Poprzednia / następna pieśń z planu |
| **B** | Przełączenie czarnego ekranu (Black Screen) |
| **C** | Ukrycie tekstu (Clear Text) |
| **Esc** | Zakończenie projekcji (przy dwóch ekranach gasi tekst, patrz rozdział 2) |

**Klawisze stałe**

| Skrót | Działanie |
|---|---|
| **←** / **↑** | Poprzedni slajd (**↑** na liście pieśni: poprzednia pieśń) |
| **→** / **↓** | Następny slajd (**↓** na liście pieśni: następna pieśń) |
| **Page Up** / **Page Down** | Poprzedni / następny slajd (pilot), także w polu wyszukiwania |
| **Enter** w oknie projekcji | Następny slajd |
| **Esc** w polu wyszukiwania | Wyjście z pola |
| **R** | Refren (pierwszy w pieśni) |
| **1 – 9** | Zwrotka o tym numerze (znaczek na karcie slajdu) |
| **⌘F** | Szukaj pieśni (**Enter**: wybór pierwszego wyniku) |
| **⌘T** | Szybki tekst na żywo |
| **⌘E** | Edytuj zaznaczoną pieśń |
| **⌘I** | Import pieśni |
| **⌘B** | Utwórz pełną kopię zapasową (.cantatebackup) |
| **⌘?** | Instrukcja obsługi |
| **⌘+** / **⌘−** / **⌘0** | Powiększenie / Pomniejszenie / Reset skali interfejsu (100%) |
| **⌘Q** | Zakończenie programu (z kopią na Dysk Google, jeśli włączona) |

---

*CantatePresenter — Śpiewajcie Panu pieśń nową (Cantate Domino canticum novum)*
