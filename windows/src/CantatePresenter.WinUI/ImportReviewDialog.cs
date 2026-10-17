using CantatePresenter.Core.Import;
using CantatePresenter.Core.Models;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Przegląd importu jak ImportReviewSheet w macOS i okno w wersji web: duplikaty wewnątrz importu i pieśni
/// o tym samym tytule w bibliotece; dla każdej decyzja „pomiń” (domyślnie jak w macOS).
/// </summary>
public static class ImportReviewDialog
{
    /// <summary>Pieśni do dodania albo null, gdy użytkownik anulował import.</summary>
    public static async Task<List<Song>?> ShowAsync(MainWindow window, ImportReport report)
    {
        var duplicateSkips = new Dictionary<string, bool>();
        var collisionSkips = new Dictionary<string, bool>();
        List<Song> Commit() => SongDeduplication.SongsToCommit(report, duplicateSkips, collisionSkips);

        var dialog = new ContentDialog
        {
            Title = L("Podsumowanie importu i deduplikacji pieśni"),
            PrimaryButtonText = L("Zaimportuj {0} pieśni", Commit().Count),
            CloseButtonText = L("Anuluj"),
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 760.0;
        var countValue = new TextBlock { Text = Commit().Count.ToString(), FontSize = 24, FontWeight = FontWeights.Bold };
        void Refresh()
        {
            var count = Commit().Count;
            countValue.Text = count.ToString();
            dialog.PrimaryButtonText = L("Zaimportuj {0} pieśni", count);
        }

        static StackPanel Metric(string title, UIElement value, string subtitle)
        {
            var panel = new StackPanel { Spacing = 2, MinWidth = 160 };
            panel.Children.Add(new TextBlock { Text = title, Opacity = 0.7, FontSize = 12 });
            panel.Children.Add(value);
            panel.Children.Add(new TextBlock { Text = subtitle, Opacity = 0.7, FontSize = 12 });
            return panel;
        }
        static TextBlock Number(int value) => new() { Text = value.ToString(), FontSize = 24, FontWeight = FontWeights.Bold };
        static StackPanel SongLine(string label, Song song)
        {
            var panel = new StackPanel { Spacing = 1 };
            panel.Children.Add(new TextBlock { Text = label, Opacity = 0.7, FontSize = 12 });
            var line = new TextBlock { TextWrapping = TextWrapping.Wrap };
            line.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = song.Title, FontWeight = FontWeights.SemiBold });
            line.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = " · " + (string.IsNullOrWhiteSpace(song.Author) ? L("Autor nieznany") : song.Author) });
            panel.Children.Add(line);
            return panel;
        }
        static Border Card(UIElement content, bool warning = false) => new()
        {
            Child = content,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[warning ? "SystemFillColorCautionBrush" : "CardStrokeColorDefaultBrush"],
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
        };
        static Grid Head(string reason, UIElement right)
        {
            var grid = new Grid { ColumnSpacing = 8 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.Children.Add(new TextBlock { Text = reason, TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold });
            Grid.SetColumn((FrameworkElement)right, 1);
            grid.Children.Add(right);
            return grid;
        }

        var body = new StackPanel { Spacing = 10 };
        var metrics = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        metrics.Children.Add(Metric(L("Wczytano z pliku"), Number(report.TotalScanned), L("utworów")));
        metrics.Children.Add(Metric(L("Wykryte duplikaty"), Number(report.DuplicateRecords.Count), L("pominięte")));
        metrics.Children.Add(Metric(L("Do zaimportowania"), countValue, L("unikalnych pieśni")));
        body.Children.Add(metrics);

        if (report.DuplicateRecords.Count > 0)
        {
            body.Children.Add(new TextBlock { Text = L("Wykryte duplikaty ({0})", report.DuplicateRecords.Count), FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 6, 0, 0) });
            foreach (var record in report.DuplicateRecords)
            {
                var toggle = new CheckBox { Content = L("Pomiń ten duplikat"), IsChecked = record.ShouldSkipDuplicate };
                var second = new ContentControl();
                void Render() => second.Content = SongLine(toggle.IsChecked == true ? L("Wersja zduplikowana (pomijana):") : L("Wersja zduplikowana (zostanie dodana):"), record.DuplicateSong);
                toggle.Click += (_, _) => { duplicateSkips[record.Id] = toggle.IsChecked == true; Render(); Refresh(); };
                Render();
                var card = new StackPanel { Spacing = 6 };
                card.Children.Add(Head(record.Reason, new TextBlock { Text = L("Zgodność: {0}%", record.SimilarityScore), Opacity = 0.8, FontSize = 12 }));
                card.Children.Add(toggle);
                card.Children.Add(SongLine(L("Wersja główna (zachowywana):"), record.PrimarySong));
                card.Children.Add(second);
                body.Children.Add(Card(card));
            }
        }
        if (report.ExistingCollisions.Count > 0)
        {
            body.Children.Add(new TextBlock { Text = L("Kolizje z bazą ({0})", report.ExistingCollisions.Count), FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 6, 0, 0) });
            foreach (var record in report.ExistingCollisions)
            {
                var toggle = new CheckBox { Content = L("Pomiń (jest w bibliotece)"), IsChecked = record.ShouldSkipDuplicate };
                toggle.Click += (_, _) => { collisionSkips[record.Id] = toggle.IsChecked == true; Refresh(); };
                var card = new StackPanel { Spacing = 4 };
                card.Children.Add(Head("⚠ " + record.PrimarySong.Title, toggle));
                card.Children.Add(new TextBlock { Text = record.Reason, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
                body.Children.Add(Card(card, warning: true));
            }
        }

        dialog.Content = new ScrollViewer { Content = body, MaxHeight = 560, Padding = new Thickness(0, 0, 14, 0) };
        return await Dialogs.ShowAsync(window, dialog) == ContentDialogResult.Primary ? Commit() : null;
    }
}
