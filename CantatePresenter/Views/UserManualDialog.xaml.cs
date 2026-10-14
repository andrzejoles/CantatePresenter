using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using CantatePresenter.Models;
using CantatePresenter.Services;

namespace CantatePresenter.Views
{
    public class ManualChapter
    {
        public string Title { get; set; } = "";
        public string Content { get; set; } = "";
    }

    public partial class UserManualDialog : Window
    {
        private readonly List<ManualChapter> _allChapters = new();

        public UserManualDialog()
        {
            InitializeComponent();
            LoadChapters();
        }

        private void LoadChapters()
        {
            _allChapters.Clear();
            _allChapters.Add(new ManualChapter
            {
                Title = "1. Wprowadzenie i Układ",
                Content = @"CantatePresenter to profesjonalny program do prezentacji tekstów pieśni religijnych, slajdów liturgicznych oraz chwytów gitarowych dla Windows 11.

Aplikacja posiada przejrzysty układ trzypanelowy:
• Lewy panel: Baza pieśni z wyszukiwaniem oraz Zestawy pieśni (plany nabożeństw).
• Środkowy panel: Podgląd slajdów wybranej pieśni wraz z chwytami gitarowymi i transpozycją.
• Prawy panel (Live Monitor): Podgląd stanu rzutnika na żywo, podgląd następnego slajdu i kontrola ekranów."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "2. Prezentacja i Ekrany",
                Content = @"Program automatycznie wykrywa podłączone projektory i monitory.

• Prezentacja na projektorze: Wybierz w Ustawieniach Ekran 2 i kliknij 'Prezentuj na pełnym ekranie'.
• Prezentacja na 1 ekranie: W trybie pojedynczego ekranu prezentacja uruchamia się na całym ekranie.
• Wyjście z prezentacji: Naciśnij klawisz ESC w dowolnym momencie, aby natychmiast wrócić do programu.
• Okno testowe: Umożliwia sprawdzenie wyglądu slajdów w oknie bez podłączania projektora."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "3. Plansza Czuwania i Logo",
                Content = @"Gdy nie trwa projekcja żadnego utworu, na ekranie rzutnika wyświetlana jest elegancka plansza czuwania z nazwą programu 'CantatePresenter', wersją oraz wybranym logo.

W galerii dostępna jest 23 propozycji logotypów, w tym:
• Oficjalne logo Equipes Notre-Dame (END: ryba i obrączki przymierza małżeńskiego)
• Złota gitara akustyczna
• Harfa i fale harmoniczne
• Lira Dawidowa
• Krzyż z wiązką światła projektora"
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "4. Edytor i Sekcje Utworu",
                Content = @"Edytor rozpoznaje znaczniki struktury utworu:
• [Zwrotka 1], [Zwrotka 2], [1], [2]
• [Refren], [Refren 1], [R]
• [Coda] lub [Koda]
• [Bridge] lub [Mostek]
• [Przejście] lub [Interlude]
• [Zakończenie] lub [Ending]
• [Intro] oraz [Outro]

Edytor posiada podgląd podziału na slajdy na żywo po prawej stronie."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "5. Chwyty Gitarowe",
                Content = @"Program obsługuje akordy gitarowe:
• Wbudowana baza popularnych pieśni (Barka, Abba Ojcze, Jezus Siłą Mą).
• Transpozycja tonacji w górę i w dół o dowolną liczbę półtonów.
• Wyszukiwanie chwytów w internecie bezpośrednio z aplikacji.
• Zapisywanie akordów do wybranego utworu."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "6. Import i Eksport",
                Content = @"Obsługiwane formaty:
• Pliki programu Holyrics (.mufl, .muf, .hly, .holyrics)
• Pliki tekstowe (.txt) z automatycznym wykrywaniem kodowania (UTF-8, Windows-1250, ISO-8859-2)
• Bazy danych JSON (.json)
• Weryfikacja autorów przed importem: możliwość odznaczenia fałszywych autorów (np. 'Łysa Góra' -> 'Nieznany')
• Automatyczna naprawa polskich znaków diakrytycznych (naprawianie mojibake)."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "7. Kopia Zapasowa (Backup)",
                Content = @"Format archiwum: .cantatebackup (lub .holyricsbackup / .zip).

Kopia obejmuje całą bazę pieśni, chwyty, plany nabożeństw, planszę startową, wybrane logo oraz wszystkie ustawienia programu.
Możliwa jest również synchronizacja z dyskiem Google Drive (konto )."
            });

            _allChapters.Add(new ManualChapter
            {
                Title = "8. Skróty Klawiszowe",
                Content = @"• Spacja / Strzałka w prawo / w dół: Następny slajd
• Strzałka w lewo / w górę: Poprzedni slajd
• [ oraz ]: Poprzednia / Następna pieśń
• B: Czarny ekran (Black Screen)
• C: Ukryj tekst (Clear Text)
• ESC: Wyjście z pełnego ekranu
• Ctrl + / Ctrl -: Powiększenie / pomniejszenie interfejsu (Zoom)
• Ctrl 0: Domyślny rozmiar interfejsu (100%)"
            });

            ChaptersListBox.ItemsSource = _allChapters;
            if (_allChapters.Count > 0)
                ChaptersListBox.SelectedIndex = 0;
        }

        private void ChaptersListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (ChaptersListBox.SelectedItem is ManualChapter ch)
            {
                ChapterTitleText.Text = ch.Title;
                ChapterBodyText.Text = ch.Content;
            }
        }

        private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var q = Song.FoldString(SearchBox.Text);
            if (string.IsNullOrEmpty(q))
            {
                ChaptersListBox.ItemsSource = _allChapters;
            }
            else
            {
                var filtered = _allChapters.Where(c => Song.FoldString(c.Title).Contains(q) || Song.FoldString(c.Content).Contains(q)).ToList();
                ChaptersListBox.ItemsSource = filtered;
                if (filtered.Count > 0)
                    ChaptersListBox.SelectedIndex = 0;
            }
        }

        private void OpenMarkdown_Click(object sender, RoutedEventArgs e)
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var docPath = Path.Combine(baseDir, "INSTRUKCJA.md");
            if (File.Exists(docPath))
            {
                Process.Start(new ProcessStartInfo { FileName = docPath, UseShellExecute = true });
            }
            else
            {
                MessageBox.Show("Plik INSTRUKCJA.md znajduje się w katalogu głównym aplikacji.", "CantatePresenter", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void OpenGitHub_Click(object sender, RoutedEventArgs e)
        {
            Process.Start(new ProcessStartInfo { FileName = "https://github.com/andrzejoles/CantatePresenter", UseShellExecute = true });
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
    }
}
