using CantatePresenter.Core.Import;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Windows.UI;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Przegląd importu jak ImportReviewSheet w macOS: liczniki, zakładki (duplikaty, chwyty, kolizje z biblioteką,
/// wszystkie do dodania), filtr listy i decyzja „pomiń” dla każdego duplikatu. Bez zakładki „Autorzy i polskie litery”
/// (wzbogacanie z wbudowanego katalogu jest tylko w macOS).
/// </summary>
public static class ImportReviewDialog
{
    /// <summary>Pieśni do dodania albo null, gdy użytkownik anulował import.</summary>
    public static async Task<List<Song>?> ShowAsync(MainWindow window, ImportReport report)
    {
        var duplicateSkips = new Dictionary<string, bool>();
        var collisionSkips = new Dictionary<string, bool>();
        List<Song> Commit() => SongDeduplication.SongsToCommit(report, duplicateSkips, collisionSkips);
        var withChords = report.UniqueSongs.Where(s => s.HasChords).ToList();

        var dialog = new ContentDialog
        {
            PrimaryButtonText = L("Zaimportuj {0} pieśni", Commit().Count),
            CloseButtonText = L("Anuluj"),
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 960.0;
        // Zielony przycisk importu jak .tint(.green) w macOS.
        var green = Ui.Brush(Ui.Green);
        dialog.Resources["AccentButtonBackground"] = green;
        dialog.Resources["AccentButtonBackgroundPointerOver"] = Ui.Brush(Ui.Green, 0.88);
        dialog.Resources["AccentButtonBackgroundPressed"] = Ui.Brush(Ui.Green, 0.75);
        var countValue = new TextBlock { Text = Commit().Count.ToString(), FontSize = 18, FontWeight = FontWeights.Bold };
        var summary = new TextBlock { FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center };
        void Refresh()
        {
            var count = Commit().Count;
            countValue.Text = count.ToString();
            dialog.PrimaryButtonText = L("Zaimportuj {0} pieśni", count);
            summary.Text = L("Gotowych do dodania: {0} pieśni ({1} z chwytami gitarowymi)", count, withChords.Count);
        }

        // MARK: Liczniki
        static Border Metric(string glyph, Color color, UIElement value, string title)
        {
            var text = new StackPanel { Spacing = 0 };
            text.Children.Add(value);
            text.Children.Add(new TextBlock { Text = title, FontSize = 11, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary });
            return new Border
            {
                Child = Ui.Columns(10, (Ui.Icon(glyph, 20, color), 28), (text, -1)),
                Padding = new Thickness(8), CornerRadius = new CornerRadius(8), MinWidth = 170,
                Background = Ui.Brush(color, 0.08), BorderBrush = Ui.Brush(color, 0.2), BorderThickness = new Thickness(1),
            };
        }
        static TextBlock Number(int value) => new() { Text = value.ToString(), FontSize = 18, FontWeight = FontWeights.Bold };
        var metrics = new Grid { ColumnSpacing = 10 };
        UIElement[] cards =
        [
            Metric(Glyphs.Document, Ui.Blue, Number(report.TotalScanned), L("Wczytano z pliku") + " · " + L("utworów")),
            Metric(Glyphs.Library, Ui.Orange, Number(report.DuplicateRecords.Count), L("Wykryte duplikaty") + " · " + L("pominięte")),
            Metric(Glyphs.Music, Ui.Yellow, Number(withChords.Count), L("Chwyty gitarowe") + " · " + L("z akordami")),
            Metric(Glyphs.Checkmark, Ui.Green, countValue, L("Do zaimportowania") + " · " + L("unikalnych pieśni")),
        ];
        for (var i = 0; i < cards.Length; i++)
        {
            metrics.ColumnDefinitions.Add(new ColumnDefinition());
            Grid.SetColumn((FrameworkElement)cards[i], i);
            metrics.Children.Add(cards[i]);
        }

        // MARK: Karty
        static Border Card(UIElement content, Color? accent = null) => new()
        {
            Child = content,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            BorderBrush = accent is Color c ? Ui.Brush(c, 0.35) : Ui.Resource("CardStrokeColorDefaultBrush"),
            Background = Ui.Resource("CardBackgroundFillColorDefaultBrush"),
        };
        static StackPanel SongLine(string label, Song song)
        {
            var panel = new StackPanel { Spacing = 1 };
            panel.Children.Add(new TextBlock { Text = label, Foreground = Ui.Secondary, FontSize = 12 });
            var line = new TextBlock { TextWrapping = TextWrapping.Wrap };
            line.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = song.Title, FontWeight = FontWeights.SemiBold });
            line.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = " · " + (string.IsNullOrWhiteSpace(song.Author) ? L("Autor nieznany") : song.Author) });
            panel.Children.Add(line);
            return panel;
        }
        static Grid Head(string reason, UIElement right) =>
            Ui.Columns(8, (new TextBlock { Text = reason, TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold }, -1), (right, 0));
        static bool Matches(Song song, string filter) =>
            filter.Length == 0 || TextFold.Fold(song.Title).Contains(filter) || TextFold.Fold(song.Author).Contains(filter);

        var duplicatesList = new StackPanel { Spacing = 10 };
        var chordsList = new StackPanel { Spacing = 10 };
        var collisionsList = new StackPanel { Spacing = 8 };
        var allList = new StackPanel { Spacing = 2 };
        static TextBlock Empty(string text) => new() { Text = text, Foreground = Ui.Secondary, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(40) };
        void RenderLists(string filter)
        {
            duplicatesList.Children.Clear();
            foreach (var record in report.DuplicateRecords.Where(r => Matches(r.PrimarySong, filter) || Matches(r.DuplicateSong, filter)))
            {
                var toggle = new CheckBox { Content = L("Pomiń ten duplikat"), IsChecked = duplicateSkips.GetValueOrDefault(record.Id, record.ShouldSkipDuplicate) };
                var second = new ContentControl();
                void Render() => second.Content = SongLine(toggle.IsChecked == true ? L("Wersja zduplikowana (pomijana):") : L("Wersja zduplikowana (zostanie dodana):"), record.DuplicateSong);
                toggle.Click += (_, _) => { duplicateSkips[record.Id] = toggle.IsChecked == true; Render(); Refresh(); };
                Render();
                var card = new StackPanel { Spacing = 6 };
                card.Children.Add(Head(record.Reason, Ui.Badge(L("Zgodność: {0}%", record.SimilarityScore), Ui.Orange, 11)));
                card.Children.Add(toggle);
                card.Children.Add(SongLine(L("Wersja główna (zachowywana):"), record.PrimarySong));
                card.Children.Add(second);
                duplicatesList.Children.Add(Card(card));
            }
            if (duplicatesList.Children.Count == 0) duplicatesList.Children.Add(Empty(L("Brak wykrytych duplikatów")));

            chordsList.Children.Clear();
            foreach (var song in withChords.Where(s => Matches(s, filter)))
            {
                var card = new StackPanel { Spacing = 6 };
                var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                title.Children.Add(new TextBlock { Text = "🎸", VerticalAlignment = VerticalAlignment.Center });
                title.Children.Add(new TextBlock { Text = song.Title, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
                if (song.Key.Length > 0) title.Children.Add(Ui.Badge(L("Tonacja: {0}", song.Key), Ui.Orange, 10));
                card.Children.Add(title);
                card.Children.Add(new Border
                {
                    Child = new TextBlock { Text = string.Join("\n", song.Chords!.Split('\n').Take(4)), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11, Foreground = Ui.Secondary },
                    Padding = new Thickness(6), CornerRadius = new CornerRadius(4), Background = Ui.Resource("SolidBackgroundFillColorTertiaryBrush"),
                });
                chordsList.Children.Add(Card(card, Ui.Orange));
            }
            if (chordsList.Children.Count == 0) chordsList.Children.Add(Empty(L("Brak opracowań chwytów spełniających filtr.")));

            collisionsList.Children.Clear();
            foreach (var record in report.ExistingCollisions.Where(r => Matches(r.DuplicateSong, filter)))
            {
                var toggle = new CheckBox { Content = L("Pomiń (jest w bibliotece)"), IsChecked = collisionSkips.GetValueOrDefault(record.Id, record.ShouldSkipDuplicate) };
                toggle.Click += (_, _) => { collisionSkips[record.Id] = toggle.IsChecked == true; Refresh(); };
                var card = new StackPanel { Spacing = 4 };
                card.Children.Add(Head("⚠ " + record.PrimarySong.Title, toggle));
                card.Children.Add(new TextBlock { Text = record.Reason, Foreground = Ui.Secondary, TextWrapping = TextWrapping.Wrap });
                collisionsList.Children.Add(Card(card, Ui.Orange));
            }
            if (collisionsList.Children.Count == 0) collisionsList.Children.Add(Empty(L("Brak elementów do wyświetlenia")));

            allList.Children.Clear();
            foreach (var song in report.UniqueSongs.Where(s => Matches(s, filter)))
            {
                var info = new StackPanel { Spacing = 2 };
                var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                title.Children.Add(new TextBlock { Text = song.Title, FontWeight = FontWeights.SemiBold });
                if (song.HasChords) title.Children.Add(new TextBlock { Text = "🎸", FontSize = 11, VerticalAlignment = VerticalAlignment.Center });
                if (song.Key.Length > 0) title.Children.Add(Ui.Badge(song.Key, Ui.Orange, 10));
                info.Children.Add(title);
                info.Children.Add(new TextBlock { Text = song.Author.Length == 0 ? L("Autor nieznany") : song.Author, FontSize = 11, Foreground = Ui.Secondary });
                allList.Children.Add(new Border
                {
                    Child = Ui.Columns(8, (info, -1), (new TextBlock { Text = L("{0} slajdów", song.Slides.Count), FontSize = 11, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center }, 0)),
                    Padding = new Thickness(8, 6, 8, 6),
                    BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"),
                    BorderThickness = new Thickness(0, 0, 0, 1),
                });
            }
            if (allList.Children.Count == 0) allList.Children.Add(Empty(L("Brak elementów do wyświetlenia")));
        }

        // MARK: Zakładki i filtr
        var pages = new List<(string Title, StackPanel List)>
        {
            (L("Wykryte duplikaty ({0})", report.DuplicateRecords.Count), duplicatesList),
            (L("Chwyty gitarowe ({0})", withChords.Count), chordsList),
        };
        if (report.ExistingCollisions.Count > 0) pages.Add((L("Kolizje z bazą ({0})", report.ExistingCollisions.Count), collisionsList));
        pages.Add((L("Wszystkie do dodania ({0})", report.UniqueSongs.Count), allList));
        var tabButtons = new StackPanel { Orientation = Orientation.Horizontal };
        var content = new ScrollViewer { Height = 330, Padding = new Thickness(0, 0, 12, 0) };
        var buttons = new List<ToggleButton>();
        void Select(int index)
        {
            for (var i = 0; i < buttons.Count; i++) buttons[i].IsChecked = i == index;
            content.Content = pages[index].List;
            content.ChangeView(null, 0, null, true);
        }
        for (var i = 0; i < pages.Count; i++)
        {
            var index = i;
            var button = new ToggleButton
            {
                Content = pages[i].Title,
                CornerRadius = new CornerRadius(i == 0 ? 4 : 0, i == pages.Count - 1 ? 4 : 0, i == pages.Count - 1 ? 4 : 0, i == 0 ? 4 : 0),
            };
            button.Click += (_, _) => Select(index);
            buttons.Add(button);
            tabButtons.Children.Add(button);
        }
        var filterBox = new TextBox { PlaceholderText = L("Filtruj listę..."), Width = 180 };
        filterBox.TextChanged += (_, _) => RenderLists(TextFold.Fold(filterBox.Text.Trim()));
        var filter = Ui.Columns(6, (Ui.Icon(Glyphs.Search, 12), 0), (filterBox, 0));
        RenderLists("");
        // Pierwsza zakładka z czymś do decyzji: duplikaty albo kolizje.
        Select(report.DuplicateRecords.Count > 0 || report.ExistingCollisions.Count == 0 ? 0 : pages.FindIndex(p => p.List == collisionsList));
        Refresh();

        var body = new StackPanel { Spacing = 12, Width = 880 };
        body.Children.Add(metrics);
        body.Children.Add(Ui.Columns(10, (new ScrollViewer { Content = tabButtons, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled }, -1), (filter, 0)));
        body.Children.Add(new Border { Child = content, BorderThickness = new Thickness(0, 1, 0, 1), BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"), Padding = new Thickness(0, 10, 0, 10) });
        body.Children.Add(summary);
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        title.Children.Add(Ui.Icon(Glyphs.Download, 20, Ui.Blue));
        title.Children.Add(new TextBlock { Text = L("Podsumowanie importu i deduplikacji pieśni"), FontSize = 18, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        dialog.Title = title;
        dialog.Content = body;
        return await Dialogs.ShowAsync(window, dialog) == ContentDialogResult.Primary ? Commit() : null;
    }
}
