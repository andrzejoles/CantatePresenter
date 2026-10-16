using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Input;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Wiersz listy pieśni (wiązanie danych w szablonie listy).</summary>
[Bindable]
public sealed class SongRow
{
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Subtitle { get; init; } = "";
    public string Info { get; init; } = "";
    public string Snippet { get; init; } = "";
    public Visibility SnippetVisibility => Snippet.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
}

/// <summary>
/// Okno główne: górny pasek, biblioteka/plan, slajdy pieśni, ekran na żywo i pasek skrótów (układ jak w macOS).
/// Skróty idą przez <see cref="KeyboardRouter"/> (te same reguły i kody co w macOS); przy otwartym oknie dialogowym nie działają.
/// </summary>
public sealed partial class MainWindow : Window
{
    private Library library => Services.Library;
    private readonly PresentationWindow presentation = new();
    private MusiciansWindow? musicians;
    private readonly Grid root = new();
    private readonly Grid leftPanel = new();
    private readonly Grid middlePanel = new();
    private readonly StackPanel rightPanel = new() { Spacing = 10, Padding = new Thickness(12) };
    private readonly SlideView livePreview = new();
    private readonly SlideView nextPreview = new();
    private ListView? songList;
    private TextBox? searchBox;
    private string query = "";
    private SearchScope scope = SearchScope.All;
    private bool showingPlan;
    private bool showChords;
    private int chordsTranspose;
    internal bool DialogOpen;

