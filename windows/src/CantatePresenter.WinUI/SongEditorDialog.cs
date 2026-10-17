using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Models;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Edytor pieśni (SongEditorView w macOS): metadane, zakładki „Tekst i Slajdy” (z podglądem slajdów na żywo
/// i wstawianiem sekcji) oraz „Chwyty gitarowe / Taby” (transpozycja, wbudowana baza chwytów).
/// </summary>
public static class SongEditorDialog
{
    private static TextBox Field(string text, string placeholder = "") => new() { Text = text, PlaceholderText = placeholder };

    private static StackPanel Labeled(string label, UIElement control, UIElement? accessory = null)
    {
        var panel = new StackPanel { Spacing = 3 };
        var title = new TextBlock { Text = label, FontWeight = FontWeights.SemiBold, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
        panel.Children.Add(accessory is null ? title : Ui.Columns(6, (title, -1), (accessory, 0)));
        panel.Children.Add(control);
        return panel;
    }

    private static string Normalize(string text) => text.Replace("\r\n", "\n").Replace("\r", "\n");

    public static async Task ShowAsync(MainWindow window, Song? song)
    {
        var library = Services.Library;
        var title = Field(song?.Title ?? "", L("Wpisz tytuł..."));
        var author = Field(song?.Author ?? "", L("np. Cesareo Gabarain"));
        var key = Field(song?.Key ?? "", L("np. D, G, Am"));
        var copyright = Field(song?.Copyright ?? "", L("np. © 2024 Wydawnictwo, domena publiczna"));
        var ccli = Field(song?.CcliNumber ?? "", "1234567");
        var tags = Field(string.Join(", ", song?.Tags ?? []), L("np. Uwielbienie, Oazowe, Młodzieżowe, ŚDM"));
        var mono = new FontFamily("Consolas");
        var lyrics = Ui.MultilineBox(song?.RawLyrics ?? "");
        lyrics.FontFamily = mono;
        lyrics.FontSize = 13;
        var chords = Ui.MultilineBox(song?.Chords ?? "", TextWrapping.NoWrap);
        chords.FontFamily = mono;
        chords.FontSize = 13;
        ScrollViewer.SetHorizontalScrollBarVisibility(chords, ScrollBarVisibility.Auto);

        // Metadane jak w macOS: tytuł, autor, tonacja / prawa, CCLI / tagi i przełącznik widoku.
        var row1 = Ui.Columns(12,
            (Labeled(L("Tytuł pieśni *"), title, Dictation.Button(title, DictationMode.Replace)), -1),
            (Labeled(L("Autor / Źródło"), author, Dictation.Button(author, DictationMode.Replace)), -1),
            (Labeled(L("Tonacja (Key)"), key), 100));
        var row2 = Ui.Columns(12, (Labeled(L("Prawa autorskie (©)"), copyright), -1), (Labeled(L("Numer CCLI"), ccli), 130));
        var lyricsTab = new ToggleButton { Content = L("Tekst i Slajdy"), IsChecked = true, MinWidth = 120, CornerRadius = new CornerRadius(4, 0, 0, 4) };
        var chordsTab = new ToggleButton { MinWidth = 150, CornerRadius = new CornerRadius(0, 4, 4, 0) };
        void ChordsTabTitle() => chordsTab.Content = L("Chwyty gitarowe / Taby") + (chords.Text.Trim().Length > 0 ? " (✓)" : "");
        ChordsTabTitle();
        var tabs = new StackPanel { Orientation = Orientation.Horizontal };
        tabs.Children.Add(lyricsTab);
        tabs.Children.Add(chordsTab);
        var viewLabel = new StackPanel { Spacing = 3 };
        viewLabel.Children.Add(new TextBlock { Text = L("Widok edytora"), FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = Ui.Secondary, HorizontalAlignment = HorizontalAlignment.Right });
        viewLabel.Children.Add(tabs);
        var row3 = Ui.Columns(12, (Labeled(L("Tagi / Kategorie (rozdzielone przecinkami)"), tags), -1), (viewLabel, 0));
        var meta = new StackPanel { Spacing = 10 };
        meta.Children.Add(row1);
        meta.Children.Add(row2);
        meta.Children.Add(row3);

        // Zakładka 1: tekst po lewej, slajdy po prawej.
        var lyricsHead = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        lyricsHead.Children.Add(new TextBlock { Text = L("Treść pieśni (dla rzutnika / zboru)"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        lyricsHead.Children.Add(Dictation.Button(lyrics, DictationMode.AppendNewline, L("Dyktuj tekst nowej zwrotki lub refrenu")));
        var lyricsHeader = Ui.Columns(8, (lyricsHead, -1), (new TextBlock { Text = L("Wskazówka: oddzielaj zwrotki pustą linią"), FontSize = 11, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center }, 0));
        var sections = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        sections.Children.Add(new TextBlock { Text = L("Wstaw sekcję:"), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
        // Znaczniki sekcji to dane (nie tłumaczone), jak w macOS.
        foreach (var (label, tag) in new[]
        {
            (L("+ [Zwrotka]"), "[Zwrotka]\n"), (L("+ [Refren]"), "[Refren]\n"), (L("+ [Bridge / Mostek]"), "[Bridge]\n"), ("+ [Pre-Chorus]", "[Pre-Chorus]\n"),
            (L("+ [Coda / Koda]"), "[Coda]\n"), (L("+ [Przejście / Solo]"), "[Przejście]\n"), (L("+ [Zakończenie]"), "[Zakończenie]\n"),
        })
        {
            var insert = new Button { Content = label, FontSize = 11, Padding = new Thickness(7, 2, 7, 3), MinHeight = 0 };
            insert.Click += (_, _) =>
            {
                var text = Normalize(lyrics.Text);
                lyrics.Text = text.Length == 0 ? tag : text.EndsWith("\n\n") ? text + tag : text.EndsWith('\n') ? text + "\n" + tag : text + "\n\n" + tag;
                lyrics.Focus(FocusState.Programmatic);
                lyrics.SelectionStart = lyrics.Text.Length;
            };
            sections.Children.Add(insert);
        }
        var lyricsColumn = new Grid { RowSpacing = 6 };
        lyricsColumn.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        lyricsColumn.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        lyricsColumn.RowDefinitions.Add(new RowDefinition());
        lyricsColumn.Children.Add(lyricsHeader);
        var sectionsScroll = new ScrollViewer { Content = sections, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollMode = ScrollMode.Enabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollMode = ScrollMode.Disabled };
        Grid.SetRow(sectionsScroll, 1);
        lyricsColumn.Children.Add(sectionsScroll);
        Grid.SetRow(lyrics, 2);
        lyricsColumn.Children.Add(lyrics);

        var slidesTitle = new TextBlock { FontWeight = FontWeights.SemiBold };
        var slides = new StackPanel { Spacing = 8 };
        void RenderSlides()
        {
            var parsed = Song.SlidesFromLyrics(Normalize(lyrics.Text));
            slidesTitle.Text = L("Podgląd wygenerowanych slajdów ({0})", parsed.Count);
            slides.Children.Clear();
            for (var i = 0; i < parsed.Count; i++)
            {
                var slide = parsed[i];
                var card = new StackPanel { Spacing = 4 };
                card.Children.Add(Ui.Columns(5, (Ui.SlideTypeBadge(slide.Type, 10), 0),
                    (new TextBlock { Text = Labels.Slide(slide), FontSize = 12, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center }, -1),
                    (new TextBlock { Text = L("Slajd {0}", i + 1), FontSize = 10, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center }, 0)));
                card.Children.Add(new TextBlock { Text = slide.Text, FontSize = 12, TextWrapping = TextWrapping.Wrap });
                slides.Children.Add(new Border
                {
                    Child = card, Padding = new Thickness(8), CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1),
                    BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"), Background = Ui.Resource("CardBackgroundFillColorDefaultBrush"),
                });
            }
        }
        RenderSlides();
        lyrics.TextChanged += (_, _) => RenderSlides();
        var slidesColumn = new Grid { RowSpacing = 6 };
        slidesColumn.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        slidesColumn.RowDefinitions.Add(new RowDefinition());
        slidesColumn.Children.Add(slidesTitle);
        var slidesScroll = new ScrollViewer { Content = slides, Padding = new Thickness(0, 0, 10, 0) };
        Grid.SetRow(slidesScroll, 1);
        slidesColumn.Children.Add(slidesScroll);
        var lyricsView = new Grid { ColumnSpacing = 16 };
        lyricsView.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.3, GridUnitType.Star) });
        lyricsView.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        lyricsView.Children.Add(lyricsColumn);
        Grid.SetColumn(slidesColumn, 1);
        lyricsView.Children.Add(slidesColumn);

        // Zakładka 2: chwyty z transpozycją i bazą chwytów.
        var chordsInfo = new StackPanel { Spacing = 2 };
        chordsInfo.Children.Add(new TextBlock { Text = L("Opracowanie akordów i tabulatur (dla muzyków)"), FontWeight = FontWeights.Bold });
        chordsInfo.Children.Add(Ui.Note(L("Chwyty są dostępne dla muzyków w aplikacji i nie wyświetlają się zborowi na ekranie projekcji.")));
        var down = new Button { Content = L("Transpozycja ♭ -1"), Padding = new Thickness(8, 3, 8, 4) };
        down.Click += (_, _) => chords.Text = ChordTransposer.Transpose(Normalize(chords.Text), -1);
        var up = new Button { Content = L("Transpozycja ♯ +1"), Padding = new Thickness(8, 3, 8, 4) };
        up.Click += (_, _) => chords.Text = ChordTransposer.Transpose(Normalize(chords.Text), 1);
        // Baza chwytów w wysuwanym panelu (okno w oknie dialogowym nie jest możliwe w WinUI).
        var catalogList = new ListView { SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = true, MaxHeight = 320, Width = 340 };
        var catalogEmpty = new TextBlock { Text = L("Nie znaleziono opracowań. Wpisz inny tytuł albo dodaj chwyty w edytorze pieśni."), TextWrapping = TextWrapping.Wrap, Foreground = Ui.Secondary, Width = 320 };
        var catalogPanel = new StackPanel { Spacing = 6 };
        catalogPanel.Children.Add(new TextBlock { Text = L("Biblioteka chwytów"), FontWeight = FontWeights.Bold });
        catalogPanel.Children.Add(catalogList);
        catalogPanel.Children.Add(catalogEmpty);
        var catalogFlyout = new Flyout { Content = catalogPanel };
        catalogFlyout.Opening += (_, _) =>
        {
            catalogList.Items.Clear();
            foreach (var result in ChordsCatalog.Search(title.Text.Trim().Length > 0 ? title.Text : L("Nowa pieśń")))
            {
                var item = new StackPanel { Spacing = 2, Padding = new Thickness(0, 4, 0, 4) };
                item.Children.Add(Ui.Columns(6, (new TextBlock { Text = result.Title, FontWeight = FontWeights.Bold }, -1), (Ui.Badge(result.Key, Ui.Orange, 10), 0)));
                item.Children.Add(new TextBlock { Text = result.Artist, FontSize = 11, Foreground = Ui.Secondary });
                catalogList.Items.Add(new ListViewItem { Content = item, Tag = result });
            }
            catalogEmpty.Visibility = catalogList.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        };
        catalogList.ItemClick += (_, e) =>
        {
            var chosen = (e.ClickedItem as ListViewItem)?.Tag as ChordsResult
                ?? catalogList.Items.OfType<ListViewItem>().FirstOrDefault(i => i.Content == e.ClickedItem)?.Tag as ChordsResult;
            if (chosen is null) return;
            chords.Text = chosen.ChordsSheet;
            if (chosen.Key.Length > 0 && key.Text.Trim().Length == 0) key.Text = chosen.Key;
            catalogFlyout.Hide();
        };
        var findChords = Ui.Button(Glyphs.Globe, L("Szukaj w bibliotece chwytów..."), (_, _) => { });
        Ui.Tint(findChords, Ui.Orange);
        findChords.Flyout = catalogFlyout;
        var chordsTools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        chordsTools.Children.Add(down);
        chordsTools.Children.Add(up);
        chordsTools.Children.Add(findChords);
        var chordsView = new Grid { RowSpacing = 8, Visibility = Visibility.Collapsed };
        chordsView.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        chordsView.RowDefinitions.Add(new RowDefinition());
        chordsView.Children.Add(Ui.Columns(12, (chordsInfo, -1), (chordsTools, 0)));
        Grid.SetRow(chords, 1);
        chordsView.Children.Add(chords);
        chords.TextChanged += (_, _) => ChordsTabTitle();

        void ShowTab(bool chordsVisible)
        {
            lyricsTab.IsChecked = !chordsVisible;
            chordsTab.IsChecked = chordsVisible;
            lyricsView.Visibility = chordsVisible ? Visibility.Collapsed : Visibility.Visible;
            chordsView.Visibility = chordsVisible ? Visibility.Visible : Visibility.Collapsed;
        }
        lyricsTab.Click += (_, _) => ShowTab(false);
        chordsTab.Click += (_, _) => ShowTab(true);

        var editorArea = new Grid { Height = 400 };
        editorArea.Children.Add(lyricsView);
        editorArea.Children.Add(chordsView);
        var panel = new StackPanel { Spacing = 14, Width = 960 };
        panel.Children.Add(meta);
        panel.Children.Add(Ui.Divider());
        panel.Children.Add(editorArea);

        var dialog = new ContentDialog
        {
            Title = song is null ? L("Nowa pieśń") : L("Edycja pieśni"),
            Content = panel,
            PrimaryButtonText = L("Zapisz"),
            CloseButtonText = L("Anuluj"),
            SecondaryButtonText = song is null ? "" : L("Usuń"),
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = title.Text.Trim().Length > 0,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 1040.0;
        dialog.Resources["ContentDialogMaxHeight"] = 900.0;
        title.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = title.Text.Trim().Length > 0;
        title.Loaded += (_, _) => { if (song is null) title.Focus(FocusState.Programmatic); };
        var result = await Dialogs.ShowAsync(window, dialog);
        if (result == ContentDialogResult.Secondary && song is not null)
        {
            if (await Dialogs.ConfirmAsync(window, L("Czy na pewno usunąć pieśń „{0}”?", song.Title))) library.DeleteSong(song.Id);
            return;
        }
        if (result != ContentDialogResult.Primary || title.Text.Trim().Length == 0) return;
        var target = song ?? Song.Create(title.Text.Trim());
        target.Title = title.Text.Trim();
        target.Author = author.Text.Trim();
        target.Key = key.Text.Trim();
        target.Tags = tags.Text.Split(',', ';').Select(t => t.Trim()).Where(t => t.Length > 0).ToList();
        target.RawLyrics = Normalize(lyrics.Text);
        target.Chords = chords.Text.Trim().Length > 0 ? Normalize(chords.Text) : null;
        target.Copyright = copyright.Text.Trim().Length > 0 ? copyright.Text.Trim() : null;
        target.CcliNumber = ccli.Text.Trim().Length > 0 ? ccli.Text.Trim() : null;
        if (song is null)
        {
            target.Slides = Song.SlidesFromLyrics(target.RawLyrics);
            library.SelectSong(library.AddSong(target).Id);
        }
        else
        {
            library.UpdateSong(target);
        }
    }
}
