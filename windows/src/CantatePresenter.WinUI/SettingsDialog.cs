using System.Globalization;
using CantatePresenter.Core.Input;
using CantatePresenter.Core.Models;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Ustawienia prezentacji i wyglądu (SettingsSheet w macOS): grupy w tej samej kolejności, zmiany działają od razu
/// (podgląd w oknie głównym), „Gotowe” zamyka okno. Kopie i Dysk Google otwierają osobne okna po zamknięciu ustawień
/// (WinUI pokazuje tylko jedno okno dialogowe naraz).
/// </summary>
public static class SettingsDialog
{
    /// <summary>Języki wyszukiwania w Wikiźródłach (subdomeny), jak w oknie „Online”.</summary>
    public static readonly (string Code, string Name, string Flag)[] SearchLanguages =
    [
        ("pl", "Polski", "🇵🇱"), ("en", "English", "🇬🇧"), ("de", "Deutsch", "🇩🇪"), ("es", "Español", "🇪🇸"), ("uk", "Українська", "🇺🇦"), ("la", "Latina", "🇻🇦"),
    ];

    private static readonly string[] CommonFonts = ["Segoe UI", "Arial", "Calibri", "Helvetica Neue", "Georgia", "Times New Roman", "Verdana", "Trebuchet MS", "Cambria", "Bahnschrift", "Tahoma"];

    /// <summary>Klawisze do wyboru jak ShortcutPresets.availableKeys w macOS (kody klawiszy macOS z settings.json).</summary>
    private static (int Code, string Name)[] AvailableKeys() =>
    [
        (49, L("Spacja (Space)")), (124, L("Strzałka w prawo (→)")), (123, L("Strzałka w lewo (←)")), (125, L("Strzałka w dół (↓)")), (126, L("Strzałka w górę (↑)")),
        (36, "Enter (↵)"), (53, "Escape (Esc)"), (48, "Tabulator (Tab)"), (51, "Backspace (⌫)"), (121, "Page Down (⇟)"), (116, "Page Up (⇞)"),
        (11, L("Klawisz B")), (8, L("Klawisz C")), (15, L("Klawisz R")), (45, L("Klawisz N")), (35, L("Klawisz P")),
        (33, L("Klawisz [ (Lewy nawias)")), (30, L("Klawisz ] (Prawy nawias)")), (96, L("Klawisz F5")), (97, L("Klawisz F6")),
    ];

    private static string KeyName(int code) => AvailableKeys().FirstOrDefault(k => k.Code == code).Name ?? L("Klawisz (kod: {0})", code);

    /// <summary>Konflikty skrótów jak ShortcutSettings.conflicts w macOS (W5).</summary>
    public static List<string> Conflicts(ShortcutSettings s)
    {
        (string Name, int Code)[] entries =
        [
            (L("Poprzedni slajd"), s.PrevSlideKey), (L("Następny slajd"), s.NextSlideKey), (L("Poprzedni utwór"), s.PrevSongKey), (L("Następny utwór"), s.NextSongKey),
            (L("Uruchomienie prezentacji"), s.StartPresentationKey), (L("Zatrzymanie prezentacji"), s.StopPresentationKey), (L("Czarny ekran"), s.BlackScreenKey), (L("Ukrycie tekstu"), s.ClearTextKey),
        ];
        var result = new List<string>();
        foreach (var group in entries.GroupBy(e => e.Code).OrderBy(g => g.Key).Where(g => g.Count() > 1))
            result.Add(L("{0}: {1}. Zadziała tylko pierwsza akcja.", KeyName(group.Key), string.Join(", ", group.Select(e => e.Name))));
        int[] digits = [18, 19, 20, 21, 23, 22, 26, 28, 25];
        foreach (var (name, code) in entries)
        {
            if (code == 15) result.Add(L("{0} na klawiszu R: klawisz przestanie przechodzić do refrenu.", name));
            else if (digits.Contains(code)) result.Add(L("{0} na klawiszu cyfry: cyfra przestanie przechodzić do zwrotki.", name));
            else if (code == 53 && code != s.StopPresentationKey) result.Add(L("{0} na klawiszu Esc: Esc przestanie kończyć projekcję.", name));
        }
        return result;
    }

