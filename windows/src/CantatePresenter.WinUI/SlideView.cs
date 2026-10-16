using System.Globalization;
using CantatePresenter.Core.Presentation;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.Storage.Streams;
using Windows.UI;

namespace CantatePresenter.WinUI;

/// <summary>Obraz ekranu projekcji: to samo dla okna projekcji i podglądów (jak SlideTextView w macOS, N1).</summary>
public sealed record ScreenState(
    bool IsLive, bool IsBlackScreen, bool IsClearText, string Text, string? Notice,
    string FontFamily, bool IsBold, string TextColorHex, string BackgroundColorHex, bool HasShadow,
    string TextAlignment, string VerticalAlignment, double MarginPercent, double LineSpacingFactor, bool Dimmed = false)
{
    public static ScreenState FromLibrary(bool dimmed = false, string? textOverride = null)
    {
        var library = Services.Library;
        var s = library.Settings;
        var text = textOverride ?? library.CurrentLiveSlide?.Text ?? "";
        return new ScreenState(textOverride is not null || library.IsLive, textOverride is null && library.IsBlackScreen, textOverride is null && library.IsClearText,
            text, textOverride is null ? library.CurrentCopyrightNotice : null, s.FontFamily, s.IsBold, s.TextColorHex, s.BackgroundColorHex, s.HasShadow,
            s.TextAlignment, s.VerticalAlignment, s.MarginPercent, s.LineSpacingFactor, dimmed);
    }
}

/// <summary>Pomiar tekstu przez TextBlock poza ekranem (ta sama czcionka co na projektorze).</summary>
public sealed class TextMeasurer : ITextMeasurer
{
    public static readonly TextMeasurer Shared = new();
    private readonly TextBlock probe = new() { TextWrapping = TextWrapping.NoWrap };
    private readonly Dictionary<(string, string, double, bool), double> cache = [];

    public double Width(string text, string fontFamily, double size, bool bold)
    {
        var key = (text, fontFamily, Math.Round(size, 2), bold);
        if (cache.TryGetValue(key, out var cached)) return cached;
        probe.Text = text;
        probe.FontFamily = SlideView.Font(fontFamily);
        probe.FontSize = size;
        probe.FontWeight = bold ? FontWeights.Bold : FontWeights.Normal;
        probe.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        if (cache.Count > 20000) cache.Clear();
        return cache[key] = probe.DesiredSize.Width;
    }
}

public sealed class SlideView : Grid
{
    private const double StandbyWidth = 960;
    private static readonly List<WeakReference<TextBlock>> Clocks = [];
    private static DispatcherTimer? clockTimer;
    private readonly Viewbox viewbox = new() { Stretch = Stretch.Uniform };

    public SlideView()
    {
        Children.Add(viewbox);
        Background = new SolidColorBrush(Colors.Black);
        if (clockTimer is null)
        {
            clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            clockTimer.Tick += (_, _) =>
            {
                Clocks.RemoveAll(w => !w.TryGetTarget(out _));
                foreach (var weak in Clocks) if (weak.TryGetTarget(out var clock)) clock.Text = ClockText();
            };
            clockTimer.Start();
        }
    }

    public static FontFamily Font(string family) => new($"{family}, Helvetica Neue, Segoe UI, Arial");

    public static Color ParseColor(string hex, Color fallback)
    {
        var value = hex.TrimStart('#');
        if (value.Length == 6 && uint.TryParse(value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var rgb))
            return ColorHelper.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        return fallback;
    }

