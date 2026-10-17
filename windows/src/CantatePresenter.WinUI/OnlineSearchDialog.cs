using CantatePresenter.Core.Models;
using CantatePresenter.Core.Online;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Wyszukiwanie pieśni w internecie (OnlineSearchSheet w macOS): Wikiźródła (domena publiczna i wolne licencje),
/// podgląd slajdów, poprawa tytułu i autora przed importem, odnośnik do CCLI SongSelect.
/// </summary>
public static class OnlineSearchDialog
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private static string LicenseLabel(string code) => code == "publicDomain" ? L("Domena publiczna") : code == "ccBySA" ? "CC BY-SA" : L("Licencja: zobacz stronę źródła");

    public static async Task ShowAsync(MainWindow window)
    {
        var library = Services.Library;
        ContentDialog? dialog = null;
        var query = new TextBox { PlaceholderText = L("Wpisz tytuł lub słowa pieśni (np. Kiedy ranne wstają zorze)..."), VerticalAlignment = VerticalAlignment.Center };
        var language = new ComboBox { MinWidth = 150, VerticalAlignment = VerticalAlignment.Center };
        foreach (var (code, name, flag) in SettingsDialog.SearchLanguages)
        {
            language.Items.Add(new ComboBoxItem { Content = $"{flag}  {name}", Tag = code });
            if (code == library.Settings.OnlineSearchLanguage) language.SelectedIndex = language.Items.Count - 1;
        }
        if (language.SelectedIndex < 0) language.SelectedIndex = 0;
        var search = new Button { Content = L("Szukaj"), Style = (Style)Application.Current.Resources["AccentButtonStyle"], MinWidth = 70 };
        var songSelect = Ui.Button(Glyphs.NewWindow, L("Szukaj w SongSelect"), async (_, _) =>
            await Windows.System.Launcher.LaunchUriAsync(new Uri(Core.Import.SongSelectImporter.SearchUrl(query.Text.Trim()))),
            L("Otwiera wyszukiwanie CCLI SongSelect w przeglądarce. Pobrany plik (.txt lub ChordPro) zaimportujesz przez Import/Eksport."));
        var languageLabel = new TextBlock { Text = L("Język:"), VerticalAlignment = VerticalAlignment.Center };
        var searchBar = Ui.Columns(8, (Ui.Icon(Glyphs.Globe, 15, Ui.Blue), 0), (query, -1), (Dictation.Button(query, DictationMode.Replace), 0), (languageLabel, 0), (language, 0), (search, 0), (songSelect, 0));

        // Wyniki i podgląd.
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single, Width = 320 };
        var editedTitle = new TextBox { PlaceholderText = L("Tytuł pieśni"), FontWeight = FontWeights.SemiBold };
        var editedAuthor = new TextBox { PlaceholderText = L("Autor / Wykonawca") };
        var importAuthor = new CheckBox { Content = L("Importuj proponowanego autora:"), MinWidth = 0 };
        var unknown = new Border { Padding = new Thickness(6, 3, 6, 3), CornerRadius = new CornerRadius(4), Background = Ui.Brush(Ui.Orange, 0.12) };
        var unknownRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        unknownRow.Children.Add(Ui.Icon(Glyphs.Person, 12, Ui.Orange));
        unknownRow.Children.Add(new TextBlock { Text = L("Zostanie zapisany jako:"), FontSize = 12, Foreground = Ui.Secondary });
        unknownRow.Children.Add(new TextBlock { Text = L("\"Nieznany\""), FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Orange) });
        unknown.Child = unknownRow;
        var authorValue = new Grid();
        authorValue.Children.Add(editedAuthor);
        authorValue.Children.Add(unknown);
        void AuthorMode()
        {
            editedAuthor.Visibility = importAuthor.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            unknown.Visibility = importAuthor.IsChecked == true ? Visibility.Collapsed : Visibility.Visible;
        }
        importAuthor.Click += (_, _) => AuthorMode();
        WikisourceResult? selected = null;
        var importButton = Ui.Button(Glyphs.Download, L("Importuj do programu"), (_, _) =>
        {
            if (selected is null) return;
            var title = editedTitle.Text.Trim().Length > 0 ? editedTitle.Text.Trim() : selected.Title;
            var author = importAuthor.IsChecked == true && editedAuthor.Text.Trim().Length > 0 ? editedAuthor.Text.Trim() : L("Nieznany");
            var song = Song.Create(title, author, tags: [L("Wikiźródła")], rawLyrics: selected.Lyrics);
            song.Source = selected.Url;
            song.Copyright = LicenseLabel(selected.License);
            library.SelectSong(library.AddSong(song).Id);
            dialog?.Hide();
        }, accent: true);
        var review = new StackPanel { Spacing = 8 };
        review.Children.Add(Ui.Columns(8, (new TextBlock { Text = L("Tytuł:"), FontWeight = FontWeights.Bold, FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center }, 50), (editedTitle, -1), (importButton, 0)));
        review.Children.Add(Ui.Columns(8, (new TextBlock { Text = L("Autor:"), FontWeight = FontWeights.Bold, FontSize = 12, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center }, 50), (importAuthor, 0), (authorValue, -1)));
        var license = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        var licenseText = new TextBlock { FontSize = 12, Foreground = Ui.Brush(Ui.Green) };
        license.Children.Add(Ui.Icon(Glyphs.Checkmark, 12, Ui.Green));
        license.Children.Add(licenseText);
        var snippet = new TextBlock { FontSize = 12, Foreground = Ui.Secondary, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        var source = new HyperlinkButton { Content = Ui.Label(Glyphs.NewWindow, L("Otwórz źródło"), 12) };
        var slides = new StackPanel { Spacing = 8 };
        var preview = new StackPanel { Spacing = 10 };
        preview.Children.Add(new Border { Child = review, Padding = new Thickness(10), CornerRadius = new CornerRadius(8), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });
        preview.Children.Add(Ui.Columns(8, (license, 0), (snippet, -1), (source, 0)));
        preview.Children.Add(Ui.Divider());
        var slidesScroll = new ScrollViewer { Content = slides, Height = 270, Padding = new Thickness(0, 0, 10, 0) };
        preview.Children.Add(slidesScroll);
        var choose = new TextBlock { Text = L("Wybierz pieśń z listy, aby zobaczyć podgląd"), Foreground = Ui.Secondary, Margin = new Thickness(14) };
        var right = new Grid { Padding = new Thickness(14) };
        right.Children.Add(preview);
        right.Children.Add(choose);
        var split = new Grid { Height = 420 };
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        split.ColumnDefinitions.Add(new ColumnDefinition());
        split.Children.Add(list);
        var divider = Ui.Divider(vertical: true);
        divider.VerticalAlignment = VerticalAlignment.Stretch;
        Grid.SetColumn(divider, 1);
        split.Children.Add(divider);
        Grid.SetColumn(right, 2);
        split.Children.Add(right);
        static StackPanel Centered(string? glyph, string text)
        {
            var panel = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            panel.Children.Add(glyph is null ? new ProgressRing { IsActive = true, Width = 28, Height = 28 } : new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont, FontSize = 44, Foreground = Ui.Secondary, Opacity = 0.3 });
            panel.Children.Add(new TextBlock { Text = text, FontSize = 14, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center });
            return panel;
        }
        var state = new ContentControl { Height = 420, HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
        var area = new Grid();
        area.Children.Add(split);
        area.Children.Add(state);
        void ShowState(string? glyph, string? text)
        {
            state.Content = text is null ? null : Centered(glyph, text);
            state.Visibility = text is null ? Visibility.Collapsed : Visibility.Visible;
            split.Visibility = text is null ? Visibility.Visible : Visibility.Collapsed;
        }
        ShowState(Glyphs.Search, L("Wpisz tytuł lub fragment tekstu i kliknij 'Szukaj'"));

        void Select(WikisourceResult? result)
        {
            selected = result;
            preview.Visibility = result is null ? Visibility.Collapsed : Visibility.Visible;
            choose.Visibility = result is null ? Visibility.Visible : Visibility.Collapsed;
            if (result is null) return;
            editedTitle.Text = result.Title;
            editedAuthor.Text = result.Author;
            importAuthor.IsChecked = result.Author.Length > 0;
            AuthorMode();
            licenseText.Text = LicenseLabel(result.License);
            snippet.Text = result.Page;
            source.NavigateUri = Uri.TryCreate(result.Url, UriKind.Absolute, out var url) ? url : null;
            slides.Children.Clear();
            foreach (var slide in Song.SlidesFromLyrics(result.Lyrics))
            {
                var card = new StackPanel { Spacing = 3 };
                card.Children.Add(new TextBlock { Text = Labels.Slide(slide), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Orange) });
                card.Children.Add(new TextBlock { Text = slide.Text, FontSize = 13, TextWrapping = TextWrapping.Wrap });
                slides.Children.Add(new Border { Child = card, Padding = new Thickness(8), CornerRadius = new CornerRadius(6), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });
            }
            slidesScroll.ChangeView(null, 0, null, true);
        }
        list.SelectionChanged += (_, _) => Select((list.SelectedItem as ListViewItem)?.Tag as WikisourceResult);

        async Task Run()
        {
            var text = query.Text.Trim();
            if (text.Length == 0) return;
            var code = (language.SelectedItem as ComboBoxItem)?.Tag as string ?? "pl";
            if (code != library.Settings.OnlineSearchLanguage) library.UpdateSettings(x => x.OnlineSearchLanguage = code);
            search.IsEnabled = false;
            ShowState(null, L("Przeszukiwanie Wikiźródeł..."));
            List<WikisourceResult> found;
            try
            {
                found = await Wikisource.SearchAsync(Http, text, code, Services.Version);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
            {
                ShowState(Glyphs.Warning, L("Błąd połączenia: {0}", error.Message));
                search.IsEnabled = true;
                return;
            }
            search.IsEnabled = true;
            list.Items.Clear();
            if (found.Count == 0)
            {
                ShowState(Glyphs.Search, L("Nie znaleziono pieśni dla podanej frazy"));
                return;
            }
            foreach (var result in found)
            {
                var item = new StackPanel { Spacing = 3, Padding = new Thickness(0, 4, 0, 4) };
                item.Children.Add(Ui.Columns(6, (new TextBlock { Text = result.Title, FontWeight = FontWeights.SemiBold, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis }, -1), (Ui.Badge(L("Wikiźródła"), Ui.Blue, 9), 0)));
                if (result.Author.Length > 0) item.Children.Add(new TextBlock { Text = result.Author, FontSize = 12, Foreground = Ui.Secondary });
                var firstLines = string.Join(" / ", result.Lyrics.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).Take(2));
                if (firstLines.Length > 0) item.Children.Add(new TextBlock { Text = firstLines, FontSize = 11, Foreground = Ui.Secondary, Opacity = 0.8, MaxLines = 2, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis });
                list.Items.Add(new ListViewItem { Content = item, Tag = result });
            }
            ShowState(null, null);
            list.SelectedIndex = 0;
        }
        search.Click += async (_, _) => await Run();
        query.KeyDown += async (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) { e.Handled = true; await Run(); } };

        var body = new StackPanel { Spacing = 10, Width = 920 };
        body.Children.Add(searchBar);
        body.Children.Add(Ui.Note(L("Źródło: Wikiźródła. Tradycyjne pieśni w domenie publicznej lub na wolnej licencji; adres strony zostaje zapisany w pieśni.")));
        body.Children.Add(new Border { Child = area, BorderThickness = new Thickness(1), BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"), CornerRadius = new CornerRadius(8) });
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        titleRow.Children.Add(Ui.Icon(Glyphs.Globe, 20, Ui.Blue));
        titleRow.Children.Add(new TextBlock { Text = L("Wyszukiwanie pieśni religijnych w internecie"), FontSize = 18, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        dialog = new ContentDialog { Title = titleRow, Content = body, CloseButtonText = L("Zamknij") };
        dialog.Resources["ContentDialogMaxWidth"] = 1000.0;
        query.Loaded += (_, _) => query.Focus(FocusState.Programmatic);
        await Dialogs.ShowAsync(window, dialog);
    }
}