    /// <summary>Klawisze stałe jak KeyboardRouter.fixedKeysHelp w macOS (z Ctrl zamiast ⌘).</summary>
    public static (string Keys, string Action)[] FixedKeys() =>
    [
        ("← / ↑", L("Poprzedni slajd (↑ na liście pieśni: poprzednia pieśń)")),
        ("→ / ↓", L("Następny slajd (↓ na liście pieśni: następna pieśń)")),
        ("Page Up / Page Down", L("Poprzedni / następny slajd (pilot), także w polu wyszukiwania")),
        (L("Enter w oknie projekcji"), L("Następny slajd")),
        ("Esc", L("Zakończenie projekcji; w polu wyszukiwania: wyjście z pola")),
        ("R", L("Refren")),
        ("1 – 9", L("Zwrotka o tym numerze")),
        ("Ctrl+F", L("Szukaj pieśni (Enter: wybór pierwszego wyniku)")),
        ("Ctrl+T", L("Szybki tekst na żywo")),
        ("Ctrl+E", L("Edycja zaznaczonej pieśni")),
        ("Ctrl+I", L("Import pieśni")),
        ("Ctrl+B", L("Utwórz pełną kopię zapasową")),
        ("Ctrl+ / Ctrl− / Ctrl+0", L("Powiększenie / pomniejszenie / domyślna skala interfejsu")),
        ("F1", L("Instrukcja obsługi")),
    ];