    public MainWindow()
    {
        Title = L("CantatePresenter — Prezenter Pieśni & Słowa");
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1500, 920));
        Content = root;
        root.PreviewKeyDown += OnPreviewKeyDown;
        presentation.KeyPressed += key => HandleKey(key, KeyContext.Presentation);
        presentation.AppWindow.Hide();
        library.Changed += reason => DispatcherQueue.TryEnqueue(() => OnLibraryChanged(reason));
        Closed += (_, _) =>
        {
            presentation.Close();
            musicians?.Close();
        };
        BuildUi();
    }

    public PresentationWindow Presentation => presentation;

    // MARK: - Layout

    private void BuildUi()
    {
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RequestedTheme = ElementTheme.Default;
        root.Background = (Brush)Application.Current.Resources["ApplicationPageBackgroundThemeBrush"];

        var toolbar = Toolbar();
        Grid.SetRow(toolbar, 0);
        root.Children.Add(toolbar);

        var issues = IssuesBar();
        Grid.SetRow(issues, 1);
        root.Children.Add(issues);

        var main = new Grid { ColumnSpacing = 0 };
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(320), MinWidth = 220 });
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 260 });
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(400), MinWidth = 280 });
        var leftBorder = Panel(leftPanel);
        var middleBorder = Panel(middlePanel);
        var rightBorder = Panel(new ScrollViewer { Content = rightPanel });
        Grid.SetColumn(leftBorder, 0);
        Grid.SetColumn(middleBorder, 1);
        Grid.SetColumn(rightBorder, 2);
        main.Children.Add(leftBorder);
        main.Children.Add(middleBorder);
        main.Children.Add(rightBorder);
        Grid.SetRow(main, 2);
        root.Children.Add(main);

        var shortcuts = ShortcutsBar();
        Grid.SetRow(shortcuts, 3);
        root.Children.Add(shortcuts);

        RenderLeft();
        RenderMiddle();
        RenderRight();
    }

    private static Border Panel(UIElement child) => new()
    {
        Child = child,
        BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        BorderThickness = new Thickness(0, 0, 1, 0),
    };

    private static Button ToolButton(string symbol, string text, RoutedEventHandler click, string? tip = null)
    {
        var button = new Button { Content = $"{symbol}  {text}", Margin = new Thickness(0, 0, 6, 0) };
        button.Click += click;
        ToolTipService.SetToolTip(button, tip ?? text);
        return button;
    }

    private UIElement Toolbar()
    {
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Padding = new Thickness(10, 8, 10, 8) };
        bar.Children.Add(new TextBlock { Text = "♫ CantatePresenter", FontWeight = FontWeights.Bold, FontSize = 16, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 16, 0) });
        bar.Children.Add(ToolButton("⚡", L("Szybki tekst"), async (_, _) => await QuickTextAsync()));
        bar.Children.Add(ToolButton("＋", L("Nowa pieśń"), async (_, _) => await EditSongAsync(null)));
        bar.Children.Add(ToolButton("✎", L("Edytuj"), async (_, _) => { if (library.SelectedSong is Song s && s != library.TemporarySong) await EditSongAsync(s); }));

        var importExport = new DropDownButton { Content = "⇅  " + L("Import/Eksport"), Margin = new Thickness(0, 0, 6, 0) };
        var menu = new MenuFlyout();
        void Item(string text, Func<Task> action, bool enabled = true)
        {
            var item = new MenuFlyoutItem { Text = text, IsEnabled = enabled };
            item.Click += async (_, _) => await action();
            menu.Items.Add(item);
        }
        Item(L("Importuj pliki..."), () => ImportExport.ImportFilesAsync(this));
        menu.Items.Add(new MenuFlyoutSeparator());
        Item(L("Utwórz kopię zapasową"), () => ImportExport.CreateBackupAsync(this));
        Item(L("Przywróć z kopii..."), () => ImportExport.RestoreBackupAsync(this));
        Item(L("Cofnij ostatnie przywrócenie"), () => ImportExport.UndoRestoreAsync(this), Backup.CanUndo(library.DataDirectory));
        menu.Items.Add(new MenuFlyoutSeparator());
        Item(L("Zapisz wybraną pieśń jako .txt"), () => ImportExport.ExportSongAsync(this), library.SelectedSong is not null);
        Item(L("Eksportuj raport CCLI (CSV)..."), () => ImportExport.ExportCcliAsync(this), library.CcliUsage.Count > 0);
        importExport.Flyout = menu;
        bar.Children.Add(importExport);

        bar.Children.Add(ToolButton("🌐", L("Online"), async (_, _) => await Dialogs.OnlineSearchAsync(this), L("Wyszukiwanie pieśni religijnych w internecie")));
        bar.Children.Add(ToolButton("🎸", L("Muzycy"), (_, _) => OpenMusicians(), L("Ekran dla muzyków")));
        bar.Children.Add(ToolButton("⚙", L("Ustawienia"), async (_, _) => await Dialogs.SettingsAsync(this)));
        bar.Children.Add(ToolButton("?", L("O programie"), async (_, _) => await Dialogs.AboutAsync(this)));
        return new ScrollViewer { Content = bar, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
    }

    private UIElement IssuesBar()
    {
        var panel = new StackPanel();
        foreach (var issue in library.Issues)
        {
            var (title, message) = issue.Kind switch
            {
                PersistenceIssueKind.Unreadable => (L("Nie można odczytać pliku {0}", issue.FileName),
                    L("Plik jest uszkodzony albo ma nieznany format. Aplikacja go nie nadpisze: zmiany w tej części danych nie będą zapisywane do czasu przywrócenia kopii lub ponownego uruchomienia.\n\n{0}Szczegóły: {1}",
                        issue.QuarantinedCopy is null ? "" : L("Kopia pliku: {0}.\n\n", Path.GetFileName(issue.QuarantinedCopy)), issue.Detail)),
                PersistenceIssueKind.SaveFailed => (L("Nie można zapisać pliku {0}", issue.FileName), L("Ostatnie zmiany mogą nie zostać zachowane.\n\nSzczegóły: {0}", issue.Detail)),
                _ => (L("Dane z nowszej wersji aplikacji"),
                    L("Bibliotekę zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Pieśni i plany można wyświetlać, ale zmiany nie będą zapisywane, żeby nie uszkodzić danych. Zaktualizuj aplikację.", issue.FileName, AppSettings.SchemaVersionCurrent)),
            };
            panel.Children.Add(new InfoBar { Title = title, Message = message, Severity = InfoBarSeverity.Error, IsOpen = true });
        }
        return panel;
    }

    private UIElement ShortcutsBar()
    {
        var s = library.Settings.Shortcuts;
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14, Padding = new Thickness(14, 8, 14, 8) };
        bar.Children.Add(new TextBlock { Text = L("SKRÓTY:"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Opacity = 0.7 });
        void Item(string key, string label)
        {
            var item = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            item.Children.Add(new Border
            {
                Child = new TextBlock { Text = key, FontFamily = new FontFamily("Consolas"), FontSize = 12 },
                Padding = new Thickness(6, 1, 6, 1), CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(1),
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            });
            item.Children.Add(new TextBlock { Text = L(label), VerticalAlignment = VerticalAlignment.Center, Opacity = 0.8 });
            bar.Children.Add(item);
        }
        Item(KeyboardRouter.KeyName(s.PrevSlideKey), "Poprzedni");
        Item(KeyboardRouter.KeyName(s.NextSlideKey), "Następny");
        Item("R", "Refren");
        Item("1–9", "Zwrotka");
        Item(KeyboardRouter.KeyName(s.BlackScreenKey), "Czarny");
        Item(KeyboardRouter.KeyName(s.ClearTextKey), "Czysty");
        Item(KeyboardRouter.KeyName(s.PrevSongKey), "Poprz. pieśń");
        Item(KeyboardRouter.KeyName(s.NextSongKey), "Nast. pieśń");
        Item(KeyboardRouter.KeyName(s.StartPresentationKey), "Prezentuj");
        Item("Ctrl T", "Szybki tekst");
        return new ScrollViewer { Content = bar, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
    }

    // MARK: - Left panel

    private static readonly DataTemplate SongTemplate = (DataTemplate)XamlReader.Load("""
        <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
          <Grid Padding="2,6,2,6" ColumnSpacing="8">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock Text="{Binding Title}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
            <TextBlock Grid.Column="1" Text="{Binding Info}" Opacity="0.6" FontSize="12"/>
            <TextBlock Grid.Row="1" Grid.ColumnSpan="2" Text="{Binding Subtitle}" Opacity="0.65" FontSize="12" TextTrimming="CharacterEllipsis"/>
            <TextBlock Grid.Row="2" Grid.ColumnSpan="2" Text="{Binding Snippet}" Visibility="{Binding SnippetVisibility}" FontStyle="Italic" Opacity="0.7" FontSize="12" TextTrimming="CharacterEllipsis"/>
          </Grid>
        </DataTemplate>
        """);

    private void RenderLeft()
    {
        leftPanel.Children.Clear();
        leftPanel.RowDefinitions.Clear();
        leftPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        leftPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        leftPanel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        leftPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var tabs = new Grid { Margin = new Thickness(10, 10, 10, 6), ColumnSpacing = 6 };
        tabs.ColumnDefinitions.Add(new ColumnDefinition());
        tabs.ColumnDefinitions.Add(new ColumnDefinition());
        var libraryTab = new ToggleButton { Content = L("Biblioteka pieśni"), IsChecked = !showingPlan, HorizontalAlignment = HorizontalAlignment.Stretch };
        var planTab = new ToggleButton { Content = L("Plan nabożeństwa"), IsChecked = showingPlan, HorizontalAlignment = HorizontalAlignment.Stretch };
        libraryTab.Click += (_, _) => { showingPlan = false; RenderLeft(); };
        planTab.Click += (_, _) => { showingPlan = true; RenderLeft(); };
        Grid.SetColumn(planTab, 1);
        tabs.Children.Add(libraryTab);
        tabs.Children.Add(planTab);
        leftPanel.Children.Add(tabs);
        if (showingPlan) RenderPlan(); else RenderLibrary();
    }

    private void RenderLibrary()
    {
        var header = new StackPanel { Spacing = 6, Margin = new Thickness(10, 0, 10, 6) };
        searchBox = new TextBox { PlaceholderText = L("Szukaj w tytule, autorze i tekście..."), Text = query };
        searchBox.TextChanged += (_, _) => { query = searchBox.Text; RenderSongList(); };
        var scopeBox = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (value, label) in new[] { (SearchScope.All, "Wszędzie"), (SearchScope.TitleAndAuthor, "Tytuł i autor"), (SearchScope.TitleOnly, "Tylko tytuł"), (SearchScope.AuthorOnly, "Tylko autor") })
        {
            scopeBox.Items.Add(new ComboBoxItem { Content = L(label), Tag = value });
            if (value == scope) scopeBox.SelectedIndex = scopeBox.Items.Count - 1;
        }
        scopeBox.SelectionChanged += (_, _) => { scope = (SearchScope)((ComboBoxItem)scopeBox.SelectedItem).Tag; RenderSongList(); };
        header.Children.Add(searchBox);
        header.Children.Add(scopeBox);
        Grid.SetRow(header, 1);
        leftPanel.Children.Add(header);

        songList = new ListView { ItemTemplate = SongTemplate, SelectionMode = ListViewSelectionMode.Single, IsItemClickEnabled = false };
        songList.SelectionChanged += (_, _) =>
        {
            if (songList.SelectedItem is SongRow row && row.Id != library.SelectedSongId) library.SelectSong(row.Id);
        };
        songList.DoubleTapped += async (_, _) => { if (library.SelectedSong is Song song && song != library.TemporarySong) await EditSongAsync(song); };
        Grid.SetRow(songList, 2);
        leftPanel.Children.Add(songList);
        var footer = new TextBlock { Margin = new Thickness(12, 6, 12, 8), Opacity = 0.65, FontSize = 12 };
        Grid.SetRow(footer, 3);
        leftPanel.Children.Add(footer);
        RenderSongList();
        footer.Text = $"{library.Songs.Count} " + L("pieśni w bibliotece") + " · " + L("Podwójny klik: edycja");
    }

    private void RenderSongList()
    {
        if (songList is null || showingPlan) return;
        var songs = library.FilteredSongs(query, scope);
        var rows = songs.Select(s => new SongRow
        {
            Id = s.Id,
            Title = s.Title.Length > 0 ? s.Title : L("Bez tytułu"),
            Subtitle = s.Author.Length > 0 ? s.Author : L("Autor nieznany"),
            Info = (s.Key.Length > 0 ? s.Key + " · " : "") + L("{0} sl.", s.Slides.Count),
            Snippet = query.Length > 0 && SongSearch.MatchingSnippet(s.Title, s.RawLyrics, query) is string snippet ? $"„{snippet}”" : "",
        }).ToList();
        songList.ItemsSource = rows;
        var selected = rows.FindIndex(r => r.Id == library.SelectedSongId);
        if (selected >= 0)
        {
            songList.SelectedIndex = selected;
            songList.ScrollIntoView(rows[selected]);
        }
    }

    private void RenderPlan()
    {
        var plan = library.ActivePlan;
        var head = new Grid { Margin = new Thickness(10, 0, 10, 6), ColumnSpacing = 6 };
        head.ColumnDefinitions.Add(new ColumnDefinition());
        for (var i = 0; i < 3; i++) head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var picker = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var p in library.Plans)
        {
            picker.Items.Add(new ComboBoxItem { Content = p.Name, Tag = p.Id });
            if (p.Id == plan?.Id) picker.SelectedIndex = picker.Items.Count - 1;
        }
        picker.SelectionChanged += (_, _) => { if (picker.SelectedItem is ComboBoxItem item) library.SetActivePlan((string)item.Tag); };
        head.Children.Add(picker);
        Button Small(string text, string tip, int column, Func<Task> action, bool enabled = true)
        {
            var b = new Button { Content = text, IsEnabled = enabled };
            ToolTipService.SetToolTip(b, tip);
            b.Click += async (_, _) => await action();
            Grid.SetColumn(b, column);
            head.Children.Add(b);
            return b;
        }
        Small("＋", L("Nowy plan"), 1, async () => { if (await Dialogs.PromptAsync(this, L("Nazwa planu"), L("Nowy plan")) is string name && name.Trim().Length > 0) library.CreatePlan(name.Trim()); });
        Small("✎", L("Zmień nazwę"), 2, async () => { if (plan is not null && await Dialogs.PromptAsync(this, L("Nazwa planu"), plan.Name) is string name) library.RenamePlan(plan.Id, name); }, plan is not null);
        Small("🗑", L("Usuń plan"), 3, async () => { if (plan is not null && await Dialogs.ConfirmAsync(this, L("Usunąć plan „{0}”?", plan.Name))) library.DeletePlan(plan.Id); }, plan is not null);
        Grid.SetRow(head, 1);
        leftPanel.Children.Add(head);

        var list = new StackPanel { Spacing = 4, Padding = new Thickness(10, 0, 10, 10) };
        if (plan is null) list.Children.Add(new TextBlock { Text = L("Utwórz plan przyciskiem +."), Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
        else if (plan.Items.Count == 0) list.Children.Add(new TextBlock { Text = L("Plan jest pusty. Wybierz pieśń w bibliotece i kliknij „Dodaj do planu”."), Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
        else
        {
            var current = library.CurrentPlanIndex(plan);
            for (var index = 0; index < plan.Items.Count; index++)
            {
                var item = plan.Items[index];
                var song = library.SongById(item.SongId);
                var row = new Grid { ColumnSpacing = 4, Padding = new Thickness(6), CornerRadius = new CornerRadius(6) };
                if (library.IsLive && current == index) row.Background = (Brush)Application.Current.Resources["AccentFillColorSecondaryBrush"];
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition());
                for (var i = 0; i < 4; i++) row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Children.Add(new TextBlock { Text = $"{index + 1}.", Opacity = 0.6, VerticalAlignment = VerticalAlignment.Center });
                var title = new TextBlock { Text = song?.Title ?? L("(usunięta pieśń)"), TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(title, 1);
                row.Children.Add(title);
                var position = index;
                void Action(string text, string tip, int column, Action action, bool enabled = true)
                {
                    var b = new Button { Content = text, IsEnabled = enabled, Padding = new Thickness(8, 2, 8, 2) };
                    ToolTipService.SetToolTip(b, tip);
                    b.Click += (_, _) => action();
                    Grid.SetColumn(b, column);
                    row.Children.Add(b);
                }
                Action("▶", L("Prezentuj"), 2, () => { if (song is not null) library.Present(song); }, song is not null);
                Action("↑", "↑", 3, () => library.MovePlanItem(position, position - 1), index > 0);
                Action("↓", "↓", 4, () => library.MovePlanItem(position, position + 1), index < plan.Items.Count - 1);
                Action("✕", L("Usuń z planu"), 5, () => library.RemovePlanItem(item.Id));
                row.Tapped += (_, _) => { if (song is not null) library.SelectSong(song.Id); };
                row.DoubleTapped += (_, _) => { if (song is not null) library.Present(song); };
                list.Children.Add(row);
            }
        }
        var scroll = new ScrollViewer { Content = list };
        Grid.SetRow(scroll, 2);
        leftPanel.Children.Add(scroll);
        var footer = new TextBlock { Margin = new Thickness(12, 6, 12, 8), Opacity = 0.65, FontSize = 12, Text = plan is null ? "" : L("{0} pieśni w planie", plan.Items.Count) };
        Grid.SetRow(footer, 3);
        leftPanel.Children.Add(footer);
    }

    // MARK: - Middle panel

    private void RenderMiddle()
    {
        middlePanel.Children.Clear();
        middlePanel.RowDefinitions.Clear();
        var song = library.SelectedSong;
        if (song is null)
        {
            middlePanel.Children.Add(new TextBlock { Text = "♫\n" + L("Wybierz pieśń z biblioteki"), TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = 0.6, FontSize = 18 });
            return;
        }
        middlePanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        middlePanel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var isTemporary = song == library.TemporarySong;

        // Tytuł nad przyciskami, przyciski zawijają się: przy wąskim panelu nic nie jest ucinane z lewej (jak poprawka w macOS).
        var head = new StackPanel { Spacing = 8, Padding = new Thickness(16, 12, 16, 12) };
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        titleRow.Children.Add(new TextBlock { Text = song.Title, FontSize = 22, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap, MaxLines = 2 });
        if (song.Key.Length > 0) titleRow.Children.Add(new Border { Child = new TextBlock { Text = song.Key, FontWeight = FontWeights.Bold }, Padding = new Thickness(6, 2, 6, 2), CornerRadius = new CornerRadius(4), VerticalAlignment = VerticalAlignment.Center, Background = (Brush)Application.Current.Resources["AccentFillColorTertiaryBrush"] });
        head.Children.Add(titleRow);
        head.Children.Add(new TextBlock { Text = song.Author.Length > 0 ? song.Author : L("Autor nieznany"), Opacity = 0.65, TextTrimming = TextTrimming.CharacterEllipsis });
        var buttons = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemHeight = 40 };
        void HeadButton(string text, RoutedEventHandler click, bool enabled = true, bool accent = false)
        {
            var b = new Button { Content = text, IsEnabled = enabled, Margin = new Thickness(0, 0, 6, 6) };
            if (accent) b.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
            b.Click += click;
            buttons.Children.Add(b);
        }
        HeadButton("▶ " + L("Prezentuj"), (_, _) => library.Present(song), accent: true);
        HeadButton("＋ " + L("Plan"), (_, _) => library.AddSongToPlan(song.Id), !isTemporary && library.ActivePlan is not null);
        HeadButton("🎸 " + (song.Chords is null ? L("Chwyty") : L("Chwyty (✓)")), (_, _) => { showChords = !showChords; chordsTranspose = 0; RenderMiddle(); });
        HeadButton("✎ " + L("Edytuj"), async (_, _) => await EditSongAsync(song), !isTemporary);
        head.Children.Add(buttons);
        if (song.Tags.Count > 0) head.Children.Add(new TextBlock { Text = string.Join(" · ", song.Tags), Opacity = 0.6, FontSize = 12, TextWrapping = TextWrapping.Wrap });
        if (song.Copyright is not null || song.CcliNumber is not null)
            head.Children.Add(new TextBlock { Text = string.Join(" · ", new[] { song.Copyright, song.CcliNumber is null ? null : $"CCLI {song.CcliNumber}" }.OfType<string>()), Opacity = 0.6, FontSize = 12, TextWrapping = TextWrapping.Wrap });
        middlePanel.Children.Add(head);

        var body = new StackPanel { Spacing = 10, Padding = new Thickness(16, 4, 16, 16) };
        if (showChords)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var down = new Button { Content = "−1" };
            down.Click += (_, _) => { chordsTranspose--; RenderMiddle(); };
            var up = new Button { Content = "+1" };
            up.Click += (_, _) => { chordsTranspose++; RenderMiddle(); };
            row.Children.Add(down);
            row.Children.Add(new TextBlock { Text = L("Transpozycja: {0}", chordsTranspose > 0 ? $"+{chordsTranspose}" : chordsTranspose.ToString()), VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(up);
            body.Children.Add(row);
            body.Children.Add(song.Chords is null
                ? new TextBlock { Text = L("Ta pieśń nie ma chwytów. Dodaj je w edytorze."), Opacity = 0.7 }
                : new TextBlock { Text = ChordTransposer.Transpose(song.Chords, chordsTranspose), FontFamily = new FontFamily("Consolas"), IsTextSelectionEnabled = true });
        }
        else
        {
            var isActive = library.IsLive && library.ActiveSong?.Id == song.Id;
            var verse = 0;
            for (var index = 0; index < song.Slides.Count; index++)
            {
                var slide = song.Slides[index];
                var hint = slide.Type == SlideTypes.Verse ? $"[{slide.Number ?? ++verse}]" : slide.Type == SlideTypes.Chorus ? "[R]" : "";
                var card = new Button { HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(12) };
                if (isActive && library.ActiveSlideIndex == index)
                {
                    card.BorderBrush = new SolidColorBrush(ColorHelper.FromArgb(255, 0xE5, 0x48, 0x4D));
                    card.BorderThickness = new Thickness(2);
                }
                var content = new StackPanel { Spacing = 6 };
                var cardHead = new Grid();
                cardHead.ColumnDefinitions.Add(new ColumnDefinition());
                cardHead.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                cardHead.Children.Add(new TextBlock { Text = $"{SlideTypes.ShortBadge.GetValueOrDefault(slide.Type, "•")}  {Labels.Slide(slide)}", FontWeight = FontWeights.SemiBold });
                var hintText = new TextBlock { Text = hint, Opacity = 0.5, FontFamily = new FontFamily("Consolas") };
                Grid.SetColumn(hintText, 1);
                cardHead.Children.Add(hintText);
                content.Children.Add(cardHead);
                content.Children.Add(new TextBlock { Text = slide.Text, TextWrapping = TextWrapping.Wrap });
                card.Content = content;
                var position = index;
                card.Click += (_, _) =>
                {
                    if (library.IsLive && library.ActiveSong?.Id == song.Id) library.JumpToSlide(position);
                    else library.Present(song, position);
                };
                body.Children.Add(card);
            }
        }
        var scroll = new ScrollViewer { Content = body };
        Grid.SetRow(scroll, 1);
        middlePanel.Children.Add(scroll);
    }

    // MARK: - Right panel

    private Size TargetSize()
    {
        if (presentation.IsOpen) return presentation.TargetSize;
        var screen = Screens.Target();
        return screen is null ? new Size(1920, 1080) : new Size(screen.Bounds.Width, screen.Bounds.Height);
    }

    private void RenderRight()
    {
        rightPanel.Children.Clear();
        var target = TargetSize();
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition());
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(new TextBlock { Text = "🖥  " + L("Ekran na żywo"), FontWeight = FontWeights.SemiBold });
        var pill = new Border
        {
            Child = new TextBlock { Text = library.IsLive ? L("NA ŻYWO") : L("OFF AIR"), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(library.IsLive ? Colors.White : Colors.Gray) },
            Padding = new Thickness(8, 2, 8, 2), CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(library.IsLive ? ColorHelper.FromArgb(255, 0xE5, 0x48, 0x4D) : ColorHelper.FromArgb(40, 128, 128, 128)),
        };
        Grid.SetColumn(pill, 1);
        head.Children.Add(pill);
        rightPanel.Children.Add(head);

        var width = 370.0;
        livePreview.Width = width;
        livePreview.Height = width * target.Height / target.Width;
        livePreview.Render(ScreenState.FromLibrary(), target);
        rightPanel.Children.Add(new Border { Child = livePreview, BorderThickness = new Thickness(2), CornerRadius = new CornerRadius(6), BorderBrush = new SolidColorBrush(library.IsLive ? ColorHelper.FromArgb(255, 0xE5, 0x48, 0x4D) : Colors.Gray) });

        var controls = new Grid { ColumnSpacing = 8, RowSpacing = 8 };
        controls.ColumnDefinitions.Add(new ColumnDefinition());
        controls.ColumnDefinitions.Add(new ColumnDefinition());
        for (var i = 0; i < 4; i++) controls.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        void Control(string text, int row, int column, Action action, bool enabled = true, int span = 1, bool on = false, bool accent = false)
        {
            var b = new Button { Content = text, IsEnabled = enabled, HorizontalAlignment = HorizontalAlignment.Stretch };
            if (accent || on) b.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
            b.Click += (_, _) => action();
            Grid.SetRow(b, row);
            Grid.SetColumn(b, column);
            Grid.SetColumnSpan(b, span);
            controls.Children.Add(b);
        }
        Control("← " + L("Poprzedni"), 0, 0, library.PrevSlide, library.IsLive);
        Control(L("Następny") + " →", 0, 1, library.NextSlide, library.IsLive);
        Control(L("Czarny (B)"), 1, 0, library.ToggleBlackScreen, library.IsLive, on: library.IsBlackScreen);
        Control(L("Czysty (C)"), 1, 1, library.ToggleClearText, library.IsLive, on: library.IsClearText);
        if (library.IsLive) Control("■ " + L("Zakończ projekcję"), 2, 0, library.StopLive, span: 2);
        else Control("▶ " + (library.ActiveSong is null ? L("Rozpocznij projekcję") : L("Wznów projekcję")), 2, 0, library.StartOrResume, library.ActiveSong is not null || library.SelectedSong is not null, span: 2, accent: true);
        Control(presentation.IsOpen ? L("Zamknij okno projekcji") : L("Otwórz okno projekcji"), 3, 0, ToggleProjection, span: 2, accent: !presentation.IsOpen);
        rightPanel.Children.Add(controls);

        var screens = Screens.All();
        var screenBox = new ComboBox { Header = L("Ekran projekcji"), HorizontalAlignment = HorizontalAlignment.Stretch };
        screenBox.Items.Add(new ComboBoxItem { Content = L("Automatycznie (drugi ekran)"), Tag = "" });
        foreach (var screen in screens) screenBox.Items.Add(new ComboBoxItem { Content = screen.Label, Tag = screen.Id });
        screenBox.SelectedIndex = Math.Max(0, screens.FindIndex(s => s.Id == library.Settings.WindowsScreenDevice) + 1);
        screenBox.SelectionChanged += (_, _) =>
        {
            if (screenBox.SelectedItem is not ComboBoxItem item) return;
            library.UpdateSettings(s => s.WindowsScreenDevice = (string)item.Tag);
            if (presentation.IsOpen) presentation.ShowOn(Screens.Target());
        };
        rightPanel.Children.Add(screenBox);

        var next = library.IsLive ? library.NextSlidePreview : null;
        var nextHead = new Grid { Margin = new Thickness(0, 8, 0, 0) };
        nextHead.ColumnDefinitions.Add(new ColumnDefinition());
        nextHead.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        nextHead.Children.Add(new TextBlock { Text = "⇥  " + L("Podgląd następnego slajdu"), FontWeight = FontWeights.SemiBold });
        var nextLabel = new TextBlock { Text = next is null ? L("KONIEC") : Labels.Slide(next), Opacity = 0.6, FontSize = 12 };
        Grid.SetColumn(nextLabel, 1);
        nextHead.Children.Add(nextLabel);
        rightPanel.Children.Add(nextHead);
        if (next is null)
        {
            rightPanel.Children.Add(new TextBlock { Text = library.IsLive ? L("Koniec planu") : L("Brak aktywnej prezentacji"), Opacity = 0.6, Margin = new Thickness(0, 10, 0, 0) });
        }
        else
        {
            nextPreview.Width = width;
            nextPreview.Height = width * target.Height / target.Width;
            nextPreview.Render(ScreenState.FromLibrary(dimmed: true, textOverride: next.Text), target);
            rightPanel.Children.Add(new Border { Child = nextPreview, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), BorderBrush = new SolidColorBrush(Colors.Gray), Opacity = 0.9 });
        }
    }

    public void ToggleProjection()
    {
        if (presentation.IsOpen) presentation.HideWindow();
        else presentation.ShowOn(Screens.Target());
        RenderRight();
    }

    public void OpenMusicians()
    {
        if (musicians is null)
        {
            musicians = new MusiciansWindow();
            musicians.Closed += (_, _) => musicians = null;
        }
        musicians.Activate();
    }

    public MusiciansWindow? Musicians => musicians;

    // MARK: - Updates

    private void OnLibraryChanged(string reason)
    {
        switch (reason)
        {
            case "live":
                RenderMiddle();
                RenderRight();
                if (showingPlan) RenderLeft();
                break;
            case "selection":
                RenderSongList();
                showChords = false;
                RenderMiddle();
                break;
            case "settings":
                if (Catalog.Language != library.Settings.AppLanguage)
                {
                    Catalog.Language = library.Settings.AppLanguage;
                    Title = L("CantatePresenter — Prezenter Pieśni & Słowa");
                    BuildUi();
                }
                else
                {
                    RenderRight();
                }
                break;
            default:
                BuildUi();
                break;
        }
    }

    // MARK: - Keyboard

    private KeyFocus FocusKind()
    {
        var element = FocusManager.GetFocusedElement(root.XamlRoot);
        return element switch
        {
            TextBox box => box.AcceptsReturn ? KeyFocus.MultilineText : KeyFocus.Text,
            ComboBox or PasswordBox => KeyFocus.MultilineText,
            ListView or ListViewItem => KeyFocus.List,
            _ => KeyFocus.Other,
        };
    }

    private static string Characters(VirtualKey key) => key switch
    {
        >= VirtualKey.Number0 and <= VirtualKey.Number9 => ((int)key - (int)VirtualKey.Number0).ToString(),
        >= VirtualKey.NumberPad0 and <= VirtualKey.NumberPad9 => ((int)key - (int)VirtualKey.NumberPad0).ToString(),
        >= VirtualKey.A and <= VirtualKey.Z => ((char)('a' + (key - VirtualKey.A))).ToString(),
        (VirtualKey)0xBB or VirtualKey.Add => "=",
        (VirtualKey)0xBD or VirtualKey.Subtract => "-",
        _ => "",
    };

    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (DialogOpen) return;
        if (HandleKey(e.Key, KeyContext.Main(FocusKind()))) e.Handled = true;
    }

    /// <summary>Wykonuje akcję skrótu; zwraca true, gdy klawisz został obsłużony.</summary>
    public bool HandleKey(VirtualKey key, KeyContext context)
    {
        if (DialogOpen) return false;
        var command = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
        var virtualKey = key >= VirtualKey.NumberPad0 && key <= VirtualKey.NumberPad9 ? VirtualKey.Number0 + (key - VirtualKey.NumberPad0) : key;
        var action = KeyboardRouter.Action(KeyboardRouter.MacCode((int)virtualKey), Characters(key), command, library.Settings.Shortcuts, context);
        if (action is null) return false;
        switch (action.Type)
        {
            case "nextSlide": library.NextSlide(); break;
            case "prevSlide": library.PrevSlide(); break;
            case "nextSong": library.NextSongInPlan(); break;
            case "prevSong": library.PrevSongInPlan(); break;
            case "blackScreen": library.ToggleBlackScreen(); break;
            case "clearText": library.ToggleClearText(); break;
            case "chorus": library.JumpToChorus(); break;
            case "verse": library.JumpToVerse(action.Number ?? 1); break;
            case "quickText": _ = QuickTextAsync(); break;
            case "zoomIn": library.UpdateSettings(s => s.UiScale += 0.05); break;
            case "zoomOut": library.UpdateSettings(s => s.UiScale -= 0.05); break;
            case "zoomReset": library.UpdateSettings(s => s.UiScale = 1); break;
            case "endTextEditing": songList?.Focus(FocusState.Programmatic); break;
            case "startPresentation": if (library.SelectedSong is Song song) library.Present(song); break;
            case "stopPresentation": library.StopLive(); break;
        }
        return true;
    }

    // MARK: - Dialogs

    private async Task QuickTextAsync()
    {
        if (await Dialogs.QuickTextAsync(this) is (string text, string title)) library.PresentQuickText(text, title);
    }

    private async Task EditSongAsync(Song? song) => await Dialogs.EditSongAsync(this, song);

    public void FocusSearch()
    {
        showingPlan = false;
        RenderLeft();
        searchBox?.Focus(FocusState.Programmatic);
    }
}
