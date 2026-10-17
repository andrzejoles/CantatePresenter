using System.Globalization;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Wiersz listy pieśni (wiązanie danych w szablonie listy).</summary>
[Bindable]
public sealed class SongRow
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Author { get; set; } = "";
    public string Key { get; set; } = "";
    public string Count { get; set; } = "";
    public string Snippet { get; set; } = "";
    public Visibility GuitarVisibility { get; set; } = Visibility.Collapsed;
    public Visibility LiveVisibility { get; set; } = Visibility.Collapsed;
    public Visibility KeyVisibility => Key.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility AuthorVisibility => Author.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility SnippetVisibility => Snippet.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
}

/// <summary>Lewy panel: biblioteka (SongListView w macOS) i plan nabożeństwa (PlanListView).</summary>
public sealed partial class MainWindow
{
    private ListView? songList;
    private TextBox? searchBox;
    private TextBlock? listCount;
    private TextBlock? libraryFooter;
    private string query = "";
    private SearchScope scope = SearchScope.All;
    private bool onlyWithChords;
    private bool showingPlan;
    private List<Song> visibleSongs = [];
    private string? listedLiveId;

    private static readonly (string Code, string Label, string Glyph)[] SortOrders =
    [
        ("titleAsc", "Tytuł (A-Z)", Glyphs.ChevronUp),
        ("titleDesc", "Tytuł (Z-A)", Glyphs.ChevronDown),
        ("authorAsc", "Autor (A-Z)", Glyphs.Person),
        ("newest", "Najnowsze", Glyphs.Clock),
    ];

    private static readonly (SearchScope Scope, string Label)[] Scopes =
    [
        (SearchScope.All, "Wszędzie"), (SearchScope.TitleAndAuthor, "Tytuł i autor"), (SearchScope.TitleOnly, "Tylko tytuł"), (SearchScope.AuthorOnly, "Tylko autor"),
    ];

    private static readonly DataTemplate SongTemplate = (DataTemplate)XamlReader.Load("""
        <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
          <StackPanel Padding="2,7,2,7" Spacing="3">
            <Grid ColumnSpacing="6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Ellipse Width="8" Height="8" Fill="#FFFF3B30" VerticalAlignment="Center" Visibility="{Binding LiveVisibility}"/>
              <TextBlock Grid.Column="1" Text="{Binding Title}" FontWeight="SemiBold" FontSize="14" TextTrimming="CharacterEllipsis" MaxLines="1"/>
              <TextBlock Grid.Column="2" Text="🎸" FontSize="11" VerticalAlignment="Center" Visibility="{Binding GuitarVisibility}"/>
              <Border Grid.Column="3" Background="#260A84FF" CornerRadius="4" Padding="5,1,5,2" VerticalAlignment="Center" Visibility="{Binding KeyVisibility}">
                <TextBlock Text="{Binding Key}" FontSize="11" FontWeight="Bold" Foreground="#FF0A84FF"/>
              </Border>
              <TextBlock Grid.Column="4" Text="{Binding Count}" FontSize="11" Opacity="0.6" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock Text="{Binding Author}" FontSize="12" Opacity="0.65" TextTrimming="CharacterEllipsis" MaxLines="1" Visibility="{Binding AuthorVisibility}"/>
            <StackPanel Orientation="Horizontal" Spacing="4" Visibility="{Binding SnippetVisibility}">
              <TextBlock Text="❝" FontSize="10" Foreground="#FFFF9500" VerticalAlignment="Center"/>
              <TextBlock Text="{Binding Snippet}" FontSize="11" FontStyle="Italic" Foreground="#FFFF9500" TextTrimming="CharacterEllipsis" MaxLines="1"/>
            </StackPanel>
          </StackPanel>
        </DataTemplate>
        """);