    /// <summary>Rodziny czcionek zainstalowanych w systemie (rejestr Fonts) i popularne nazwy.</summary>
    private static List<string> SystemFonts()
    {
        var names = new SortedSet<string>(CommonFonts, StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var hive in new[] { Microsoft.Win32.Registry.LocalMachine, Microsoft.Win32.Registry.CurrentUser })
            {
                using var key = hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts");
                if (key is null) continue;
                foreach (var value in key.GetValueNames())
                {
                    var name = System.Text.RegularExpressions.Regex.Replace(value, @"\s*\((TrueType|OpenType|All res)\)$", "");
                    foreach (var part in name.Split('&'))
                    {
                        var family = System.Text.RegularExpressions.Regex.Replace(part.Trim(),
                            @"\s+(Bold|Italic|Oblique|Light|Semibold|SemiBold|Semilight|SemiLight|Black|Heavy|Medium|Thin|ExtraLight|ExtraBold|Extra Light|Condensed|Regular|Demibold|Narrow)(\s.*)?$", "");
                        if (family.Length > 1 && !family.StartsWith('@')) names.Add(family);
                    }
                }
            }
        }
        catch (Exception error) when (error is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
        }
        return names.ToList();
    }

    public static async Task ShowAsync(MainWindow window)
    {
        var library = Services.Library;
        var s = library.Settings;
        void Apply(Action<AppSettings> change) => library.UpdateSettings(change);
        Func<Task>? after = null;
        ContentDialog? dialog = null;
        void Then(Func<Task> action)
        {
            after = action;
            dialog?.Hide();
        }

        var panel = new StackPanel { Spacing = 20, Padding = new Thickness(0, 0, 14, 0) };
        static Grid Row(string label, UIElement control, double labelWidth = 190)
        {
            var text = new TextBlock { Text = label, FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap };
            return Ui.Columns(10, (text, labelWidth), (control, -1));
        }
        static ComboBox Choice<T>(IEnumerable<(T Value, string Label)> options, T current, double width = 0)
        {
            var box = new ComboBox { HorizontalAlignment = width > 0 ? HorizontalAlignment.Left : HorizontalAlignment.Stretch };
            if (width > 0) box.Width = width;
            foreach (var (value, label) in options)
            {
                box.Items.Add(new ComboBoxItem { Content = label, Tag = value });
                if (Equals(value, current)) box.SelectedIndex = box.Items.Count - 1;
            }
            return box;
        }
        static T? Selected<T>(ComboBox box) => box.SelectedItem is ComboBoxItem { Tag: T value } ? value : default;

        // MARK: Języki i dyktowanie
        panel.Children.Add(Ui.Group(Glyphs.Language, L("Języki i dyktowanie głosowe"), out var languages));
        var appLanguage = Choice(Core.Localization.Catalog.Languages.Select(l => (l.Code, l.Name)), s.AppLanguage, 260);
        appLanguage.SelectionChanged += (_, _) => { if (Selected<string>(appLanguage) is string code) Apply(x => x.AppLanguage = code); };
        languages.Children.Add(Row(L("Język aplikacji:"), appLanguage));
        var searchLanguage = Choice(SearchLanguages.Select(l => (l.Code, $"{l.Flag}  {l.Name}")), s.OnlineSearchLanguage, 260);
        searchLanguage.SelectionChanged += (_, _) => { if (Selected<string>(searchLanguage) is string code) Apply(x => x.OnlineSearchLanguage = code); };
        languages.Children.Add(Row(L("Język wyszukiwania pieśni:"), searchLanguage));
        var dictationLanguage = Choice(Dictation.Languages.Select(l => (l.Code, $"{l.Flag}  {l.Name}")), s.DictationLanguage, 260);
        dictationLanguage.SelectionChanged += (_, _) => { if (Selected<string>(dictationLanguage) is string code) Apply(x => x.DictationLanguage = code); };
        languages.Children.Add(Row(L("Język dyktowania głosem:"), dictationLanguage));
        var onDevice = new CheckBox { Content = L("Rozpoznawaj mowę tylko na tym urządzeniu"), IsChecked = s.DictationOnDeviceOnly };
        onDevice.Click += (_, _) => Apply(x => x.DictationOnDeviceOnly = onDevice.IsChecked == true);
        languages.Children.Add(onDevice);
        languages.Children.Add(Ui.Note(L("Windows rozpoznaje dyktowany tekst w usłudze online firmy Microsoft (Ustawienia systemu Windows → Prywatność i zabezpieczenia → Mowa). Przy opcji „tylko na tym urządzeniu” dyktowanie jest wyłączone.")));
        languages.Children.Add(Ui.Divider());
        var test = new TextBox { PlaceholderText = L("Kliknij mikrofon obok i powiedz kilka słów...") };
        var testRow = new StackPanel { Spacing = 6 };
        testRow.Children.Add(new TextBlock { Text = L("Przetestuj dyktowanie mikrofonem:"), FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = Ui.Secondary });
        testRow.Children.Add(Dictation.WithMic(test, DictationMode.Append));
        testRow.Children.Add(Ui.Note(L("Dyktowanie działa bezpośrednio w wyszukiwarkach (biblioteka, online, autor/tytuł) oraz w edytorze nowej pieśni (tytuł, autor i treść zwrotek).")));
        languages.Children.Add(new Border { Child = testRow, Padding = new Thickness(8), CornerRadius = new CornerRadius(6), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });

        // MARK: Plansza startowa i logo
        panel.Children.Add(Ui.Group(Glyphs.Image, L("Plansza startowa i Logo aplikacji"), out var standby));
        standby.Children.Add(Ui.Note(L("Gdy prezentacja pieśni nie jest aktywna, na ekranie projektora wyświetlana jest plansza powitalna HTML z wybranym logo programu.")));
        var activeImage = new Image { Width = 50, Height = 50 };
        var activeName = new TextBlock { FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center };
        void ShowActive()
        {
            if (ActiveLogo is Logo logo)
            {
                activeImage.Source = SlideView.LogoSource(logo);
                activeName.Text = logo.Name;
            }
        }
        ShowActive();
        var activeBox = new Border { Child = activeImage, Width = 58, Height = 58, CornerRadius = new CornerRadius(8), Background = Ui.Brush(ColorHelper.FromArgb(255, 0x0D, 0x11, 0x1D)), Padding = new Thickness(4) };
        var activeText = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        activeText.Children.Add(new TextBlock { Text = L("Aktywne logo:"), Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
        activeText.Children.Add(activeName);
        var gallery = new GridView { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 300, Visibility = Visibility.Collapsed };
        foreach (var logo in Logos)
        {
            var item = new StackPanel { Width = 112, Spacing = 4, Padding = new Thickness(6), Background = Ui.Brush(ColorHelper.FromArgb(255, 0x0D, 0x11, 0x1D)), CornerRadius = new CornerRadius(6) };
            item.Children.Add(new Image { Source = SlideView.LogoSource(logo), Width = 64, Height = 64 });
            item.Children.Add(new TextBlock { Text = logo.Name, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, Foreground = Ui.Brush(Colors.White), HorizontalAlignment = HorizontalAlignment.Center });
            ToolTipService.SetToolTip(item, logo.Name);
            gallery.Items.Add(new GridViewItem { Content = item, Tag = logo.Id });
            if (logo.Id == s.ActiveLogoId) gallery.SelectedIndex = gallery.Items.Count - 1;
        }
        gallery.SelectionChanged += (_, _) =>
        {
            if ((gallery.SelectedItem as GridViewItem)?.Tag is string id && id != library.Settings.ActiveLogoId)
            {
                Apply(x => x.ActiveLogoId = id);
                ShowActive();
            }
        };
        var choose = Ui.Button(Glyphs.Image, L("Wybierz inne logo ({0} propozycje)...", Logos.Count), (_, _) => gallery.Visibility = gallery.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible, accent: true);
        standby.Children.Add(new Border
        {
            Child = Ui.Columns(12, (activeBox, 0), (activeText, -1), (choose, 0)),
            Padding = new Thickness(8), CornerRadius = new CornerRadius(8), Background = Ui.Resource("SubtleFillColorSecondaryBrush"),
        });
        standby.Children.Add(gallery);

        // MARK: Kopia zapasowa i Dysk Google
        panel.Children.Add(Ui.Group(Glyphs.Cloud, L("Kopia zapasowa i Dysk Google"), out var backup));
        var shield = new StackPanel { Spacing = 3 };
        shield.Children.Add(new TextBlock { Text = L("Kompletna ochrona danych aplikacji"), FontWeight = FontWeights.Bold });
        shield.Children.Add(Ui.Note(L("Kopia zapasowa (.cantatebackup) zawiera: całą bazę pieśni ({0}), plany nabożeństw ({1}), chwyty gitarowe i wszystkie ustawienia programu.", library.Songs.Count, library.Plans.Count)));
        backup.Children.Add(new Border
        {
            Child = Ui.Columns(10, (Ui.Icon(Glyphs.Checkmark, 20, Ui.Green), 0), (shield, -1)),
            Padding = new Thickness(8), CornerRadius = new CornerRadius(8), Background = Ui.Brush(Ui.Green, 0.08),
        });
        var backupButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        backupButtons.Children.Add(Ui.Button(Glyphs.Save, L("Utwórz pełną kopię zapasową..."), (_, _) => Then(() => ImportExport.CreateBackupAsync(window)), accent: true));
        backupButtons.Children.Add(Ui.Button(Glyphs.Refresh, L("Przywróć z pliku kopii zapasowej..."), (_, _) => Then(() => ImportExport.RestoreBackupAsync(window))));
        backup.Children.Add(backupButtons);
        backup.Children.Add(Ui.Divider());
        var drive = s.GoogleDrive;
        var driveState = drive.IsEnabled ? (Drive.IsSignedIn ? (drive.AccountEmail.Length > 0 ? drive.AccountEmail : L("Połączono")) : L("Nie połączono")) : "";
        var driveRow = Ui.Columns(10,
            (Ui.Label(Glyphs.Cloud, L("Synchronizacja i kopie na koncie Dysk Google (Google Drive)"), 14, drive.IsEnabled ? Ui.Blue : null), -1),
            (driveState.Length > 0 ? Ui.Badge(driveState, Ui.Blue, 11) : new Border(), 0));
        backup.Children.Add(driveRow);
        backup.Children.Add(Ui.Note(L("Logowanie, wysyłanie kopii, przywracanie z Dysku i kopia przy zamykaniu aplikacji.")));
        backup.Children.Add(Ui.Button(Glyphs.Cloud, L("Kopie zapasowe na Dysku Google") + "...", (_, _) => Then(() => GoogleDriveDialog.ShowAsync(window))));

        // MARK: Skróty klawiszowe
        panel.Children.Add(Ui.Group(Glyphs.Keyboard, L("Skróty klawiszowe sterowania prezentacją"), out var keys));
        var conflicts = new StackPanel { Spacing = 4 };
        var conflictsBox = new Border { Child = conflicts, Padding = new Thickness(8), CornerRadius = new CornerRadius(6), Background = Ui.Brush(Ui.Orange, 0.1) };
        void ShowConflicts()
        {
            conflicts.Children.Clear();
            foreach (var conflict in Conflicts(library.Settings.Shortcuts))
                conflicts.Children.Add(Ui.Label(Glyphs.Warning, conflict, 12, Ui.Orange));
            foreach (var label in conflicts.Children.OfType<StackPanel>().SelectMany(p => p.Children.OfType<TextBlock>()))
            {
                label.Foreground = Ui.Brush(Ui.Orange);
                label.TextWrapping = TextWrapping.Wrap;
                label.FontSize = 12;
            }
            conflictsBox.Visibility = conflicts.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        var keyRows = new StackPanel { Spacing = 8 };
        void KeyRows()
        {
            keyRows.Children.Clear();
            var current = library.Settings.Shortcuts;
            void KeyRow(string title, int value, Func<ShortcutSettings, int, ShortcutSettings> set)
            {
                var options = AvailableKeys().ToList();
                if (options.All(k => k.Code != value)) options.Add((value, KeyName(value)));
                var box = Choice(options.Select(k => (k.Code, k.Name)), value, 260);
                box.SelectionChanged += (_, _) =>
                {
                    if (box.SelectedItem is not ComboBoxItem { Tag: int code }) return;
                    Apply(x => x.Shortcuts = set(x.Shortcuts, code));
                    ShowConflicts();
                };
                keyRows.Children.Add(Row(title, box, 220));
            }
            KeyRow(L("Poprzedni slajd:"), current.PrevSlideKey, (x, c) => x with { PrevSlideKey = c });
            KeyRow(L("Następny slajd:"), current.NextSlideKey, (x, c) => x with { NextSlideKey = c });
            KeyRow(L("Poprzedni utwór (z planu):"), current.PrevSongKey, (x, c) => x with { PrevSongKey = c });
            KeyRow(L("Następny utwór (z planu):"), current.NextSongKey, (x, c) => x with { NextSongKey = c });
            KeyRow(L("Uruchomienie prezentacji:"), current.StartPresentationKey, (x, c) => x with { StartPresentationKey = c });
            KeyRow(L("Zatrzymanie prezentacji:"), current.StopPresentationKey, (x, c) => x with { StopPresentationKey = c });
            KeyRow(L("Czarny ekran (toggle):"), current.BlackScreenKey, (x, c) => x with { BlackScreenKey = c });
            KeyRow(L("Ukrycie tekstu (toggle):"), current.ClearTextKey, (x, c) => x with { ClearTextKey = c });
        }
        KeyRows();
        keys.Children.Add(keyRows);
        ShowConflicts();
        keys.Children.Add(conflictsBox);
        var fixedKeys = new StackPanel { Spacing = 4, Margin = new Thickness(0, 4, 0, 0) };
        fixedKeys.Children.Add(new TextBlock { Text = L("Klawisze stałe"), FontWeight = FontWeights.SemiBold, FontSize = 12 });
        foreach (var (k, action) in FixedKeys())
            fixedKeys.Children.Add(Ui.Columns(8, (new TextBlock { Text = k, FontSize = 12, FontWeight = FontWeights.Medium }, 200), (new TextBlock { Text = action, FontSize = 12, Foreground = Ui.Secondary, TextWrapping = TextWrapping.Wrap }, -1)));
        fixedKeys.Children.Add(Ui.Note(L("Skróty działają, gdy pole wyszukiwania jest nieaktywne (po starcie albo po Esc). Klawisz wybrany powyżej ma pierwszeństwo przed klawiszem stałym, np. R przypisane do czarnego ekranu przestaje włączać refren.")));
        keys.Children.Add(fixedKeys);
        var resetKeys = new Button { Content = L("Przywróć domyślne skróty"), HorizontalAlignment = HorizontalAlignment.Right };
        resetKeys.Click += (_, _) => { Apply(x => x.Shortcuts = new ShortcutSettings()); KeyRows(); ShowConflicts(); };
        keys.Children.Add(resetKeys);

        // MARK: Typografia
        panel.Children.Add(Ui.Group(Glyphs.Font, L("Typografia ekranu prezentacji"), out var typography));
        var font = new ComboBox { IsEditable = true, Width = 300, HorizontalAlignment = HorizontalAlignment.Left, Text = s.FontFamily };
        foreach (var f in SystemFonts()) font.Items.Add(f);
        font.SelectedItem = font.Items.OfType<string>().FirstOrDefault(f => string.Equals(f, s.FontFamily, StringComparison.OrdinalIgnoreCase));
        void ApplyFont(string? name)
        {
            var value = (name ?? "").Trim();
            if (value.Length > 0 && value != library.Settings.FontFamily) Apply(x => x.FontFamily = value);
        }
        font.SelectionChanged += (_, _) => ApplyFont(font.SelectedItem as string);
        font.TextSubmitted += (_, e) => ApplyFont(e.Text);
        typography.Children.Add(Row(L("Czcionka systemowa:"), font, 160));
        var bold = new CheckBox { Content = L("Pogrubienie tekstu (Bold)"), IsChecked = s.IsBold };
        bold.Click += (_, _) => Apply(x => x.IsBold = bold.IsChecked == true);
        typography.Children.Add(bold);
        var shadow = new CheckBox { Content = L("Cień pod tekstem (poprawia kontrast na projektorze)"), IsChecked = s.HasShadow };
        shadow.Click += (_, _) => Apply(x => x.HasShadow = shadow.IsChecked == true);
        typography.Children.Add(shadow);
        typography.Children.Add(Row(L("Wyrównanie tekstu:"), Segmented([("center", L("Środek")), ("left", L("Do lewej")), ("right", L("Do prawej"))], s.TextAlignment, v => Apply(x => x.TextAlignment = v)), 160));
        typography.Children.Add(Row(L("Położenie pionowe:"), Segmented([("top", L("Góra")), ("center", L("Środek")), ("bottom", L("Dół"))], s.VerticalAlignment, v => Apply(x => x.VerticalAlignment = v)), 160));

        // MARK: Kolory
        panel.Children.Add(Ui.Group(Glyphs.Color, L("Kolory ekranu"), out var colors));
        colors.Children.Add(Row(L("Kolor tekstu:"), ColorRow(s.TextColorHex, hex => Apply(x => x.TextColorHex = hex), [(L("Biały"), "#FFFFFF"), (L("Żółty"), "#FFE57F")]), 160));
        colors.Children.Add(Row(L("Kolor tła:"), ColorRow(s.BackgroundColorHex, hex => Apply(x => x.BackgroundColorHex = hex), [(L("Czarny"), "#000000"), (L("Ciemny granat"), "#0A0E1A")]), 160));

        // MARK: Marginesy i interlinia
        panel.Children.Add(Ui.Group(Glyphs.Margins, L("Marginesy i interlinia"), out var spacing));
        var marginLabel = new TextBlock { Text = L("Margines ekranu: {0}%", Math.Round(s.MarginPercent * 100)), FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center };
        var margin = new Slider { Minimum = 3, Maximum = 18, StepFrequency = 1, Value = Math.Round(s.MarginPercent * 100) };
        margin.ValueChanged += (_, e) => { marginLabel.Text = L("Margines ekranu: {0}%", e.NewValue); Apply(x => x.MarginPercent = e.NewValue / 100); };
        spacing.Children.Add(Ui.Columns(10, (marginLabel, 180), (margin, -1)));
        var lineLabel = new TextBlock { Text = L("Interlinia: {0}x", s.LineSpacingFactor.ToString("0.00", CultureInfo.CurrentCulture)), FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center };
        var line = new Slider { Minimum = 1, Maximum = 1.5, StepFrequency = 0.05, Value = s.LineSpacingFactor };
        line.ValueChanged += (_, e) => { lineLabel.Text = L("Interlinia: {0}x", e.NewValue.ToString("0.00", CultureInfo.CurrentCulture)); Apply(x => x.LineSpacingFactor = Math.Round(e.NewValue, 2)); };
        spacing.Children.Add(Ui.Columns(10, (lineLabel, 180), (line, -1)));

        // MARK: CCLI
        panel.Children.Add(Ui.Group(Glyphs.Copyright, L("Licencja CCLI i prawa autorskie"), out var ccli));
        var license = new TextBox { Text = s.CcliLicenseNumber, PlaceholderText = "1234567", Width = 160, HorizontalAlignment = HorizontalAlignment.Left };
        license.LostFocus += (_, _) => { if (license.Text.Trim() != library.Settings.CcliLicenseNumber) Apply(x => x.CcliLicenseNumber = license.Text.Trim()); };
        ccli.Children.Add(Row(L("Numer licencji CCLI parafii:"), license, 230));
        var placement = Choice([("firstSlide", L("Na pierwszym slajdzie")), ("lastSlide", L("Na ostatnim slajdzie")), ("allSlides", L("Na każdym slajdzie")), ("none", L("Nie pokazuj"))], s.CopyrightNoticePlacement, 260);
        placement.SelectionChanged += (_, _) => { if (Selected<string>(placement) is string v) Apply(x => x.CopyrightNoticePlacement = v); };
        ccli.Children.Add(Row(L("Informacja o prawach na slajdzie:"), placement, 230));
        ccli.Children.Add(Ui.Note(L("Dotyczy pieśni z numerem CCLI (np. zaimportowanych z SongSelect). Licencja CCLI wymaga pokazania tytułu, autorów, praw autorskich i numeru licencji przy wyświetlaniu tekstu.")));
        ccli.Children.Add(Ui.Divider());
        var export = Ui.Button(Glyphs.Document, L("Eksportuj raport CCLI (CSV)..."), (_, _) => Then(() => ImportExport.ExportCcliAsync(window)));
        export.IsEnabled = library.CcliUsage.Count > 0;
        ccli.Children.Add(Ui.Columns(10, (new TextBlock { Text = L("Raport użycia: zapisane wyświetlenia: {0}", library.CcliUsage.Count), FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center }, -1), (export, 0)));
        ccli.Children.Add(Ui.Note(L("Każda pieśń z numerem CCLI jest zapisywana raz dziennie, gdy trafi na ekran. Plik CSV pomoże zgłosić użycie na stronie CCLI.")));

        // MARK: Skala interfejsu
        panel.Children.Add(Ui.Group(Glyphs.Zoom, L("Wielkość elementów interfejsu (UI Scale)"), out var zoom));
        var zoomLabel = new TextBlock { Text = L("Skala interfejsu: {0}%", Math.Round(s.UiScale * 100)), FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center };
        var zoomSlider = new Slider { Minimum = 0.8, Maximum = 1.5, StepFrequency = 0.05, Value = Math.Clamp(s.UiScale, 0.8, 1.5) };
        var zoomReady = false;
        zoomSlider.ValueChanged += (_, e) =>
        {
            zoomLabel.Text = L("Skala interfejsu: {0}%", Math.Round(e.NewValue * 100));
            if (zoomReady) Apply(x => x.UiScale = Math.Round(e.NewValue, 2));
        };
        zoomSlider.Loaded += (_, _) => zoomReady = true;
        var zoomReset = new Button { Content = L("Resetuj (100%)") };
        zoomReset.Click += (_, _) => { zoomSlider.Value = 1; Apply(x => x.UiScale = 1); };
        zoom.Children.Add(Ui.Columns(10, (zoomLabel, 180), (zoomSlider, -1), (zoomReset, 0)));
        zoom.Children.Add(Ui.Note(Lw("Możesz także używać skrótów Cmd + / Cmd - oraz przycisków w prawym górnym rogu paska narzędzi.")));

        // MARK: Dolny pasek
        panel.Children.Add(Ui.Group(Glyphs.BottomBar, L("Dolny pasek sterowania prezentacją"), out var bar));
        var barLabel = new TextBlock { Text = L("Wysokość paska: {0} px", Math.Round(s.BottomBarHeight)), FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center };
        var barSlider = new Slider { Minimum = 52, Maximum = 160, StepFrequency = 2, Value = s.BottomBarHeight };
        barSlider.ValueChanged += (_, e) => { barLabel.Text = L("Wysokość paska: {0} px", Math.Round(e.NewValue)); Apply(x => x.BottomBarHeight = e.NewValue); };
        var barReset = new Button { Content = L("Domyślna (72 px)") };
        barReset.Click += (_, _) => barSlider.Value = 72;
        bar.Children.Add(Ui.Columns(10, (barLabel, 180), (barSlider, -1), (barReset, 0)));
        bar.Children.Add(Ui.Note(L("Wielkość ikon, czcionek klawiszy i etykiet w dolnym pasku dostosowuje się automatycznie do wybranej wysokości. Pasek można także rozciągać przeciągając myszką uchwyt na linii podziału.")));

        // MARK: Uaktualnienia (tylko Windows; w macOS Sparkle)
        panel.Children.Add(Ui.Group(Glyphs.Download, L("Uaktualnienia"), out var updates));
        var checkUpdates = new CheckBox { Content = L("Sprawdzaj uaktualnienia przy uruchamianiu"), IsChecked = s.CheckForUpdatesAutomatically };
        checkUpdates.Click += (_, _) => Apply(x => x.CheckForUpdatesAutomatically = checkUpdates.IsChecked == true);
        updates.Children.Add(Ui.Columns(10, (checkUpdates, -1), (Ui.Button(Glyphs.Download, L("Sprawdź uaktualnienia..."), (_, _) => Then(() => Updater.CheckAsync(window, manual: true))), 0)));

        dialog = new ContentDialog
        {
            Title = L("Ustawienia prezentacji i wyglądu"),
            Content = new ScrollViewer { Content = panel, MaxHeight = 640 },
            PrimaryButtonText = L("Gotowe"),
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 820.0;
        panel.MinWidth = 700;
        await Dialogs.ShowAsync(window, dialog);
        if (license.Text.Trim() != library.Settings.CcliLicenseNumber) Apply(x => x.CcliLicenseNumber = license.Text.Trim());
        if (after is not null) await after();
    }

    /// <summary>Przełącznik segmentowy (jak SegmentedPickerStyle w macOS).</summary>
    private static StackPanel Segmented((string Value, string Label)[] options, string current, Action<string> select)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 0 };
        var buttons = new List<ToggleButton>();
        for (var i = 0; i < options.Length; i++)
        {
            var (value, label) = options[i];
            var button = new ToggleButton
            {
                Content = label, IsChecked = value == current, MinWidth = 90,
                CornerRadius = new CornerRadius(i == 0 ? 4 : 0, i == options.Length - 1 ? 4 : 0, i == options.Length - 1 ? 4 : 0, i == 0 ? 4 : 0),
            };
            button.Click += (_, _) =>
            {
                foreach (var other in buttons) other.IsChecked = other == button;
                select(value);
            };
            buttons.Add(button);
            panel.Children.Add(button);
        }
        return panel;
    }

    /// <summary>Kolor: próbka otwierająca ColorPicker, kod szesnastkowy i gotowe kolory.</summary>
    private static StackPanel ColorRow(string hex, Action<string> apply, (string Label, string Hex)[] presets)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var swatch = new Border { Width = 34, Height = 22, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(1), BorderBrush = Ui.Brush(Ui.Gray, 0.6) };
        var code = new TextBlock { FontFamily = new FontFamily("Consolas"), Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center, MinWidth = 70 };
        var picker = new ColorPicker { IsAlphaEnabled = false, IsMoreButtonVisible = true, IsColorChannelTextInputVisible = true, IsHexInputVisible = true };
        var current = hex;
        void Show(string value)
        {
            current = value;
            swatch.Background = Ui.Brush(SlideView.ParseColor(value, Colors.Black));
            code.Text = value;
        }
        Show(hex);
        var pickerButton = new Button { Content = swatch, Padding = new Thickness(4) };
        ToolTipService.SetToolTip(pickerButton, L("Wybierz kolor"));
        var flyout = new Flyout { Content = picker };
        flyout.Opening += (_, _) => picker.Color = SlideView.ParseColor(current, Colors.Black);
        flyout.Closed += (_, _) =>
        {
            var c = picker.Color;
            var value = $"#{c.R:X2}{c.G:X2}{c.B:X2}";
            if (value != current) { Show(value); apply(value); }
        };
        pickerButton.Flyout = flyout;
        row.Children.Add(pickerButton);
        row.Children.Add(code);
        foreach (var (label, value) in presets)
        {
            var preset = new Button { Content = label, Padding = new Thickness(8, 3, 8, 4) };
            preset.Click += (_, _) => { Show(value); apply(value); };
            row.Children.Add(preset);
        }
        return row;
    }
}
