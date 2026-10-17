using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Models;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Wyszukiwarka chwytów (ChordsSearchSheet w macOS): opracowania z wbudowanej bazy i chwyty samej pieśni,
/// podgląd z transpozycją i „Zastosuj chwyty do pieśni”.
/// </summary>
public static class ChordsDialog
{
    public static async Task ShowAsync(MainWindow window, Song song, Action<string, string> apply)
    {
        var query = new TextBox { Text = song.Title, PlaceholderText = L("Wpisz tytuł pieśni lub słowa..."), VerticalAlignment = VerticalAlignment.Center };
        var search = new Button { Content = L("Szukaj"), FontWeight = FontWeights.SemiBold };
        Ui.Tint(search, Ui.Orange);
        var countLabel = new TextBlock { FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Ui.Secondary };
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single };
        var empty = new StackPanel { Spacing = 12, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(20) };
        empty.Children.Add(new FontIcon { Glyph = Glyphs.List, FontFamily = Ui.SymbolFont, FontSize = 32, Foreground = Ui.Secondary, Opacity = 0.5 });
        empty.Children.Add(new TextBlock { Text = L("Nie znaleziono opracowań. Wpisz inny tytuł albo dodaj chwyty w edytorze pieśni."), FontSize = 12, Foreground = Ui.Secondary, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
        var left = new Grid { Width = 300 };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition());
        left.Children.Add(new Border { Child = countLabel, Padding = new Thickness(12, 8, 12, 8), Background = Ui.Resource("SubtleFillColorSecondaryBrush") });
        Grid.SetRow(list, 1);
        Grid.SetRow(empty, 1);
        left.Children.Add(list);
        left.Children.Add(empty);

        var steps = 0;
        ChordsResult? selected = null;
        var preview = new TextBlock { FontFamily = new FontFamily("Consolas"), FontSize = 13, IsTextSelectionEnabled = true, LineHeight = 20, Padding = new Thickness(16) };
        var stepsLabel = new TextBlock { FontWeight = FontWeights.Bold, MinWidth = 28, TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var reset = new HyperlinkButton { Content = L("Reset"), Visibility = Visibility.Collapsed, Padding = new Thickness(4, 0, 4, 0) };
        string PreviewSheet() => selected is null ? "" : ChordTransposer.Transpose(selected.ChordsSheet, steps);
        void Render()
        {
            stepsLabel.Text = steps == 0 ? "0" : steps > 0 ? $"+{steps}" : steps.ToString();
            reset.Visibility = steps != 0 ? Visibility.Visible : Visibility.Collapsed;
            preview.Text = PreviewSheet();
        }
        var minus = new Button { Content = "♭ -1", Padding = new Thickness(8, 3, 8, 4) };
        minus.Click += (_, _) => { steps--; Render(); };
        var plus = new Button { Content = "♯ +1", Padding = new Thickness(8, 3, 8, 4) };
        plus.Click += (_, _) => { steps++; Render(); };
        reset.Click += (_, _) => { steps = 0; Render(); };
        var transposition = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        transposition.Children.Add(new TextBlock { Text = L("Transpozycja:"), FontWeight = FontWeights.SemiBold, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
        transposition.Children.Add(minus);
        transposition.Children.Add(stepsLabel);
        transposition.Children.Add(plus);
        transposition.Children.Add(reset);
        ContentDialog? dialog = null;
        var applyButton = Ui.Button(Glyphs.Checkmark, L("Zastosuj chwyty do pieśni"), (_, _) =>
        {
            if (selected is null) return;
            apply(PreviewSheet(), selected.Key);
            dialog?.Hide();
        });
        Ui.Tint(applyButton, Ui.Green);
        applyButton.FontWeight = FontWeights.Bold;
        var toolbar = new Border
        {
            Child = Ui.Columns(12, (transposition, -1), (applyButton, 0)),
            Padding = new Thickness(14, 8, 14, 8),
            Background = Ui.Resource("SubtleFillColorSecondaryBrush"),
        };
        var right = new Grid();
        right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        right.RowDefinitions.Add(new RowDefinition());
        right.Children.Add(toolbar);
        var previewScroll = new ScrollViewer { Content = preview, Background = Ui.Resource("SolidBackgroundFillColorTertiaryBrush"), HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetRow(previewScroll, 1);
        right.Children.Add(previewScroll);
        var hint = new TextBlock { Text = L("Wybierz opracowanie z listy po lewej stronie, aby podejrzeć chwyty i dokonać transpozycji."), Foreground = Ui.Secondary, TextWrapping = TextWrapping.Wrap, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(20) };
        Grid.SetRowSpan(hint, 2);
        right.Children.Add(hint);

        void Select(ChordsResult? result)
        {
            selected = result;
            steps = 0;
            toolbar.Visibility = previewScroll.Visibility = result is null ? Visibility.Collapsed : Visibility.Visible;
            hint.Visibility = result is null ? Visibility.Visible : Visibility.Collapsed;
            Render();
        }
        List<ChordsResult> results = [];
        void Run()
        {
            results = [];
            if (song.HasChords) results.Add(new ChordsResult(song.Title, song.Author, song.Key, song.Chords!, L("Chwyty tej pieśni")));
            results.AddRange(ChordsCatalog.Search(query.Text));
            list.Items.Clear();
            foreach (var result in results)
            {
                var item = new StackPanel { Spacing = 3, Padding = new Thickness(0, 4, 0, 4) };
                var top = Ui.Columns(6, (new TextBlock { Text = result.Title, FontWeight = FontWeights.Bold, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis }, -1),
                    (result.Key.Length > 0 ? Ui.Badge(result.Key, Ui.Orange, 10) : new Border(), 0));
                item.Children.Add(top);
                item.Children.Add(Ui.Columns(6, (new TextBlock { Text = result.Artist, FontSize = 11, Foreground = Ui.Secondary, TextTrimming = TextTrimming.CharacterEllipsis }, -1),
                    (new TextBlock { Text = result.Source, FontSize = 10, Foreground = Ui.Secondary, Opacity = 0.8 }, 0)));
                list.Items.Add(new ListViewItem { Content = item, Tag = result });
            }
            countLabel.Text = L("Znalezione opracowania ({0})", results.Count);
            empty.Visibility = results.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            if (results.Count > 0) list.SelectedIndex = 0;
            else Select(null);
        }
        list.SelectionChanged += (_, _) => Select((list.SelectedItem as ListViewItem)?.Tag as ChordsResult);
        search.Click += (_, _) => Run();
        query.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) { e.Handled = true; Run(); } };

        var searchBar = Ui.Columns(10, (Ui.Icon(Glyphs.Search, 14), 0), (query, -1), (Dictation.Button(query, DictationMode.Replace, L("Powiedz tytuł pieśni...")), 0), (search, 0));
        var split = new Grid { Height = 440, ColumnSpacing = 0 };
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        split.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        split.ColumnDefinitions.Add(new ColumnDefinition());
        split.Children.Add(left);
        var divider = Ui.Divider(vertical: true);
        divider.VerticalAlignment = VerticalAlignment.Stretch;
        Grid.SetColumn(divider, 1);
        split.Children.Add(divider);
        Grid.SetColumn(right, 2);
        split.Children.Add(right);
        var body = new StackPanel { Spacing = 12, Width = 860 };
        body.Children.Add(Ui.Note(L("Szukanie akordów dla: „{0}” w bibliotece chwytów i w samej pieśni", song.Title)));
        body.Children.Add(searchBar);
        body.Children.Add(new Border { Child = split, BorderThickness = new Thickness(1), BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"), CornerRadius = new CornerRadius(8) });

        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        title.Children.Add(new TextBlock { Text = "🎸", FontSize = 20, VerticalAlignment = VerticalAlignment.Center });
        title.Children.Add(new TextBlock { Text = L("Wyszukiwarka chwytów gitarowych i tabulatur"), FontSize = 18, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        dialog = new ContentDialog { Title = title, Content = body, CloseButtonText = L("Zamknij") };
        dialog.Resources["ContentDialogMaxWidth"] = 940.0;
        Run();
        await Dialogs.ShowAsync(window, dialog);
    }
}