    private void RenderLeft()
    {
        leftPanel.Children.Clear();
        leftPanel.RowDefinitions.Clear();
        for (var i = 0; i < 5; i++) leftPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        leftPanel.RowDefinitions[3].Height = new GridLength(1, GridUnitType.Star);

        // Przełącznik zakładek jak segmentowany Picker w macOS.
        var tabs = new Grid { ColumnSpacing = 2, Padding = new Thickness(2), CornerRadius = new CornerRadius(7), Background = Ui.Resource("ControlFillColorSecondaryBrush") };
        tabs.ColumnDefinitions.Add(new ColumnDefinition());
        tabs.ColumnDefinitions.Add(new ColumnDefinition());
        Button Tab(string text, bool selected, int column, Action select)
        {
            var b = new Button { Content = text, HorizontalAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(6, 4, 6, 5), BorderThickness = new Thickness(selected ? 1 : 0), AllowFocusOnInteraction = false };
            if (selected)
            {
                b.Background = Ui.Resource("ControlFillColorDefaultBrush");
                b.BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush");
            }
            else
            {
                b.Resources["ButtonBackground"] = Ui.Brush(Colors.Transparent);
                b.Background = Ui.Brush(Colors.Transparent);
            }
            b.Click += (_, _) => select();
            Grid.SetColumn(b, column);
            tabs.Children.Add(b);
            return b;
        }
        Tab(L("Biblioteka pieśni"), !showingPlan, 0, () => { if (showingPlan) { showingPlan = false; RenderLeft(); } });
        Tab(L("Plan nabożeństwa"), showingPlan, 1, () => { if (!showingPlan) { showingPlan = true; RenderLeft(); } });
        var tabsHost = new Border { Child = tabs, Padding = new Thickness(8), Background = Ui.Resource("SolidBackgroundFillColorBaseBrush") };
        leftPanel.Children.Add(tabsHost);
        if (showingPlan) RenderPlan(); else RenderLibrary();
    }

