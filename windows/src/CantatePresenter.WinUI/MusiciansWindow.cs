using CantatePresenter.Core.Presentation;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Ekran dla muzyków (jak okno „Muzycy” w macOS): bieżący i następny slajd z chwytami nad tekstem, czcionka o stałej
/// szerokości, transpozycja (np. pod capo) i wielkość czcionki zapamiętane w ustawieniach.
/// </summary>
public sealed class MusiciansWindow : Window
{
    private static readonly Windows.UI.Color Chord = ColorHelper.FromArgb(255, 0xFF, 0x9F, 0x0A);
    private readonly Grid root = new() { Background = new SolidColorBrush(Colors.Black), Padding = new Thickness(16) };
    private readonly StackPanel body = new();
    private readonly TextBlock title = new() { FontSize = 22, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Colors.White), TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock meta = new() { FontSize = 14, Foreground = new SolidColorBrush(Colors.Gray) };
    private readonly TextBlock transposeValue = new() { Foreground = new SolidColorBrush(Colors.White), VerticalAlignment = VerticalAlignment.Center, MinWidth = 30, TextAlignment = TextAlignment.Center };

    public MusiciansWindow()
    {
        Title = L("Ekran dla muzyków");
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1100, 760));
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var header = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 0, 0, 8) };
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var titles = new StackPanel();
        titles.Children.Add(title);
        titles.Children.Add(meta);
        header.Children.Add(titles);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        Button Control(string text, Action action)
        {
            var button = new Button { Content = text, MinWidth = 40 };
            button.Click += (_, _) => { action(); Render(); };
            return button;
        }
        controls.Children.Add(new TextBlock { Text = L("Transpozycja"), Foreground = new SolidColorBrush(Colors.Gray), VerticalAlignment = VerticalAlignment.Center });
        controls.Children.Add(Control("−", () => Services.Library.UpdateSettings(s => s.MusicianTranspose = (s.MusicianTranspose - 1) % 12)));
        controls.Children.Add(transposeValue);
        controls.Children.Add(Control("+", () => Services.Library.UpdateSettings(s => s.MusicianTranspose = (s.MusicianTranspose + 1) % 12)));
        controls.Children.Add(new TextBlock { Text = L("Czcionka"), Foreground = new SolidColorBrush(Colors.Gray), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) });
        controls.Children.Add(Control("A−", () => Services.Library.UpdateSettings(s => s.MusicianFontSize -= 3)));
        controls.Children.Add(Control("A+", () => Services.Library.UpdateSettings(s => s.MusicianFontSize += 3)));
        Grid.SetColumn(controls, 1);
        header.Children.Add(controls);
        root.Children.Add(header);
        var scroll = new ScrollViewer { Content = body };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        Content = root;
        root.SizeChanged += (_, _) => Render();
        Services.Library.Changed += reason => DispatcherQueue.TryEnqueue(Render);
        Render();
    }

    public FrameworkElement ContentElement => root;

    private void Render()
    {
        var settings = Services.Library.Settings;
        var stage = MusicianStage.Make(Services.Library, settings.MusicianTranspose, s => Labels.Slide(s));
        transposeValue.Text = stage.Semitones > 0 ? $"+{stage.Semitones}" : stage.Semitones.ToString();
        title.Text = stage.SongTitle.Length > 0 ? stage.SongTitle : L("Ekran dla muzyków");
        var parts = new List<string>();
        if (stage.Key.Length > 0) parts.Add(L("Tonacja: {0}", stage.Key));
        if (stage.Current is not null) parts.Add($"{stage.Current.Label} · {stage.Position}");
        if (stage.IsBlackScreen) parts.Add(L("CZARNY EKRAN"));
        else if (stage.IsClearText) parts.Add(L("TEKST UKRYTY"));
        if (stage.Current is not null && !stage.HasChords) parts.Add(L("Brak chwytów dla tej pieśni"));
        parts.Add(DateTime.Now.ToString("HH:mm"));
        meta.Text = string.Join("   ", parts);
        body.Children.Clear();
        if (stage.Current is null)
        {
            body.Children.Add(new TextBlock { Text = L("Brak aktywnej prezentacji"), FontSize = 20, Foreground = new SolidColorBrush(Colors.Gray), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 120, 0, 0) });
            if (stage.NextSongTitle is string upcoming) body.Children.Add(new TextBlock { Text = L("Następnie: {0}", upcoming), FontSize = 18, Foreground = new SolidColorBrush(Colors.Gray), HorizontalAlignment = HorizontalAlignment.Center });
            return;
        }
        var size = FittedSize(stage, settings.MusicianFontSize);
        body.Children.Add(Block(stage.Current, size, 1));
        if (stage.Next is MusicianSlide next)
        {
            body.Children.Add(new TextBlock { Text = stage.NextSongTitle is string t ? L("Następnie: {0}", t) : L("Następny slajd"), Foreground = new SolidColorBrush(Colors.Gray), FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 18, 0, 4) });
            body.Children.Add(Block(next, size * 0.7, 0.6));
        }
    }

    /// <summary>Czcionka dopasowana do okna bez przewijania (jak okno „Muzycy” w macOS).</summary>
    private double FittedSize(MusicianStage stage, double preferred)
    {
        var width = Math.Max(200, root.ActualWidth - 32);
        var height = Math.Max(200, root.ActualHeight - 120);
        static double Rows(MusicianSlide slide) => slide.Lines.Sum(l => (l.Chords is null ? 0 : 1) + (l.Text.Length > 0 ? 1 : 0)) + 0.6 + (slide.BorrowedFrom is null ? 0 : 0.5);
        var slides = new[] { stage.Current, stage.Next }.OfType<MusicianSlide>().ToList();
        var longest = Math.Max(1, slides.SelectMany(s => s.Lines.SelectMany(l => new[] { (l.Chords ?? "").Length, l.Text.Length })).DefaultIfEmpty(1).Max());
        var widthFit = width / (longest * 0.6);
        var total = Rows(stage.Current!) * 1.3 + (stage.Next is null ? 0 : Rows(stage.Next) * 0.7 * 1.3 + 1.6);
        var heightFit = height / Math.Max(total, 1);
        return Math.Max(10, Math.Min(preferred, Math.Min(widthFit, heightFit)));
    }

    private static StackPanel Block(MusicianSlide slide, double size, double opacity)
    {
        var block = new StackPanel { Opacity = opacity };
        block.Children.Add(new TextBlock { Text = slide.Label, Foreground = new SolidColorBrush(Chord), FontWeight = FontWeights.Bold, FontSize = Math.Max(11, size * 0.45), Margin = new Thickness(0, 0, 0, 6) });
        var mono = new FontFamily("Cascadia Mono, Consolas, Courier New");
        foreach (var line in slide.Lines)
        {
            if (line.Chords is string chords) block.Children.Add(new TextBlock { Text = chords, FontFamily = mono, FontSize = size, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Chord), TextWrapping = TextWrapping.NoWrap });
            if (line.Text.Length > 0) block.Children.Add(new TextBlock { Text = line.Text, FontFamily = mono, FontSize = size, Foreground = new SolidColorBrush(Colors.White), TextWrapping = TextWrapping.NoWrap });
        }
        if (slide.BorrowedFrom is string borrowed) block.Children.Add(new TextBlock { Text = L("Chwyty jak w: {0}", borrowed), Foreground = new SolidColorBrush(Colors.Gray), FontSize = 13, Margin = new Thickness(0, 6, 0, 0) });
        return block;
    }
}
