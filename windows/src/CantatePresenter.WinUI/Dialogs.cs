using CantatePresenter.Core.Models;
using CantatePresenter.Core.Online;
using CantatePresenter.Core.Text;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

public static class Labels
{
    /// <summary>Etykieta slajdu w języku interfejsu: domyślne („Zwrotka 2”) tłumaczone, własne bez zmian.</summary>
    public static string Slide(SongSlide slide)
    {
        var baseName = SlideTypes.PolishName.GetValueOrDefault(slide.Type, slide.Label);
        if (slide.Label == baseName) return L(baseName);
        if (slide.Number is int number && slide.Label == $"{baseName} {number}") return $"{L(baseName)} {number}";
        return slide.Label;
    }
}

/// <summary>Okna dialogowe (ContentDialog). Gdy któreś jest otwarte, skróty prezentacji nie działają (jak arkusze w macOS).</summary>
public static class Dialogs
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    public static async Task<ContentDialogResult> ShowAsync(MainWindow window, ContentDialog dialog)
    {
        dialog.XamlRoot = window.Content.XamlRoot;
        dialog.RequestedTheme = ((FrameworkElement)window.Content).ActualTheme;
        window.DialogOpen = true;
        try
        {
            return await dialog.ShowAsync();
        }
        finally
        {
            window.DialogOpen = false;
        }
    }

    private static TextBox Field(string text, string placeholder = "", bool multiline = false, double height = 0)
    {
        var box = new TextBox { Text = text, PlaceholderText = placeholder, AcceptsReturn = multiline, TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap };
        if (height > 0) box.Height = height;
        if (multiline) ScrollViewer.SetVerticalScrollBarVisibility(box, ScrollBarVisibility.Auto);
        return box;
    }

    private static StackPanel Labeled(string label, UIElement control)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.SemiBold, FontSize = 12 });
        panel.Children.Add(control);
        return panel;
    }

    public static async Task<string?> PromptAsync(MainWindow window, string title, string value)
    {
        var box = Field(value);
        var dialog = new ContentDialog { Title = title, Content = box, PrimaryButtonText = L("OK"), CloseButtonText = L("Anuluj"), DefaultButton = ContentDialogButton.Primary };
        return await ShowAsync(window, dialog) == ContentDialogResult.Primary ? box.Text : null;
    }

    public static async Task<bool> ConfirmAsync(MainWindow window, string message)
    {
        var dialog = new ContentDialog { Title = message, PrimaryButtonText = L("OK"), CloseButtonText = L("Anuluj"), DefaultButton = ContentDialogButton.Close };
        return await ShowAsync(window, dialog) == ContentDialogResult.Primary;
    }

    public static async Task InfoAsync(MainWindow window, string title, string message)
    {
        var dialog = new ContentDialog { Title = title, Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap }, CloseButtonText = L("Zamknij") };
        await ShowAsync(window, dialog);
    }

    public static async Task<(string Text, string Title)?> QuickTextAsync(MainWindow window)
    {
        var title = Field("", L("Szybki tekst"));
        var text = Field("", L("Wpisz tekst ogłoszenia lub modlitwy. Pusta linia oddziela slajdy."), multiline: true, height: 200);
        var panel = new StackPanel { Spacing = 10, MinWidth = 480 };
        panel.Children.Add(Labeled(L("Tytuł (opcjonalnie)"), Dictation.WithMic(title, DictationMode.Replace)));
        panel.Children.Add(Labeled(L("Tekst"), Dictation.WithMic(text, DictationMode.AppendNewline)));
        panel.Children.Add(new TextBlock { Text = L("Tekst nie trafia do biblioteki."), Opacity = 0.65, FontSize = 12 });
        var dialog = new ContentDialog { Title = L("Szybki tekst"), Content = panel, PrimaryButtonText = L("Pokaż na ekranie"), CloseButtonText = L("Anuluj"), DefaultButton = ContentDialogButton.Primary };
        text.Loaded += (_, _) => text.Focus(FocusState.Programmatic);
        return await ShowAsync(window, dialog) == ContentDialogResult.Primary && text.Text.Trim().Length > 0 ? (text.Text, title.Text) : null;
    }

    public static async Task EditSongAsync(MainWindow window, Song? song)
    {
        var library = Services.Library;
        var title = Field(song?.Title ?? "", L("Wpisz tytuł..."));
        var author = Field(song?.Author ?? "");
        var key = Field(song?.Key ?? "", L("np. D, G, Am"));
        var tags = Field(string.Join(", ", song?.Tags ?? []));
        var copyright = Field(song?.Copyright ?? "", L("np. © 2024 Wydawnictwo, domena publiczna"));
        var ccli = Field(song?.CcliNumber ?? "", "1234567");
        var lyrics = Field(song?.RawLyrics ?? "", multiline: true, height: 260);
        var chords = Field(song?.Chords ?? "", multiline: true, height: 140);
        chords.FontFamily = new FontFamily("Consolas");
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        var authorField = Labeled(L("Autor / Źródło"), Dictation.WithMic(author, DictationMode.Replace));
        var keyField = Labeled(L("Tonacja (Key)"), key);
        Grid.SetColumn(authorField, 1);
        Grid.SetColumn(keyField, 2);
        row.Children.Add(Labeled(L("Tytuł pieśni *"), Dictation.WithMic(title, DictationMode.Replace)));
        row.Children.Add(authorField);
        row.Children.Add(keyField);
        var rights = new Grid { ColumnSpacing = 10 };
        rights.ColumnDefinitions.Add(new ColumnDefinition());
        rights.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        var ccliField = Labeled(L("Numer CCLI"), ccli);
        Grid.SetColumn(ccliField, 1);
        rights.Children.Add(Labeled(L("Prawa autorskie (©)"), copyright));
        rights.Children.Add(ccliField);
        var panel = new StackPanel { Spacing = 10, MinWidth = 640 };
        panel.Children.Add(row);
        panel.Children.Add(rights);
        panel.Children.Add(Labeled(L("Tagi / Kategorie (rozdzielone przecinkami)"), tags));
        panel.Children.Add(Labeled(L("Tekst pieśni (pusta linia oddziela slajdy; nagłówki np. [Refren], [Zwrotka 2])"), Dictation.WithMic(lyrics, DictationMode.AppendNewline)));
        panel.Children.Add(Labeled(L("Chwyty"), chords));
        var dialog = new ContentDialog
        {
            Title = song is null ? L("Nowa pieśń") : L("Edycja pieśni"),
            Content = new ScrollViewer { Content = panel, MaxHeight = 640 },
            PrimaryButtonText = L("Zapisz"),
            CloseButtonText = L("Anuluj"),
            SecondaryButtonText = song is null ? "" : L("Usuń"),
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.PrimaryButtonClick += (_, e) => { if (title.Text.Trim().Length == 0) { e.Cancel = true; title.Focus(FocusState.Programmatic); } };
        var result = await ShowAsync(window, dialog);
        if (result == ContentDialogResult.Secondary && song is not null)
        {
            if (await ConfirmAsync(window, L("Czy na pewno usunąć pieśń „{0}”?", song.Title))) library.DeleteSong(song.Id);
            return;
        }
        if (result != ContentDialogResult.Primary) return;
        var target = song ?? Song.Create(title.Text.Trim());
        target.Title = title.Text.Trim();
        target.Author = author.Text.Trim();
        target.Key = key.Text.Trim();
        target.Tags = tags.Text.Split(',', ';').Select(t => t.Trim()).Where(t => t.Length > 0).ToList();
        target.RawLyrics = lyrics.Text.Replace("\r\n", "\n").Replace("\r", "\n");
        target.Chords = chords.Text.Trim().Length > 0 ? chords.Text.Replace("\r\n", "\n").Replace("\r", "\n") : null;
        target.Copyright = copyright.Text.Trim().Length > 0 ? copyright.Text.Trim() : null;
        target.CcliNumber = ccli.Text.Trim().Length > 0 ? ccli.Text.Trim() : null;
        if (song is null)
        {
            target.Slides = Song.SlidesFromLyrics(target.RawLyrics);
            library.AddSong(target);
        }
        else
        {
            library.UpdateSong(target);
        }
    }

    public static async Task SettingsAsync(MainWindow window)
    {
        var library = Services.Library;
        var s = library.Settings;
        var panel = new StackPanel { Spacing = 14, MinWidth = 620 };

        var language = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (code, name) in Core.Localization.Catalog.Languages)
        {
            language.Items.Add(new ComboBoxItem { Content = name, Tag = code });
            if (code == s.AppLanguage) language.SelectedIndex = language.Items.Count - 1;
        }
        panel.Children.Add(Labeled(L("Język interfejsu"), language));

        // Skala interfejsu jak suwak w macOS (0,8–1,5); Ctrl +/− i A−/A+ na pasku pozwalają wyjść poza ten zakres.
        var initialScale = Math.Clamp(s.UiScale, 0.8, 1.5);
        var uiScale = new Slider { Minimum = 0.8, Maximum = 1.5, StepFrequency = 0.05, Value = initialScale };
        var uiScaleLabel = new TextBlock { Text = L("Skala interfejsu: {0}%", Math.Round(s.UiScale * 100)), FontWeight = FontWeights.SemiBold, FontSize = 12 };
        uiScale.ValueChanged += (_, e) => uiScaleLabel.Text = L("Skala interfejsu: {0}%", Math.Round(e.NewValue * 100));
        panel.Children.Add(uiScaleLabel);
        panel.Children.Add(uiScale);

        panel.Children.Add(new TextBlock { Text = L("Języki i dyktowanie głosowe"), FontWeight = FontWeights.Bold });
        var dictationLanguage = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (code, name, flag) in Dictation.Languages)
        {
            dictationLanguage.Items.Add(new ComboBoxItem { Content = $"{flag}  {name}", Tag = code });
            if (code == s.DictationLanguage) dictationLanguage.SelectedIndex = dictationLanguage.Items.Count - 1;
        }
        panel.Children.Add(Labeled(L("Język dyktowania głosem:"), dictationLanguage));
        var dictationOnDevice = new CheckBox { Content = L("Rozpoznawaj mowę tylko na tym urządzeniu"), IsChecked = s.DictationOnDeviceOnly };
        panel.Children.Add(dictationOnDevice);
        panel.Children.Add(new TextBlock { Text = L("Windows rozpoznaje dyktowany tekst w usłudze online firmy Microsoft (Ustawienia systemu Windows → Prywatność i zabezpieczenia → Mowa). Przy opcji „tylko na tym urządzeniu” dyktowanie jest wyłączone."), TextWrapping = TextWrapping.Wrap, Opacity = 0.65, FontSize = 12 });

        string[] fonts = ["Segoe UI", "Arial", "Calibri", "Helvetica Neue", "Georgia", "Times New Roman", "Verdana", "Trebuchet MS", "Cambria", "Bahnschrift"];
        var font = new ComboBox { IsEditable = true, HorizontalAlignment = HorizontalAlignment.Stretch, Text = s.FontFamily };
        foreach (var f in fonts) font.Items.Add(f);
        font.SelectedItem = fonts.Contains(s.FontFamily) ? s.FontFamily : null;
        ComboBox Choice((string Value, string Label)[] options, string current)
        {
            var box = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            foreach (var (value, label) in options)
            {
                box.Items.Add(new ComboBoxItem { Content = label, Tag = value });
                if (value == current) box.SelectedIndex = box.Items.Count - 1;
            }
            return box;
        }
        var horizontal = Choice([("left", L("Do lewej")), ("center", L("Do środka")), ("right", L("Do prawej"))], s.TextAlignment);
        var vertical = Choice([("top", L("Góra")), ("center", L("Środek")), ("bottom", L("Dół"))], s.VerticalAlignment);
        var typography = new Grid { ColumnSpacing = 10 };
        for (var i = 0; i < 3; i++) typography.ColumnDefinitions.Add(new ColumnDefinition());
        var h = Labeled(L("Wyrównanie poziome"), horizontal);
        var v = Labeled(L("Wyrównanie pionowe"), vertical);
        Grid.SetColumn(h, 1);
        Grid.SetColumn(v, 2);
        typography.Children.Add(Labeled(L("Czcionka"), font));
        typography.Children.Add(h);
        typography.Children.Add(v);
        panel.Children.Add(new TextBlock { Text = L("Typografia ekranu prezentacji"), FontWeight = FontWeights.Bold });
        panel.Children.Add(typography);
        var bold = new CheckBox { Content = L("Pogrubienie"), IsChecked = s.IsBold };
        var shadow = new CheckBox { Content = L("Cień tekstu"), IsChecked = s.HasShadow };
        var checks = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20 };
        checks.Children.Add(bold);
        checks.Children.Add(shadow);
        panel.Children.Add(checks);

        var textColor = Field(s.TextColorHex, "#FFFFFF");
        var backgroundColor = Field(s.BackgroundColorHex, "#000000");
        var colors = new Grid { ColumnSpacing = 10 };
        colors.ColumnDefinitions.Add(new ColumnDefinition());
        colors.ColumnDefinitions.Add(new ColumnDefinition());
        var bg = Labeled(L("Kolor tła"), backgroundColor);
        Grid.SetColumn(bg, 1);
        colors.Children.Add(Labeled(L("Kolor tekstu"), textColor));
        colors.Children.Add(bg);
        panel.Children.Add(new TextBlock { Text = L("Kolory ekranu"), FontWeight = FontWeights.Bold });
        panel.Children.Add(colors);

        var margin = new Slider { Minimum = 3, Maximum = 18, Value = Math.Round(s.MarginPercent * 100), StepFrequency = 1 };
        var spacing = new Slider { Minimum = 1, Maximum = 1.5, Value = s.LineSpacingFactor, StepFrequency = 0.05 };
        panel.Children.Add(new TextBlock { Text = L("Marginesy i interlinia"), FontWeight = FontWeights.Bold });
        var marginLabel = new TextBlock { Text = L("Margines ekranu: {0}%", Math.Round(s.MarginPercent * 100)) };
        var spacingLabel = new TextBlock { Text = L("Interlinia: {0}x", s.LineSpacingFactor.ToString("0.00", System.Globalization.CultureInfo.CurrentCulture)) };
        margin.ValueChanged += (_, e) => marginLabel.Text = L("Margines ekranu: {0}%", e.NewValue);
        spacing.ValueChanged += (_, e) => spacingLabel.Text = L("Interlinia: {0}x", e.NewValue.ToString("0.00", System.Globalization.CultureInfo.CurrentCulture));
        panel.Children.Add(marginLabel);
        panel.Children.Add(margin);
        panel.Children.Add(spacingLabel);
        panel.Children.Add(spacing);

        panel.Children.Add(new TextBlock { Text = L("Galeria propozycji logo aplikacji"), FontWeight = FontWeights.Bold });
        var logos = new GridView { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 260 };
        foreach (var logo in Logos)
        {
            var item = new StackPanel { Width = 110, Spacing = 4, Padding = new Thickness(6), Background = new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(255, 0x0D, 0x11, 0x1D)) };
            item.Children.Add(new Image { Source = SlideView.LogoSource(logo), Width = 64, Height = 64 });
            item.Children.Add(new TextBlock { Text = logo.Name, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) });
            ToolTipService.SetToolTip(item, logo.Name);
            logos.Items.Add(new GridViewItem { Content = item, Tag = logo.Id });
            if (logo.Id == s.ActiveLogoId) logos.SelectedIndex = logos.Items.Count - 1;
        }
        panel.Children.Add(logos);

        panel.Children.Add(new TextBlock { Text = L("Licencja CCLI i prawa autorskie"), FontWeight = FontWeights.Bold });
        var license = Field(s.CcliLicenseNumber, "1234567");
        var placement = Choice([("firstSlide", L("Na pierwszym slajdzie")), ("lastSlide", L("Na ostatnim slajdzie")), ("allSlides", L("Na każdym slajdzie")), ("none", L("Nie pokazuj"))], s.CopyrightNoticePlacement);
        var ccli = new Grid { ColumnSpacing = 10 };
        ccli.ColumnDefinitions.Add(new ColumnDefinition());
        ccli.ColumnDefinitions.Add(new ColumnDefinition());
        var placementField = Labeled(L("Informacja o prawach na slajdzie:"), placement);
        Grid.SetColumn(placementField, 1);
        ccli.Children.Add(Labeled(L("Numer licencji CCLI parafii:"), license));
        ccli.Children.Add(placementField);
        panel.Children.Add(ccli);
        panel.Children.Add(new TextBlock { Text = L("Dotyczy pieśni z numerem CCLI (np. zaimportowanych z SongSelect). Licencja CCLI wymaga pokazania tytułu, autorów, praw autorskich i numeru licencji przy wyświetlaniu tekstu."), TextWrapping = TextWrapping.Wrap, Opacity = 0.65, FontSize = 12 });
        panel.Children.Add(new TextBlock { Text = L("Raport użycia: zapisane wyświetlenia: {0}", library.CcliUsage.Count) });

        var dialog = new ContentDialog
        {
            Title = L("Ustawienia"),
            Content = new ScrollViewer { Content = panel, MaxHeight = 660 },
            PrimaryButtonText = L("Zapisz"),
            CloseButtonText = L("Anuluj"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await ShowAsync(window, dialog) != ContentDialogResult.Primary) return;
        string Tag(ComboBox box, string fallback) => (box.SelectedItem as ComboBoxItem)?.Tag as string ?? fallback;
        library.UpdateSettings(settings =>
        {
            settings.FontFamily = (font.SelectedItem as string ?? font.Text ?? settings.FontFamily).Trim() is { Length: > 0 } f ? f : settings.FontFamily;
            settings.TextAlignment = Tag(horizontal, settings.TextAlignment);
            settings.VerticalAlignment = Tag(vertical, settings.VerticalAlignment);
            settings.IsBold = bold.IsChecked == true;
            settings.HasShadow = shadow.IsChecked == true;
            if (System.Text.RegularExpressions.Regex.IsMatch(textColor.Text.Trim(), "^#[0-9A-Fa-f]{6}$")) settings.TextColorHex = textColor.Text.Trim().ToUpperInvariant();
            if (System.Text.RegularExpressions.Regex.IsMatch(backgroundColor.Text.Trim(), "^#[0-9A-Fa-f]{6}$")) settings.BackgroundColorHex = backgroundColor.Text.Trim().ToUpperInvariant();
            settings.MarginPercent = margin.Value / 100;
            settings.LineSpacingFactor = Math.Round(spacing.Value, 2);
            if ((logos.SelectedItem as GridViewItem)?.Tag is string logoId) settings.ActiveLogoId = logoId;
            settings.CcliLicenseNumber = license.Text.Trim();
            settings.CopyrightNoticePlacement = Tag(placement, settings.CopyrightNoticePlacement);
            settings.AppLanguage = Tag(language, settings.AppLanguage);
            settings.DictationLanguage = Tag(dictationLanguage, settings.DictationLanguage);
            settings.DictationOnDeviceOnly = dictationOnDevice.IsChecked == true;
            if (Math.Abs(uiScale.Value - initialScale) > 0.001) settings.UiScale = Math.Round(uiScale.Value, 2);
        });
    }

    public static async Task AboutAsync(MainWindow window)
    {
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = "♫ CantatePresenter", FontSize = 22, FontWeight = FontWeights.Bold });
        panel.Children.Add(new TextBlock { Text = L("Wersja {0}", Services.Version) + " · Windows" });
        panel.Children.Add(new TextBlock { Text = L("Autor: Andrzej Oles\nOpracowano we współpracy z Claude (Anthropic)"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = Services.Library.DataDirectory, Opacity = 0.6, FontSize = 12, IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap });
        await ShowAsync(window, new ContentDialog { Title = L("O programie"), Content = panel, CloseButtonText = L("Zamknij") });
    }

    /// <summary>Wikiźródła (domena publiczna i wolne licencje) i odnośnik do CCLI SongSelect, jak w macOS.</summary>
    public static async Task OnlineSearchAsync(MainWindow window)
    {
        var library = Services.Library;
        var query = Field("", L("Wpisz tytuł lub słowa pieśni (np. Kiedy ranne wstają zorze)..."));
        var languageBox = new ComboBox { MinWidth = 140 };
        foreach (var (code, name) in new[] { ("pl", "Polski"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("uk", "Українська"), ("la", "Latina") })
        {
            languageBox.Items.Add(new ComboBoxItem { Content = name, Tag = code });
            if (code == library.Settings.OnlineSearchLanguage) languageBox.SelectedIndex = languageBox.Items.Count - 1;
        }
        var search = new Button { Content = L("Szukaj"), Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        var status = new TextBlock { Opacity = 0.7 };
        var results = new ListView { Height = 300, Width = 320, SelectionMode = ListViewSelectionMode.Single };
        var titleBox = Field("");
        var authorBox = Field("");
        var source = new HyperlinkButton { Content = L("Otwórz źródło") };
        var license = new TextBlock { Opacity = 0.7, FontSize = 12 };
        var lyrics = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var preview = new StackPanel { Spacing = 6, Width = 380 };
        preview.Children.Add(Labeled(L("Tytuł:"), titleBox));
        preview.Children.Add(Labeled(L("Autor:"), authorBox));
        preview.Children.Add(license);
        preview.Children.Add(source);
        preview.Children.Add(new ScrollViewer { Content = lyrics, Height = 170 });
        preview.Visibility = Visibility.Collapsed;
        List<WikisourceResult> found = [];
        string LicenseLabel(string code) => code == "publicDomain" ? L("Domena publiczna") : code == "ccBySA" ? "CC BY-SA" : L("Licencja: zobacz stronę źródła");

        async Task Run()
        {
            var text = query.Text.Trim();
            if (text.Length == 0) return;
            var language = (languageBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "pl";
            library.UpdateSettings(s => s.OnlineSearchLanguage = language);
            status.Text = L("Przeszukiwanie Wikiźródeł...");
            results.Items.Clear();
            try
            {
                found = await Wikisource.SearchAsync(Http, text, language, Services.Version);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
            {
                status.Text = L("Błąd połączenia: {0}", error.Message);
                return;
            }
            status.Text = found.Count == 0 ? L("Nie znaleziono pieśni dla podanej frazy") : "";
            foreach (var result in found) results.Items.Add(new ListViewItem { Content = $"{result.Title}\n{result.Author}", Tag = result });
        }
        search.Click += async (_, _) => await Run();
        query.KeyDown += async (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) await Run(); };
        results.SelectionChanged += (_, _) =>
        {
            if ((results.SelectedItem as ListViewItem)?.Tag is not WikisourceResult result) return;
            titleBox.Text = result.Title;
            authorBox.Text = result.Author;
            license.Text = $"{L("Wikiźródła")} · {LicenseLabel(result.License)}";
            source.NavigateUri = new Uri(result.Url);
            lyrics.Text = result.Lyrics;
            preview.Visibility = Visibility.Visible;
        };
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        query.Width = 380;
        top.Children.Add(query);
        top.Children.Add(Dictation.Button(query, DictationMode.Replace));
        top.Children.Add(languageBox);
        top.Children.Add(search);
        var body = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        body.Children.Add(results);
        body.Children.Add(preview);
        var songSelect = new HyperlinkButton { Content = L("Szukaj w SongSelect") };
        songSelect.Click += (_, _) => songSelect.NavigateUri = new Uri(Core.Import.SongSelectImporter.SearchUrl(query.Text.Trim()));
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(top);
        panel.Children.Add(new TextBlock { Text = L("Źródło: Wikiźródła. Tradycyjne pieśni w domenie publicznej lub na wolnej licencji; adres strony zostaje zapisany w pieśni."), TextWrapping = TextWrapping.Wrap, Opacity = 0.65, FontSize = 12 });
        panel.Children.Add(status);
        panel.Children.Add(body);
        panel.Children.Add(songSelect);
        var dialog = new ContentDialog
        {
            Title = L("Wyszukiwanie pieśni religijnych w internecie"),
            Content = panel,
            PrimaryButtonText = L("Importuj do programu"),
            CloseButtonText = L("Zamknij"),
            DefaultButton = ContentDialogButton.None,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 900.0;
        if (await ShowAsync(window, dialog) != ContentDialogResult.Primary) return;
        if ((results.SelectedItem as ListViewItem)?.Tag is not WikisourceResult chosen) return;
        var song = Song.Create(titleBox.Text.Trim().Length > 0 ? titleBox.Text.Trim() : chosen.Title,
            authorBox.Text.Trim().Length > 0 ? authorBox.Text.Trim() : L("Nieznany"), tags: [L("Wikiźródła")], rawLyrics: chosen.Lyrics);
        song.Source = chosen.Url;
        song.Copyright = LicenseLabel(chosen.License);
        library.AddSong(song);
    }
}