    private void RenderLibrary()
    {
        // Pole wyszukiwania: zielone, gdy aktywne (można pisać), czerwone, gdy klawisze sterują slajdami (jak w macOS).
        searchBox = new TextBox { PlaceholderText = SearchPlaceholder(), Text = query, BorderThickness = new Thickness(0), VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(4, 5, 4, 5) };
        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused" })
            searchBox.Resources[key] = Ui.Brush(Colors.Transparent);
        foreach (var key in new[] { "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused" })
            searchBox.Resources[key] = Ui.Brush(Colors.Transparent);
        var searchIcon = Ui.Icon(Glyphs.Search, 13);
        var clear = new Button { Content = Ui.Icon(Glyphs.Close, 10), Padding = new Thickness(5), MinWidth = 0, MinHeight = 0, Background = Ui.Brush(Colors.Transparent), BorderThickness = new Thickness(0), Visibility = query.Length > 0 ? Visibility.Visible : Visibility.Collapsed };
        ToolTipService.SetToolTip(clear, L("Wyczyść"));
        clear.Click += (_, _) => { searchBox.Text = ""; searchBox.Focus(FocusState.Programmatic); };
        var field = new Border
        {
            Child = Ui.Columns(6, (searchIcon, 0), (searchBox, -1), (clear, 0)),
            Padding = new Thickness(8, 0, 4, 0),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
        };
        void Paint(bool focused)
        {
            var color = focused ? Ui.Green : Ui.Red;
            field.BorderBrush = Ui.Brush(color, focused ? 0.75 : 0.4);
            field.BorderThickness = new Thickness(focused ? 1.5 : 1);
            field.Background = Ui.Brush(color, 0.07);
            searchIcon.Foreground = focused ? Ui.Brush(Ui.Green) : Ui.Secondary;
        }
        Paint(false);
        searchBox.GotFocus += (_, _) => { Paint(true); searchBox.SelectAll(); };
        searchBox.LostFocus += (_, _) => Paint(false);
        field.Tapped += (_, _) => searchBox.Focus(FocusState.Pointer);
        searchBox.TextChanged += (_, _) =>
        {
            query = searchBox.Text;
            clear.Visibility = query.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
            RenderSongList();
        };
        // Enter: pierwszy wynik i wyjście z pola, żeby klawisze znów sterowały slajdami.
        searchBox.KeyDown += (_, e) =>
        {
            if (e.Key != VirtualKey.Enter) return;
            e.Handled = true;
            if (visibleSongs.FirstOrDefault() is Song first) library.SelectSong(first.Id);
            songList?.Focus(FocusState.Programmatic);
        };

        var scopeBox = new ComboBox { MinWidth = 120 };
        foreach (var (value, label) in Scopes)
        {
            scopeBox.Items.Add(new ComboBoxItem { Content = L(label), Tag = value });
            if (value == scope) scopeBox.SelectedIndex = scopeBox.Items.Count - 1;
        }
        scopeBox.SelectionChanged += (_, _) =>
        {
            scope = (SearchScope)((ComboBoxItem)scopeBox.SelectedItem).Tag;
            if (searchBox is not null) searchBox.PlaceholderText = SearchPlaceholder();
            RenderSongList();
        };
        var chordsFilter = new ToggleButton { Content = GuitarLabel(L("Z chwytami")), IsChecked = onlyWithChords, Padding = new Thickness(8, 4, 8, 5), AllowFocusOnInteraction = false };
        chordsFilter.Resources["ToggleButtonBackgroundChecked"] = Ui.Brush(Ui.Orange);
        chordsFilter.Resources["ToggleButtonBackgroundCheckedPointerOver"] = Ui.Brush(Ui.Orange, 0.88);
        chordsFilter.Resources["ToggleButtonBackgroundCheckedPressed"] = Ui.Brush(Ui.Orange, 0.75);
        chordsFilter.Resources["ToggleButtonBorderBrushChecked"] = Ui.Brush(Ui.Orange);
        ToolTipService.SetToolTip(chordsFilter, L("Pokaż tylko pieśni z chwytami"));
        chordsFilter.Click += (_, _) => { onlyWithChords = chordsFilter.IsChecked == true; RenderSongList(); };
        var filters = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        filters.Children.Add(Dictation.Button(searchBox, DictationMode.Replace));
        filters.Children.Add(scopeBox);
        filters.Children.Add(chordsFilter);

        var header = new StackPanel { Spacing = 6, Padding = new Thickness(10, 2, 10, 10), Background = Ui.Resource("SolidBackgroundFillColorBaseBrush") };
        header.Children.Add(field);
        header.Children.Add(filters);
        Grid.SetRow(header, 1);
        leftPanel.Children.Add(header);

        // Licznik i sortowanie.
        listCount = new TextBlock { FontSize = 11.5, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center };
        var sortLabel = new TextBlock { Text = L(SortOrders.FirstOrDefault(o => o.Code == library.Settings.SongSortOrder).Label ?? "Tytuł (A-Z)"), FontSize = 11, Foreground = Ui.Secondary };
        var sortContent = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        sortContent.Children.Add(new FontIcon { Glyph = Glyphs.Sort, FontFamily = Ui.SymbolFont, FontSize = 10, Foreground = Ui.Secondary });
        sortContent.Children.Add(sortLabel);
        var sort = new DropDownButton { Content = sortContent, Padding = new Thickness(6, 2, 6, 2), Background = Ui.Brush(Colors.Transparent), BorderThickness = new Thickness(0), MinHeight = 0, AllowFocusOnInteraction = false };
        ToolTipService.SetToolTip(sort, L("Zmień kolejność sortowania pieśni w bibliotece"));
        var sortMenu = new MenuFlyout();
        foreach (var (code, label, glyph) in SortOrders)
        {
            var item = new RadioMenuFlyoutItem { Text = L(label), GroupName = "sort", IsChecked = code == library.Settings.SongSortOrder, Icon = new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont } };
            item.Click += (_, _) =>
            {
                library.Settings.SongSortOrder = code;
                library.SaveSettings();
                sortLabel.Text = L(label);
                RenderSongList();
            };
            sortMenu.Items.Add(item);
        }
        sort.Flyout = sortMenu;
        var meta = new Border
        {
            Child = Ui.Columns(6, (listCount, -1), (sort, 0)),
            Padding = new Thickness(10, 2, 6, 2),
            Background = Ui.Resource("SubtleFillColorSecondaryBrush"),
            BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(0, 1, 0, 1),
        };
        Grid.SetRow(meta, 2);
        leftPanel.Children.Add(meta);