    private static string ClockText() => DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture);

    /// <summary>Rysuje ekran w rozmiarze ekranu docelowego i pomniejsza go (Viewbox), więc wiersze łamią się jak na projektorze.</summary>
    public void Render(ScreenState state, Size target)
    {
        var width = Math.Max(target.Width, 100);
        var height = Math.Max(target.Height, 100);
        var stage = new Grid { Width = width, Height = height };
        stage.Background = new SolidColorBrush(state.IsBlackScreen ? Colors.Black : ParseColor(state.BackgroundColorHex, Colors.Black));
        viewbox.Child = stage;
        if (state.IsBlackScreen) return;
        if (!state.IsLive)
        {
            Services.Trace("SlideView: plansza");
            stage.Children.Add(Standby(width, height));
            Services.Trace("SlideView: plansza gotowa");
            return;
        }
        if (state.IsClearText || state.Text.Trim().Length == 0) return;

        var size = AutoFit.OptimalFontSize(state.Text, width, height, TextMeasurer.Shared, state.FontFamily, state.IsBold, state.LineSpacingFactor, state.MarginPercent);
        var area = new Grid { Padding = new Thickness(width * state.MarginPercent, height * state.MarginPercent, width * state.MarginPercent, height * state.MarginPercent) };
        var alignment = state.TextAlignment switch { "left" => Microsoft.UI.Xaml.TextAlignment.Left, "right" => Microsoft.UI.Xaml.TextAlignment.Right, _ => Microsoft.UI.Xaml.TextAlignment.Center };
        var vertical = state.VerticalAlignment switch { "top" => VerticalAlignment.Top, "bottom" => VerticalAlignment.Bottom, _ => VerticalAlignment.Center };
        TextBlock Make(Color color) => new()
        {
            Text = state.Text,
            FontFamily = Font(state.FontFamily),
            FontSize = size,
            FontWeight = state.IsBold ? FontWeights.Bold : FontWeights.Normal,
            Foreground = new SolidColorBrush(color),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = alignment,
            VerticalAlignment = vertical,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            LineHeight = size * (1.2 + (state.LineSpacingFactor - 1)),
            Opacity = state.Dimmed ? 0.65 : 1,
        };
        if (state.HasShadow)
        {
            var shadow = Make(ColorHelper.FromArgb((byte)(state.Dimmed ? 100 : 215), 0, 0, 0));
            shadow.RenderTransform = new TranslateTransform { X = Math.Max(2, size / 40), Y = Math.Max(2, size / 40) };
            area.Children.Add(shadow);
        }
        area.Children.Add(Make(ParseColor(state.TextColorHex, Colors.White)));
        stage.Children.Add(area);

        if (state.Notice is string notice)
        {
            stage.Children.Add(new TextBlock
            {
                Text = notice,
                FontSize = height * 0.022,
                Foreground = new SolidColorBrush(ParseColor(state.TextColorHex, Colors.White)),
                Opacity = 0.75,
                TextAlignment = Microsoft.UI.Xaml.TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Bottom,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(width * 0.04, 0, width * 0.04, height * 0.012),
            });
        }
    }

    /// <summary>Plansza startowa jak data/standby.html w macOS: projekt na 960 px szerokości, powiększany do ekranu.</summary>
    private static UIElement Standby(double width, double height)
    {
        var designHeight = StandbyWidth * height / width;
        var page = new Grid
        {
            Width = StandbyWidth,
            Height = designHeight,
            Background = new RadialGradientBrush
            {
                Center = new Point(0.5, 0.4),
                GradientOrigin = new Point(0.5, 0.4),
                RadiusX = 0.8,
                RadiusY = 0.8,
                GradientStops =
                {
                    new GradientStop { Color = ColorHelper.FromArgb(255, 0x1E, 0x26, 0x40), Offset = 0 },
                    new GradientStop { Color = ColorHelper.FromArgb(255, 0x0D, 0x11, 0x1D), Offset = 0.7 },
                    new GradientStop { Color = ColorHelper.FromArgb(255, 0x07, 0x09, 0x0E), Offset = 1 },
                },
            },
        };
        var column = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Spacing = 20 };
        if (Services.ActiveLogo is Logo logo)
        {
            column.Children.Add(new Image { Source = LogoSource(logo), Width = 140, Height = 140, Margin = new Thickness(0, 0, 0, 8) });
        }
        column.Children.Add(new TextBlock
        {
            Text = "CantatePresenter", FontSize = 51, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0), EndPoint = new Point(1, 1),
                GradientStops =
                {
                    new GradientStop { Color = Colors.White, Offset = 0 },
                    new GradientStop { Color = ColorHelper.FromArgb(255, 0xCB, 0xD5, 0xE1), Offset = 0.6 },
                    new GradientStop { Color = ColorHelper.FromArgb(255, 0x94, 0xA3, 0xB8), Offset = 1 },
                },
            },
        });
        var badge = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        badge.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = new SolidColorBrush(ColorHelper.FromArgb(255, 0x10, 0xB9, 0x81)) });
        badge.Children.Add(new TextBlock { Text = Services.L("Wersja {0}", Services.Version), FontSize = 14, Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 0x94, 0xA3, 0xB8)) });
        column.Children.Add(new Border
        {
            Child = badge, Padding = new Thickness(16, 6, 16, 6), CornerRadius = new CornerRadius(30), HorizontalAlignment = HorizontalAlignment.Center,
            Background = new SolidColorBrush(ColorHelper.FromArgb(18, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(ColorHelper.FromArgb(36, 255, 255, 255)), BorderThickness = new Thickness(1),
        });
        page.Children.Add(column);

        var footer = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 35), Spacing = 8 };
        var clock = new TextBlock { Text = ClockText(), FontSize = 20, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Foreground = new SolidColorBrush(ColorHelper.FromArgb(217, 255, 255, 255)) };
        Clocks.Add(new WeakReference<TextBlock>(clock));
        footer.Children.Add(clock);
        footer.Children.Add(new TextBlock { Text = Services.L("GOTOWY DO PROJEKCJI • OCZEKIWANIE NA PREZENTACJĘ"), FontSize = 15, HorizontalAlignment = HorizontalAlignment.Center, Foreground = new SolidColorBrush(ColorHelper.FromArgb(115, 255, 255, 255)) });
        page.Children.Add(footer);
        page.Children.Add(new TextBlock
        {
            Text = Services.L("Autor: Andrzej Oles · we współpracy z Claude (Anthropic)"), FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 10), Foreground = new SolidColorBrush(ColorHelper.FromArgb(90, 255, 255, 255)),
        });
        return new Viewbox { Stretch = Stretch.Uniform, Child = page };
    }

    /// <summary>Nowy obraz dla każdego użycia: jednego źródła obrazu nie można dzielić między oknami (awaria XAML).</summary>
    public static SvgImageSource LogoSource(Logo logo)
    {
        var source = new SvgImageSource();
        _ = LoadSvgAsync(source, logo.Svg);
        return source;
    }

    private static async Task LoadSvgAsync(SvgImageSource source, string svg)
    {
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
        {
            writer.WriteString(svg);
            await writer.StoreAsync();
            await writer.FlushAsync();
            writer.DetachStream();
        }
        Services.Trace("SVG: wczytywanie");
        var status = await source.SetSourceAsync(stream);
        Services.Trace("SVG: " + status);
    }
}
