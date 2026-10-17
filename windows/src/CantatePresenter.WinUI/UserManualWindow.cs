using CantatePresenter.Core.Text;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Instrukcja obsługi w osobnym oknie (UserManualView w macOS): sekcje po lewej, treść z wskazówkami i skrótami,
/// wyszukiwanie w treści. Teksty jak w macOS, z klawiszami Windows (Ctrl zamiast ⌘).
/// </summary>
public sealed class UserManualWindow : Window
{
    private sealed record Paragraph(string Heading, string Body, string? Tip = null, (string Key, string Description)[]? Shortcuts = null);
    private sealed record Section(string Id, string Title, string Glyph, Paragraph[] Content);

    private static UserManualWindow? current;

    public static void Open()
    {
        current ??= new UserManualWindow();
        current.Activate();
    }

    public static void CloseIfOpen() => current?.Close();

    public static UserManualWindow? Instance => current;

    private readonly Section[] sections;
    private readonly ListView sidebar = new() { SelectionMode = ListViewSelectionMode.Single };
    private readonly StackPanel content = new() { Spacing = 20, Padding = new Thickness(24) };
    private readonly TextBox search = new() { PlaceholderText = L("Szukaj w instrukcji..."), BorderThickness = new Thickness(0) };

    private UserManualWindow()
    {
        Title = L("Instrukcja Obsługi CantatePresenter");
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 720));
        Closed += (_, _) => current = null;
        sections = Sections();

        var root = new Grid { Background = Ui.Resource("ApplicationPageBackgroundThemeBrush") };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());

        var titleText = new StackPanel { Spacing = 2 };
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        titleRow.Children.Add(new TextBlock { Text = L("Instrukcja Obsługi CantatePresenter"), FontSize = 17, FontWeight = FontWeights.Bold });
        titleRow.Children.Add(Ui.Badge("v" + Services.Version, Ui.Blue, 10));
        titleText.Children.Add(titleRow);
        titleText.Children.Add(Ui.Note(L("Podręcznik użytkownika, skróty klawiszowe i wskazówki operacyjne")));
        var openFile = new Button { Content = L("Otwórz plik INSTRUKCJA.md") };
        openFile.Click += async (_, _) =>
        {
            var path = ResourcePath("INSTRUKCJA.md");
            if (File.Exists(path)) await Windows.System.Launcher.LaunchFileAsync(await Windows.Storage.StorageFile.GetFileFromPathAsync(path));
        };
        var github = new Button { Content = L("GitHub") };
        github.Click += async (_, _) => await Windows.System.Launcher.LaunchUriAsync(new Uri("https://github.com/andrzejoles/CantatePresenter"));
        var close = new Button { Content = L("Zamknij"), Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        close.Click += (_, _) => Close();
        var header = new Border
        {
            Child = Ui.Columns(12, (Ui.Icon(Glyphs.Help, 22, Ui.Blue), 0), (titleText, -1), (openFile, 0), (github, 0), (close, 0)),
            Padding = new Thickness(14), Background = Ui.Resource("SolidBackgroundFillColorBaseBrush"),
            BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"), BorderThickness = new Thickness(0, 0, 0, 1),
        };
        root.Children.Add(header);

        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused", "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused" })
            search.Resources[key] = Ui.Brush(Microsoft.UI.Colors.Transparent);
        search.TextChanged += (_, _) => RenderSidebar();
        var searchBar = new Border
        {
            Child = Ui.Columns(8, (Ui.Icon(Glyphs.Search, 13), 0), (search, -1)),
            Padding = new Thickness(10, 2, 10, 2), Background = Ui.Resource("SubtleFillColorSecondaryBrush"),
            BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"), BorderThickness = new Thickness(0, 0, 0, 1),
        };
        Grid.SetRow(searchBar, 1);
        root.Children.Add(searchBar);

        var split = new Grid();
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        split.ColumnDefinitions.Add(new ColumnDefinition());
        var sideBorder = new Border { Child = sidebar, BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"), BorderThickness = new Thickness(0, 0, 1, 0), Padding = new Thickness(0, 6, 0, 6) };
        split.Children.Add(sideBorder);
        var scroll = new ScrollViewer { Content = content };
        Grid.SetColumn(scroll, 1);
        split.Children.Add(scroll);
        Grid.SetRow(split, 2);
        root.Children.Add(split);
        sidebar.SelectionChanged += (_, _) => { if ((sidebar.SelectedItem as ListViewItem)?.Tag is Section section) RenderSection(section); };
        Content = root;
        RenderSidebar();
    }

    private void RenderSidebar()
    {
        var query = TextFold.Fold(search.Text.Trim());
        bool Matches(Section s) => query.Length == 0 || TextFold.Fold(s.Title).Contains(query) ||
            s.Content.Any(p => TextFold.Fold(p.Heading).Contains(query) || TextFold.Fold(p.Body).Contains(query) || TextFold.Fold(p.Tip).Contains(query));
        var selectedId = ((sidebar.SelectedItem as ListViewItem)?.Tag as Section)?.Id;
        sidebar.Items.Clear();
        foreach (var section in sections.Where(Matches))
        {
            sidebar.Items.Add(new ListViewItem { Content = Ui.Label(section.Glyph, section.Title, 14, null, 10), Tag = section });
        }
        var index = sidebar.Items.OfType<ListViewItem>().ToList().FindIndex(i => (i.Tag as Section)?.Id == selectedId);
        sidebar.SelectedIndex = sidebar.Items.Count == 0 ? -1 : Math.Max(0, index);
        if (sidebar.Items.Count == 0) content.Children.Clear();
    }

    private void RenderSection(Section section)
    {
        content.Children.Clear();
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        head.Children.Add(Ui.Icon(section.Glyph, 24, Ui.Blue));
        head.Children.Add(new TextBlock { Text = section.Title, FontSize = 22, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        content.Children.Add(head);
        content.Children.Add(Ui.Divider());
        foreach (var paragraph in section.Content)
        {
            var block = new StackPanel { Spacing = 8 };
            block.Children.Add(new TextBlock { Text = paragraph.Heading, FontSize = 16, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap });
            block.Children.Add(new TextBlock { Text = paragraph.Body, FontSize = 14, TextWrapping = TextWrapping.Wrap, LineHeight = 22, IsTextSelectionEnabled = true });
            if (paragraph.Tip is string tip)
            {
                var tipText = new TextBlock { Text = tip, FontSize = 13, Foreground = Ui.Brush(Ui.Orange), TextWrapping = TextWrapping.Wrap };
                block.Children.Add(new Border
                {
                    Child = Ui.Columns(8, (Ui.Icon(Glyphs.Info, 14, Ui.Orange), 0), (tipText, -1)),
                    Padding = new Thickness(10), CornerRadius = new CornerRadius(8), Background = Ui.Brush(Ui.Orange, 0.1),
                });
            }
            if (paragraph.Shortcuts is { Length: > 0 } shortcuts)
            {
                var list = new StackPanel { Spacing = 6 };
                list.Children.Add(new TextBlock { Text = L("Skróty klawiszowe:"), FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Ui.Secondary });
                foreach (var (key, description) in shortcuts)
                {
                    var keyCap = new Border
                    {
                        Child = new TextBlock { Text = key, FontFamily = new FontFamily("Consolas"), FontSize = 12, FontWeight = FontWeights.Bold },
                        Padding = new Thickness(8, 3, 8, 3), CornerRadius = new CornerRadius(5), Background = Ui.Brush(Ui.Gray, 0.14), HorizontalAlignment = HorizontalAlignment.Left,
                    };
                    list.Children.Add(Ui.Columns(10, (keyCap, 220), (new TextBlock { Text = description, FontSize = 13, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center }, -1)));
                }
                block.Children.Add(new Border { Child = list, Padding = new Thickness(10), CornerRadius = new CornerRadius(8), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });
            }
            content.Children.Add(block);
        }
    }

    private static Section[] Sections() =>
    [
        new("intro", L("1. Wprowadzenie"), Glyphs.Info,
        [
            new(L("O programie CantatePresenter"), L("CantatePresenter to narzędzie dla wspólnot, zespołów muzycznych, parafii oraz Ruchu Equipes Notre-Dame (END). Umożliwia prezentację słów pieśni, chwytów gitarowych i slajdów liturgicznych. Wersja dla Windows korzysta z tych samych plików danych i kopii zapasowych co wersja dla macOS.")),
            new(L("Układ trzypanelowy"), L("• Lewy panel: Biblioteka pieśni z wyszukiwarką oraz Plany nabożeństw.\n• Środkowy panel: Podgląd slajdów wybranej pieśni wraz z chwytami gitarowymi.\n• Prawy panel (Live Monitor): Podgląd stanu rzutnika na żywo, podgląd następnego slajdu i kontrola monitorów.")),
        ]),
        new("presentation", L("2. Prezentacja i Ekrany"), Glyphs.Monitor,
        [
            new(L("Prezentacja na projektorze lub monitorze"), L("Wybierz docelowy monitor w prawym panelu i kliknij 'Prezentuj na pełnym ekranie'. Kliknięcie w dowolny slajd włącza projekcję na żywo."),
                L("Możesz także otworzyć 'Okno testowe' w prawym panelu, aby testować wygląd slajdów bez podłączania projektora.")),
            new(L("Prezentacja na jednym ekranie & Wyjście ESC"), L("Gdy podłączony jest tylko 1 ekran, prezentacja uruchamia się w trybie pełnoekranowym na tym komputerze. Naciśnij w dowolnym momencie klawisz ESC, aby zakończyć projekcję, a przyciskiem „Zatrzymaj pełny ekran” wrócić do aplikacji."), null,
            [
                ("ESC", L("Natychmiastowe wyjście z pełnego ekranu")),
                (L("Spacja / → / ↓ / Page Down / Enter"), L("Przejście do następnego slajdu")),
                (L("← / ↑ / Page Up"), L("Przejście do poprzedniego slajdu")),
                ("B", L("Czarny ekran (Black Screen)")),
                ("C", L("Ukrycie tekstu (Clear Text)")),
            ]),
        ]),
        new("standby", L("3. Plansza Czuwania i Logo"), Glyphs.Image,
        [
            new(L("Plansza czuwania (Standby)"), L("Gdy nie trwa prezentacja pieśni, na rzutniku widoczna jest elegancka plansza czuwania z nazwą programu 'CantatePresenter', wersją, zegarem i wybranym logo."),
                L("Plansza aktualizuje się automatycznie przy każdej zmianie logo w Ustawieniach.")),
            new(L("Galeria 23 propozycji logo"), L("W Ustawieniach dostępna jest bogata galeria logotypów, w tym oficjalne logo Equipes Notre-Dame (END: ryba i obrączki przymierza), złota gitara akustyczna, Lira Dawidowa, klucz wiolinowy z korektorem, harfa i fale harmoniczne.")),
        ]),
        new("editor", L("4. Baza Pieśni i Edytor"), Glyphs.Edit,
        [
            new(L("Edycja istniejących pieśni i dodawanie nowych"), Lw("Kliknij 'Nowa pieśń' lub wybierz pieśń i kliknij 'Edytuj' (Cmd E). Edytor posiada podgląd podziału na slajdy na żywo.")),
            new(L("Obsługiwane sekcje utworu"), L("Program rozpoznaje znaczniki:\n• [Zwrotka 1], [Zwrotka 2], [1], [2]\n• [Refren], [Refren 1], [R]\n• [Coda] lub [Koda]\n• [Bridge] lub [Mostek]\n• [Przejście] lub [Interlude]\n• [Zakończenie] lub [Ending]\n• [Intro] oraz [Outro]"),
                L("Możesz też po prostu oddzielać zwrotki pustą linią — program sam podzieli tekst na slajdy.")),
        ]),
        new("chords", L("5. Chwyty Gitarowe"), Glyphs.Music,
        [
            new(L("Akordy i transpozycja"), L("Pieśń może zawierać chwyty gitarowe (np. D A h G). Przyciski +1 / -1 pozwalają transponować tonację całego utworu jednym kliknięciem.")),
            new(L("Biblioteka chwytów"), L("Przycisk „Chwyty” przy pieśni otwiera wyszukiwarkę opracowań: chwyty samej pieśni i wbudowaną bibliotekę chwytów popularnych pieśni. Wybrane opracowanie można przetransponować i wstawić do pieśni. Ekran dla muzyków („Muzycy”) pokazuje chwyty nad tekstem bieżącego slajdu.")),
        ]),
        new("dictation", L("6. Dyktowanie Głosowe"), Glyphs.Mic,
        [
            new(L("Wprowadzanie tekstu i szukanie głosem"), L("Kliknij ikonę mikrofonu w edytorze lub obok paska szukania, aby podyktować słowa pieśni lub wyszukać utwór głosem."),
                L("Język rozpoznawania mowy (domyślnie polski pl-PL) można ustawić w Ustawieniach.")),
        ]),
        new("plans", L("7. Plany Nabożeństw"), Glyphs.Checklist,
        [
            new(L("Przygotowanie listy utworów"), L("W lewym panelu przełącz na 'Plan'. Utwórz nowy plan na mszę lub spotkanie i dodawaj pieśni z biblioteki (prawy przycisk myszy na pieśni albo „+ Do planu”). Naciśnięcie spacji na końcu utworu płynnie przełącza do kolejnej pieśni z planu.")),
        ]),
        new("import", L("8. Import i Eksport"), Glyphs.ImportExport,
        [
            new(L("Formaty Holyrics, OpenLyrics, JSON i TXT"), L("Przyciskiem Import/Eksport możesz importować bazy Holyrics (.mufl, .muf), pliki tekstowe .txt, pliki JSON, XML oraz pliki z CCLI SongSelect. Przed dodaniem program pokazuje wykryte duplikaty."),
                L("Aplikacja automatycznie naprawia polskie litery z kodowań Windows-1250 i ISO-8859-2 oraz wykrywa duplikaty.")),
        ]),
        new("backup", L("9. Kopie Zapasowe i Dysk Google"), Glyphs.Cloud,
        [
            new(L("Pełny backup (.cantatebackup)"), L("Kopia zapasowa zabezpiecza całą bazę pieśni, chwyty, plany, ustawienia, planszę standby, języki i loga.")),
            new(L("Integracja z Google Drive"), L("Po autoryzacji Google OAuth w Ustawieniach, kopie są automatycznie przesyłane do dedykowanego folderu CantatePresenter_Backups w chmurze."),
                L("Włącz opcję 'Automatyczny backup przy zamykaniu', aby program tworzył kopię po każdym użyciu.")),
        ]),
        new("shortcuts", L("10. Skróty Klawiszowe"), Glyphs.Keyboard,
        [
            new(L("Szybkie sterowanie prezentacją"), L("Domyślne skróty prezentacji (zmienisz je w Ustawieniach → Skróty klawiszowe) oraz klawisze stałe. {0}",
                L("Skróty działają, gdy pole wyszukiwania jest nieaktywne (po starcie albo po Esc). Klawisz wybrany powyżej ma pierwszeństwo przed klawiszem stałym, np. R przypisane do czarnego ekranu przestaje włączać refren.")), null,
            [
                (L("Spacja"), L("Następny slajd / następna pieśń z planu")),
                (L("Enter"), L("Uruchomienie projekcji zaznaczonej pieśni")),
                ("[ / ]", L("Poprzednia / następna pieśń z planu")),
                ("B", L("Włącz/Wyłącz czarny ekran")),
                ("C", L("Włącz/Wyłącz ukrycie tekstu")),
                .. SettingsDialog.FixedKeys(),
            ]),
        ]),
    ];
}
