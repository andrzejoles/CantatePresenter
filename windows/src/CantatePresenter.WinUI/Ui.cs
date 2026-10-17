using CantatePresenter.Core.Text;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace CantatePresenter.WinUI;

/// <summary>Ikony Segoe Fluent Icons / MDL2 (odpowiedniki SF Symbols z macOS).</summary>
public static class Glyphs
{
    public const string Music = "";
    public const string Bolt = "";
    public const string Add = "";
    public const string Edit = "";
    public const string ImportExport = "";
    public const string Contact = "";
    public const string Globe = "";
    public const string Phone = "";
    public const string Settings = "";
    public const string Help = "";
    public const string FontDecrease = "";
    public const string FontIncrease = "";
    public const string Play = "";
    public const string Stop = "";
    public const string ArrowLeft = "";
    public const string ArrowRight = "";
    public const string ChevronLeft = "";
    public const string ChevronRight = "";
    public const string ChevronUp = "";
    public const string ChevronDown = "";
    public const string Moon = "";
    public const string Hide = "";
    public const string PreviousSong = "";
    public const string NextSong = "";
    public const string List = "";
    public const string Keyboard = "";
    public const string Search = "";
    public const string Clear = "";
    public const string Close = "";
    public const string Monitor = "";
    public const string Next = "";
    public const string Flag = "";
    public const string Refresh = "";
    public const string Delete = "";
    public const string AddTo = "";
    public const string FullScreen = "";
    public const string NewWindow = "";
    public const string Clock = "";
    public const string Person = "";
    public const string Sort = "";
    public const string Info = "";
    public const string Checklist = "";
    public const string Checkmark = "";
    public const string Rename = "";
    public const string Cloud = "";
    public const string Save = "";
    public const string Document = "";
    public const string Mic = "";
    public const string Warning = "";
    public const string Library = "";
    public const string Color = "";
    public const string Font = "";
    public const string Language = "";
    public const string Image = "";
    public const string Margins = "";
    public const string Copyright = "";
    public const string Zoom = "";
    public const string BottomBar = "";
    public const string Download = "";
    public const string Upload = "";
    public const string Undo = "";
}

/// <summary>Kolory i drobne elementy interfejsu wspólne dla okien (kolory systemowe jak w macOS).</summary>
public static class Ui
{
    public static readonly Color Blue = ColorHelper.FromArgb(255, 0x0A, 0x84, 0xFF);
    public static readonly Color Orange = ColorHelper.FromArgb(255, 0xFF, 0x95, 0x00);
    public static readonly Color Purple = ColorHelper.FromArgb(255, 0xAF, 0x52, 0xDE);
    public static readonly Color Teal = ColorHelper.FromArgb(255, 0x30, 0xB0, 0xC7);
    public static readonly Color Green = ColorHelper.FromArgb(255, 0x34, 0xC7, 0x59);
    public static readonly Color Red = ColorHelper.FromArgb(255, 0xFF, 0x3B, 0x30);
    public static readonly Color Pink = ColorHelper.FromArgb(255, 0xFF, 0x2D, 0x55);
    public static readonly Color Mint = ColorHelper.FromArgb(255, 0x00, 0xC7, 0xBE);
    public static readonly Color Brown = ColorHelper.FromArgb(255, 0xA2, 0x84, 0x5E);
    public static readonly Color Gray = ColorHelper.FromArgb(255, 0x8E, 0x8E, 0x93);
    public static readonly Color Yellow = ColorHelper.FromArgb(255, 0xE6, 0xB8, 0x00);
    public static readonly Color Indigo = ColorHelper.FromArgb(255, 0x58, 0x56, 0xD6);

    public static FontFamily SymbolFont => (FontFamily)Application.Current.Resources["SymbolThemeFontFamily"];

    public static Brush Resource(string key) => (Brush)Application.Current.Resources[key];