        songList = new ListView { ItemTemplate = SongTemplate, SelectionMode = ListViewSelectionMode.Single, IsItemClickEnabled = false, Padding = new Thickness(0, 4, 0, 4) };
        songList.SelectionChanged += (_, _) =>
        {
            if (songList.SelectedItem is SongRow row && row.Id != library.SelectedSongId) library.SelectSong(row.Id);
        };
        songList.DoubleTapped += async (_, _) => { if (library.SelectedSong is Song song && song != library.TemporarySong) await EditSongAsync(song); };
        songList.RightTapped += (_, e) =>
        {
            if ((e.OriginalSource as FrameworkElement)?.DataContext is not SongRow row || library.SongById(row.Id) is not Song song) return;
            library.SelectSong(song.Id);
            SongContextMenu(song).ShowAt(songList, e.GetPosition(songList));
            e.Handled = true;
        };
        Grid.SetRow(songList, 3);
        leftPanel.Children.Add(songList);

        libraryFooter = new TextBlock { FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center };
        var footer = new Border
        {
            Child = Ui.Columns(8, (libraryFooter, -1), (new TextBlock { Text = Lw("Podwójny klik / ⌘E: edycja"), FontSize = 11, Foreground = Ui.Secondary, Opacity = 0.85 }, 0)),
            Padding = new Thickness(10, 6, 10, 7),
            BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Background = Ui.Resource("SolidBackgroundFillColorBaseBrush"),
        };
        Grid.SetRow(footer, 4);
        leftPanel.Children.Add(footer);
        RenderSongList();
    }

    private string SearchPlaceholder() => scope == SearchScope.All
        ? L("Szukaj w tytule, autorze i tekście...")
        : L("Szukaj ({0})...", L(Scopes.First(s => s.Scope == scope).Label).ToLower(CultureInfo.CurrentCulture));

    private MenuFlyout SongContextMenu(Song song)
    {
        var menu = new MenuFlyout();
        void Item(string glyph, string text, Func<Task> action)
        {
            var item = new MenuFlyoutItem { Text = text, Icon = new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont } };
            item.Click += async (_, _) => await action();
            menu.Items.Add(item);
        }
        Item(Glyphs.Play, L("Prezentuj teraz"), () => { library.Present(song); return Task.CompletedTask; });
        Item(Glyphs.AddTo, L("Dodaj do aktywnego planu"), () => { library.AddSongToPlan(song.Id); return Task.CompletedTask; });
        Item(Glyphs.Edit, Lw("Edytuj pieśń ✏️ (⌘E)"), () => EditSongAsync(song));
        menu.Items.Add(new MenuFlyoutSeparator());
        Item(Glyphs.Contact, L("Wyszukaj tytuł i autora online..."), () => AuthorTitleLookupDialog.ShowAsync(this, song));
        menu.Items.Add(new MenuFlyoutSeparator());
        Item(Glyphs.Document, L("Eksportuj jako plik tekstowy (.txt)..."), () => ImportExport.ExportSongAsync(this, song));
        Item(Glyphs.Document, L("Eksportuj jako plik JSON (.json)..."), () => ImportExport.ExportSongsJsonAsync(this, [song], song.Title));
        menu.Items.Add(new MenuFlyoutSeparator());
        var delete = new MenuFlyoutItem { Text = L("Usuń z bazy"), Icon = new FontIcon { Glyph = Glyphs.Delete, FontFamily = Ui.SymbolFont }, Foreground = Ui.Brush(Ui.Red) };
        delete.Click += async (_, _) =>
        {
            if (await Dialogs.ConfirmAsync(this, L("Czy na pewno usunąć pieśń „{0}”?", song.Title))) library.DeleteSong(song.Id);
        };
        menu.Items.Add(delete);
        return menu;
    }

    /// <summary>Kolejność listy jak SongSortOrder w macOS (porównanie po polsku, bez wielkości liter).</summary>
    private List<Song> Sorted(IEnumerable<Song> songs)
    {
        var compare = CultureInfo.GetCultureInfo("pl-PL").CompareInfo;
        int Text(string a, string b) => compare.Compare(a.Trim(), b.Trim(), CompareOptions.IgnoreCase);
        var list = songs.ToList();
        switch (library.Settings.SongSortOrder)
        {
            case "titleDesc":
                list.Sort((a, b) => Text(b.Title, a.Title));
                break;
            case "authorAsc":
                list.Sort((a, b) =>
                {
                    var authorA = a.Author.Trim();
                    var authorB = b.Author.Trim();
                    if (authorA.Length == 0 && authorB.Length > 0) return 1;
                    if (authorA.Length > 0 && authorB.Length == 0) return -1;
                    var result = Text(authorA, authorB);
                    return result != 0 ? result : Text(a.Title, b.Title);
                });
                break;
            case "newest":
                list.Sort((a, b) => string.CompareOrdinal(b.CreatedAt, a.CreatedAt));
                break;
            default:
                list.Sort((a, b) => Text(a.Title, b.Title));
                break;
        }
        return list;
    }

    private void RenderSongList()
    {
        if (songList is null || showingPlan) return;
        var trimmed = query.Trim();
        IEnumerable<Song> songs = trimmed.Length == 0 ? library.Songs : library.FilteredSongs(trimmed, scope);
        if (onlyWithChords) songs = songs.Where(s => s.HasChords);
        visibleSongs = Sorted(songs);
        var liveId = library.IsLive ? library.ActiveSong?.Id : null;
        listedLiveId = liveId;
        var rows = visibleSongs.Select(s => new SongRow
        {
            Id = s.Id,
            Title = s.Title.Length > 0 ? s.Title : L("Bez tytułu"),
            Author = s.Author.Trim(),
            Key = s.Key.Trim(),
            Count = L("{0} sl.", s.Slides.Count),
            Snippet = trimmed.Length > 0 && SongSearch.MatchingSnippet(s.Title, s.RawLyrics, trimmed) is string snippet ? snippet : "",
            GuitarVisibility = s.HasChords ? Visibility.Visible : Visibility.Collapsed,
            LiveVisibility = s.Id == liveId ? Visibility.Visible : Visibility.Collapsed,
        }).ToList();
        songList.ItemsSource = rows;
        var selected = rows.FindIndex(r => r.Id == library.SelectedSongId);
        if (selected >= 0)
        {
            songList.SelectedIndex = selected;
            songList.ScrollIntoView(rows[selected]);
        }
        if (listCount is not null)
            listCount.Text = trimmed.Length == 0 && !onlyWithChords ? L("{0} pieśni", rows.Count) : L("{0} z {1} pieśni", rows.Count, library.Songs.Count);
        if (libraryFooter is not null) libraryFooter.Text = $"{rows.Count} {L("pieśni w bibliotece")}";
    }

    // MARK: - Plan

    private void RenderPlan()
    {
        var plan = library.ActivePlan;
        var items = plan?.Items ?? [];
        var head = new StackPanel { Spacing = 8, Padding = new Thickness(10, 2, 10, 10), Background = Ui.Resource("SolidBackgroundFillColorBaseBrush") };
        var picker = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch, PlaceholderText = L("Plan:") };
        foreach (var p in library.Plans)
        {
            picker.Items.Add(new ComboBoxItem { Content = p.Name, Tag = p.Id });
            if (p.Id == plan?.Id) picker.SelectedIndex = picker.Items.Count - 1;
        }
        picker.SelectionChanged += (_, _) => { if (picker.SelectedItem is ComboBoxItem item) library.SetActivePlan((string)item.Tag); };
        Button Small(string glyph, string tip, Func<Task> action)
        {
            var b = new Button { Content = Ui.Icon(glyph, 13), Padding = new Thickness(8, 5, 8, 6) };
            ToolTipService.SetToolTip(b, tip);
            Ui.AutomationName(b, tip);
            b.Click += async (_, _) => await action();
            return b;
        }
        var add = Small(Glyphs.Add, L("Utwórz nowy plan"), async () =>
        {
            var suggested = L("Plan {0}", DateTime.Now.ToString("d MMM yyyy", CultureInfo.CurrentCulture));
            if (await Dialogs.PromptAsync(this, L("Utwórz nowy plan nabożeństwa"), suggested, L("Nazwa planu (np. Niedziela 10:00)"), L("Utwórz")) is string name && name.Trim().Length > 0)
                library.CreatePlan(name.Trim());
        });
        var cells = new List<(UIElement, double)> { (picker, -1), (add, 0) };
        if (plan is not null)
        {
            cells.Add((Small(Glyphs.Rename, L("Zmień nazwę"), async () =>
            {
                if (await Dialogs.PromptAsync(this, L("Nazwa planu"), plan.Name) is string name && name.Trim().Length > 0) library.RenamePlan(plan.Id, name.Trim());
            }), 0));
        }
        if (library.Plans.Count > 1 && plan is not null)
        {
            cells.Add((Small(Glyphs.Delete, L("Usuń ten plan"), async () =>
            {
                if (await Dialogs.ConfirmAsync(this, L("Usunąć plan „{0}”?", plan.Name))) library.DeletePlan(plan.Id);
            }), 0));
        }
        head.Children.Add(Ui.Columns(6, cells.ToArray()));
        var countText = new TextBlock { Text = L("{0} pieśni w planie", items.Count), FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center };
        if (items.Count > 0)
        {
            var run = Ui.Button(Glyphs.Play, L("Uruchom plan"), (_, _) =>
            {
                if (items.Select(i => library.SongById(i.SongId)).FirstOrDefault(s => s is not null) is Song first)
                {
                    library.Present(first);
                    library.SelectSong(first.Id);
                }
            }, accent: true);
            run.FontSize = 12;
            run.Padding = new Thickness(8, 3, 8, 4);
            head.Children.Add(Ui.Columns(6, (countText, -1), (run, 0)));
        }
        else
        {
            head.Children.Add(countText);
        }
        Grid.SetRow(head, 1);
        leftPanel.Children.Add(head);
        var divider = Ui.Divider();
        Grid.SetRow(divider, 2);
        leftPanel.Children.Add(divider);

        if (items.Count == 0)
        {
            var empty = new StackPanel { Spacing = 12, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(20) };
            empty.Children.Add(new FontIcon { Glyph = Glyphs.Checklist, FontFamily = Ui.SymbolFont, FontSize = 36, Foreground = Ui.Secondary, Opacity = 0.5 });
            empty.Children.Add(new TextBlock { Text = plan is null ? L("Utwórz plan przyciskiem +.") : L("Plan nabożeństwa jest pusty"), FontSize = 14, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            if (plan is not null)
                empty.Children.Add(new TextBlock { Text = L("Kliknij prawym przyciskiem myszy na pieśń w bibliotece lub kliknij przycisk '+ Do planu', aby dodać pieśni."), FontSize = 12, Foreground = Ui.Secondary, Opacity = 0.85, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            Grid.SetRow(empty, 3);
            leftPanel.Children.Add(empty);
            return;
        }

        var list = new StackPanel { Spacing = 2, Padding = new Thickness(8, 6, 8, 10) };
        var current = plan is null ? null : library.CurrentPlanIndex(plan);
        for (var index = 0; index < items.Count; index++)
        {
            var item = items[index];
            var song = library.SongById(item.SongId);
            var isLive = library.IsLive && song is not null && library.ActiveSong?.Id == song.Id && current == index;
            var isSelected = song is not null && library.SelectedSongId == song.Id;
            var row = new Grid { ColumnSpacing = 8, Padding = new Thickness(6, 6, 4, 6), CornerRadius = new CornerRadius(6) };
            row.Background = isSelected ? Ui.Resource("SubtleFillColorSecondaryBrush") : Ui.Brush(Colors.Transparent);
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            // Numer w kółku: czerwony, gdy pieśń jest na ekranie.
            var number = new Grid { Width = 22, Height = 22, VerticalAlignment = VerticalAlignment.Center };
            number.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse { Fill = isLive ? Ui.Brush(Ui.Red) : Ui.Brush(Ui.Gray, 0.22) });
            number.Children.Add(new TextBlock { Text = (index + 1).ToString(CultureInfo.InvariantCulture), FontSize = 10, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Foreground = isLive ? Ui.Brush(Colors.White) : Ui.Resource("TextFillColorPrimaryBrush") });
            row.Children.Add(number);

            var details = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
            var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            titleRow.Children.Add(new TextBlock { Text = song?.Title ?? L("Nieznana pieśń"), FontSize = 13, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, MaxLines = 1 });
            if (song is not null && song.Key.Trim().Length > 0) titleRow.Children.Add(Ui.Badge(song.Key.Trim(), Ui.Blue, 10));
            details.Children.Add(titleRow);
            if (item.Note.Trim().Length > 0)
                details.Children.Add(new TextBlock { Text = item.Note, FontSize = 11, FontStyle = Windows.UI.Text.FontStyle.Italic, Foreground = Ui.Brush(Ui.Orange), TextTrimming = TextTrimming.CharacterEllipsis, MaxLines = 1 });
            Grid.SetColumn(details, 1);
            row.Children.Add(details);

            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 0, VerticalAlignment = VerticalAlignment.Center };
            var position = index;
            void Action(string glyph, string tip, Action action, bool enabled = true, Color? color = null, double size = 11)
            {
                var b = new Button
                {
                    Content = Ui.Icon(glyph, size, color), IsEnabled = enabled, Padding = new Thickness(5), MinWidth = 0, MinHeight = 0,
                    Background = Ui.Brush(Colors.Transparent), BorderThickness = new Thickness(0), AllowFocusOnInteraction = false,
                };
                b.Resources["ButtonBackgroundDisabled"] = Ui.Brush(Colors.Transparent);
                ToolTipService.SetToolTip(b, tip);
                Ui.AutomationName(b, tip);
                b.Click += (_, _) => action();
                actions.Children.Add(b);
            }
            Action(Glyphs.Play, L("Prezentuj teraz"), () => { if (song is not null) { library.Present(song); library.SelectSong(song.Id); } }, song is not null, Ui.Green, 13);
            Action(Glyphs.ChevronUp, L("Przesuń wyżej"), () => library.MovePlanItem(position, position - 1), index > 0);
            Action(Glyphs.ChevronDown, L("Przesuń niżej"), () => library.MovePlanItem(position, position + 1), index < items.Count - 1);
            Action(Glyphs.Close, L("Usuń z planu"), () => library.RemovePlanItem(item.Id));
            Grid.SetColumn(actions, 2);
            row.Children.Add(actions);
            row.Tapped += (_, _) => { if (song is not null) library.SelectSong(song.Id); };
            row.DoubleTapped += (_, _) => { if (song is not null) { library.Present(song); library.SelectSong(song.Id); } };
            row.PointerEntered += (_, _) => { if (!isSelected) row.Background = Ui.Resource("SubtleFillColorTertiaryBrush"); };
            row.PointerExited += (_, _) => { if (!isSelected) row.Background = Ui.Brush(Colors.Transparent); };
            list.Children.Add(row);
        }
        var scroll = new ScrollViewer { Content = list };
        Grid.SetRow(scroll, 3);
        leftPanel.Children.Add(scroll);
    }
}