    public static SolidColorBrush Brush(Color color, double opacity = 1) =>
        new(ColorHelper.FromArgb((byte)Math.Round(color.A * opacity), color.R, color.G, color.B));

    /// <summary>Tekst drugorzędny (jak .secondary w macOS).</summary>
    public static Brush Secondary => Resource("TextFillColorSecondaryBrush");

    public static FontIcon Icon(string glyph, double size = 14, Color? color = null)
    {
        var icon = new FontIcon { Glyph = glyph, FontFamily = SymbolFont, FontSize = size };
        if (color is Color c) icon.Foreground = Brush(c);
        return icon;
    }

    /// <summary>Ikona z napisem; napis można ukryć (wąskie okno), zostaje wtedy jako podpowiedź.</summary>
    public static StackPanel Label(string glyph, string text, double iconSize = 14, Color? iconColor = null, double spacing = 8)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        panel.Children.Add(Icon(glyph, iconSize, iconColor));
        panel.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }

    /// <summary>Napis przy ikonie w przycisku z <see cref="Label"/> (do ukrywania w trybie kompaktowym).</summary>
    public static TextBlock? LabelText(Button button) => (button.Content as StackPanel)?.Children.OfType<TextBlock>().FirstOrDefault();

    public static Button Button(string glyph, string text, RoutedEventHandler click, string? tip = null, bool accent = false, Color? iconColor = null, bool showText = true)
    {
        var button = new Button { Content = showText ? Label(glyph, text, 14, iconColor) : Icon(glyph, 14, iconColor), Padding = new Thickness(10, 5, 10, 6) };
        if (accent) button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        button.Click += click;
        ToolTipService.SetToolTip(button, tip ?? text);
        AutomationName(button, text);
        return button;
    }

    public static void AutomationName(DependencyObject element, string name) =>
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(element, name);

    /// <summary>Przycisk w kolorze (jak .tint w macOS): tło i napis we wszystkich stanach.</summary>
    public static void Tint(Button button, Color background, Color? foreground = null)
    {
        var fg = Brush(foreground ?? Colors.White);
        button.Resources["ButtonBackground"] = Brush(background);
        button.Resources["ButtonBackgroundPointerOver"] = Brush(background, 0.88);
        button.Resources["ButtonBackgroundPressed"] = Brush(background, 0.75);
        button.Resources["ButtonForeground"] = fg;
        button.Resources["ButtonForegroundPointerOver"] = fg;
        button.Resources["ButtonForegroundPressed"] = fg;
        button.Resources["ButtonBorderBrush"] = Brush(background);
        button.Resources["ButtonBorderBrushPointerOver"] = Brush(background);
        button.Resources["ButtonBorderBrushPressed"] = Brush(background);
        button.Background = Brush(background);
        button.Foreground = fg;
        button.BorderBrush = Brush(background);
    }

    /// <summary>Przycisk z delikatnym zabarwieniem (np. pomarańczowy „Chwyty” z chwytami, zielony pilot).</summary>
    public static void SoftTint(Button button, Color color)
    {
        button.Resources["ButtonBackground"] = Brush(color, 0.16);
        button.Resources["ButtonBackgroundPointerOver"] = Brush(color, 0.24);
        button.Resources["ButtonBackgroundPressed"] = Brush(color, 0.32);
        button.Resources["ButtonBorderBrush"] = Brush(color, 0.5);
        button.Resources["ButtonBorderBrushPointerOver"] = Brush(color, 0.6);
        button.Background = Brush(color, 0.16);
        button.BorderBrush = Brush(color, 0.5);
    }

    /// <summary>Plakietka (tonacja, LIVE, 16:9): napis w kolorze na tle tego koloru z przezroczystością.</summary>
    public static Border Badge(string text, Color color, double fontSize = 11, bool solid = false, Thickness? padding = null)
    {
        return new Border
        {
            Child = new TextBlock { Text = text, FontSize = fontSize, FontWeight = FontWeights.Bold, Foreground = solid ? Brush(Colors.White) : Brush(color) },
            Background = Brush(color, solid ? 1 : 0.15),
            Padding = padding ?? new Thickness(6, 1, 6, 2),
            CornerRadius = new CornerRadius(4),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>Plakietka szara (jak .secondary.opacity(0.12)).</summary>
    public static Border MutedBadge(string text, double fontSize = 11)
    {
        return new Border
        {
            Child = new TextBlock { Text = text, FontSize = fontSize, FontWeight = FontWeights.SemiBold, Foreground = Secondary },
            Background = Brush(Gray, 0.16),
            Padding = new Thickness(6, 1, 6, 2),
            CornerRadius = new CornerRadius(4),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>Kropka statusu (LIVE, plan na żywo, Czarny/Czysty).</summary>
    public static Microsoft.UI.Xaml.Shapes.Ellipse Dot(Color color, double size = 8) =>
        new() { Width = size, Height = size, Fill = Brush(color), VerticalAlignment = VerticalAlignment.Center };

    /// <summary>Kolor plakietki rodzaju slajdu, jak badgeColorForType w macOS.</summary>
    public static Color SlideTypeColor(string type) => type switch
    {
        SlideTypes.Chorus => Orange,
        SlideTypes.Verse => Blue,
        SlideTypes.Bridge => Purple,
        SlideTypes.PreChorus => Teal,
        SlideTypes.Coda => Pink,
        SlideTypes.Interlude => Mint,
        SlideTypes.Ending => Brown,
        SlideTypes.Intro or SlideTypes.Outro => Gray,
        SlideTypes.Tag => Yellow,
        _ => Indigo,
    };

    public static Border SlideTypeBadge(string type, double fontSize = 11) =>
        Badge(SlideTypes.ShortBadge.GetValueOrDefault(type, "•"), SlideTypeColor(type), fontSize, solid: true, padding: new Thickness(5, 1, 5, 2));

    /// <summary>Linia podziału (Divider).</summary>
    public static Border Divider(bool vertical = false, double length = double.NaN) => new()
    {
        Background = Resource("DividerStrokeColorDefaultBrush"),
        Width = vertical ? 1 : length,
        Height = vertical ? length : 1,
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Nagłówek sekcji z ikoną (jak Label(…, systemImage:) w macOS).</summary>
    public static StackPanel Header(string glyph, string text, double size = 14)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.Add(Icon(glyph, size));
        panel.Children.Add(new TextBlock { Text = text, FontWeight = FontWeights.Bold, FontSize = size, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap });
        return panel;
    }

    /// <summary>Grupa ustawień z ramką i tytułem (jak GroupBox w macOS).</summary>
    public static StackPanel Group(string glyph, string title, out StackPanel body)
    {
        var outer = new StackPanel { Spacing = 6 };
        outer.Children.Add(Header(glyph, title, 13));
        body = new StackPanel { Spacing = 8 };
        outer.Children.Add(new Border
        {
            Child = body,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            BorderBrush = Resource("CardStrokeColorDefaultBrush"),
            Background = Resource("CardBackgroundFillColorDefaultBrush"),
        });
        return outer;
    }

    /// <summary>Opis pod polem (mały, drugorzędny).</summary>
    public static TextBlock Note(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = Secondary, FontSize = 12 };

    /// <summary>Kolumny o podanych szerokościach (gwiazdki dla wartości ≤ 0).</summary>
    public static Grid Columns(double spacing, params (UIElement Element, double Width)[] cells)
    {
        var grid = new Grid { ColumnSpacing = spacing };
        for (var i = 0; i < cells.Length; i++)
        {
            var (element, width) = cells[i];
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = width > 0 ? new GridLength(width) : width == 0 ? GridLength.Auto : new GridLength(-width, GridUnitType.Star),
            });
            Grid.SetColumn((FrameworkElement)element, i);
            grid.Children.Add(element);
        }
        return grid;
    }
}
