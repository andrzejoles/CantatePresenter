using CantatePresenter.Core.Input;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.UI;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Dolny pasek skrótów jak ShortcutLegendBarView w macOS: ikona, klawisz i podpis, kliknięcie wykonuje akcję.
/// Wysokość (bottomBarHeight, 52–160) zmienia się przyciskami po prawej albo przeciąganiem uchwytu nad paskiem;
/// ikony, klawisze i podpisy rosną razem z nią.
/// </summary>
public sealed class ShortcutBar : Grid
{
    private readonly MainWindow window;
    private readonly ResizeHandle handle = new();
    private readonly Grid bar = new();
    private double dragStartY;
    private double dragStartHeight;
    private bool dragging;

    public ShortcutBar(MainWindow window)
    {
        this.window = window;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        // Uchwyt: linia podziału z „kapsułką”, przeciąganie zmienia wysokość paska.
        handle.Children.Add(new Border { Height = 1, Background = Ui.Resource("DividerStrokeColorDefaultBrush"), VerticalAlignment = VerticalAlignment.Center });
        handle.Children.Add(new Border { Width = 44, Height = 4, CornerRadius = new CornerRadius(2), Background = Ui.Brush(Ui.Gray, 0.45) });
        ToolTipService.SetToolTip(handle, L("Zmień wysokość paska"));
        handle.PointerPressed += (_, e) =>
        {
            dragging = handle.CapturePointer(e.Pointer);
            dragStartY = e.GetCurrentPoint(window.Content).Position.Y;
            dragStartHeight = Services.Library.Settings.BottomBarHeight;
        };
        handle.PointerMoved += (_, e) =>
        {
            if (!dragging) return;
            var delta = (e.GetCurrentPoint(window.Content).Position.Y - dragStartY) / window.UiScale;
            var height = Math.Clamp(dragStartHeight - delta, 52, 160);
            if (Math.Abs(height - Services.Library.Settings.BottomBarHeight) >= 2)
            {
                Services.Library.Settings.BottomBarHeight = height;
                Render();
            }
        };
        void EndDrag(object sender, PointerRoutedEventArgs e)
        {
            if (!dragging) return;
            dragging = false;
            handle.ReleasePointerCapture(e.Pointer);
            Services.Library.SaveSettings();
        }
        handle.PointerReleased += EndDrag;
        handle.PointerCaptureLost += (_, _) => { if (dragging) { dragging = false; Services.Library.SaveSettings(); } };
        Children.Add(handle);
        SetRow(bar, 1);
        Children.Add(bar);
        Render();
    }

    private static string KeyCap(int code) => KeyboardRouter.KeyName(code) switch
    {
        "Spacja" => L("Spacja"),
        "Enter" => "↵ Enter",
        "Page Up" => "PgUp",
        "Page Down" => "PgDn",
        var name => name,
    };

    public void Render()
    {
        var library = Services.Library;
        var s = library.Settings;
        var shortcuts = s.Shortcuts;
        var height = s.BottomBarHeight;
        var factor = Math.Clamp(height / 70.0, 0.75, 2.4);
        bar.Children.Clear();
        bar.ColumnDefinitions.Clear();
        bar.Height = height;
        bar.Background = Ui.Resource("SolidBackgroundFillColorBaseBrush");
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var items = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Math.Max(10, Math.Round(16 * factor)), Padding = new Thickness(12, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
        var hint = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Math.Max(4, Math.Round(6 * factor)), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
        hint.Children.Add(Ui.Icon(Glyphs.Keyboard, Math.Round(12 * factor)));
        hint.Children.Add(new TextBlock { Text = L("SKRÓTY:"), FontSize = Math.Round(10 * factor), FontWeight = FontWeights.Bold, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center });
        items.Children.Add(hint);
        void Separator() => items.Children.Add(Ui.Divider(vertical: true, length: Math.Max(18, Math.Round(24 * factor))));
        void Item(string glyph, Color color, string key, string label, Action? action, bool active = false, Color? activeColor = null)
            => items.Children.Add(ShortcutItem(glyph, color, key, label, factor, action, active, activeColor ?? Ui.Red));

        Separator();
        Item(Glyphs.ChevronLeft, Ui.Blue, KeyCap(shortcuts.PrevSlideKey), L("Poprzedni"), library.PrevSlide);
        Item(Glyphs.ChevronRight, Ui.Blue, KeyCap(shortcuts.NextSlideKey), L("Następny"), library.NextSlide);
        Separator();
        Item(Glyphs.Music, Ui.Orange, "R", L("Refren"), library.JumpToChorus);
        Item(Glyphs.List, Ui.Purple, "1 – 9", L("Zwrotka"), null);
        Separator();
        Item(Glyphs.Moon, library.IsBlackScreen ? Ui.Red : Colors.Gray, KeyCap(shortcuts.BlackScreenKey), L("Czarny"), library.ToggleBlackScreen, library.IsBlackScreen);
        Item(Glyphs.Hide, library.IsClearText ? Ui.Orange : Colors.Gray, KeyCap(shortcuts.ClearTextKey), L("Czysty"), library.ToggleClearText, library.IsClearText, Ui.Orange);
        Separator();
        Item(Glyphs.PreviousSong, Ui.Teal, KeyCap(shortcuts.PrevSongKey), L("Poprz. pieśń"), library.PrevSongInPlan);
        Item(Glyphs.NextSong, Ui.Teal, KeyCap(shortcuts.NextSongKey), L("Nast. pieśń"), library.NextSongInPlan);
        Separator();
        Item(Glyphs.Play, Ui.Green, KeyCap(shortcuts.StartPresentationKey), L("Prezentuj"), () => { if (library.SelectedSong is { } song) library.Present(song); });
        Item(Glyphs.Bolt, Ui.Orange, "Ctrl T", L("Szybki tekst"), () => _ = window.QuickTextAsync());
        Item(Glyphs.Stop, Ui.Gray, KeyCap(shortcuts.StopPresentationKey), L("Standby"), library.StopLive);

        var scroll = new ScrollViewer
        {
            Content = items,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollMode = ScrollMode.Enabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollMode = ScrollMode.Disabled,
        };
        bar.Children.Add(scroll);

        // Regulacja wysokości po prawej: −, wartość (powrót do 72 px), +.
        var size = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(6, 0, 10, 0) };
        Button Small(UIElement content, string tip, Action action)
        {
            var b = new Button { Content = content, Padding = new Thickness(6, 2, 6, 3), MinWidth = 0, MinHeight = 0, FontSize = 11, AllowFocusOnInteraction = false };
            ToolTipService.SetToolTip(b, tip);
            b.Click += (_, _) => { action(); library.SaveSettings(); Render(); };
            return b;
        }
        size.Children.Add(Ui.Divider(vertical: true, length: Math.Max(18, Math.Round(24 * factor))));
        size.Children.Add(Small(Ui.Icon(Glyphs.ChevronDown, 10), L("Zmniejsz wysokość paska"), () => s.BottomBarHeight = Math.Max(52, height - 10)));
        size.Children.Add(Small(new TextBlock { Text = $"{Math.Round(height)}px", FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11 },
            L("Kliknij, aby przywrócić domyślną wysokość (72px)"), () => s.BottomBarHeight = 72));
        size.Children.Add(Small(Ui.Icon(Glyphs.ChevronUp, 10), L("Zwiększ wysokość paska"), () => s.BottomBarHeight = Math.Min(160, height + 10)));
        SetColumn(size, 1);
        bar.Children.Add(size);
    }

    private static Button ShortcutItem(string glyph, Color color, string key, string label, double factor, Action? action, bool active, Color activeColor)
    {
        var column = new StackPanel { Spacing = Math.Max(2, Math.Round(3 * factor)), HorizontalAlignment = HorizontalAlignment.Center, MinWidth = Math.Max(46, Math.Round(54 * factor)) };
        column.Children.Add(new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont, FontSize = Math.Round(14 * factor), Foreground = Ui.Brush(color), HorizontalAlignment = HorizontalAlignment.Center });
        column.Children.Add(new Border
        {
            Child = new TextBlock
            {
                Text = key, FontSize = Math.Round(11 * factor), FontWeight = FontWeights.Bold,
                Foreground = active ? Ui.Brush(Colors.White) : Ui.Resource("TextFillColorPrimaryBrush"),
            },
            Padding = new Thickness(Math.Max(4, Math.Round(6 * factor)), Math.Max(1, Math.Round(1 * factor)), Math.Max(4, Math.Round(6 * factor)), Math.Max(2, Math.Round(2 * factor))),
            CornerRadius = new CornerRadius(Math.Max(3, Math.Round(4 * factor))),
            BorderThickness = new Thickness(1),
            BorderBrush = active ? Ui.Brush(Colors.White, 0.6) : Ui.Brush(Ui.Gray, 0.45),
            Background = active ? Ui.Brush(activeColor) : Ui.Resource("ControlFillColorDefaultBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        column.Children.Add(new TextBlock
        {
            Text = label, FontSize = Math.Max(9, Math.Round(10 * factor)), HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = active ? Ui.Brush(activeColor) : Ui.Secondary, MaxLines = 1, TextTrimming = TextTrimming.CharacterEllipsis,
        });
        var button = new Button
        {
            Content = column,
            Padding = new Thickness(4, 2, 4, 2),
            Background = Ui.Brush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Center,
            IsTabStop = false,
            AllowFocusOnInteraction = false,
        };
        button.Resources["ButtonBackground"] = Ui.Brush(Colors.Transparent);
        button.Resources["ButtonBackgroundPointerOver"] = Ui.Brush(Ui.Gray, 0.14);
        button.Resources["ButtonBackgroundPressed"] = Ui.Brush(Ui.Gray, 0.24);
        button.Resources["ButtonBackgroundDisabled"] = Ui.Brush(Colors.Transparent);
        button.Resources["ButtonBorderBrushDisabled"] = Ui.Brush(Colors.Transparent);
        ToolTipService.SetToolTip(button, action is null ? label : L("Kliknij lub naciśnij {0}", key));
        Ui.AutomationName(button, label);
        if (action is not null) button.Click += (_, _) => action();
        return button;
    }

    /// <summary>Uchwyt nad paskiem z kursorem zmiany wysokości (kursor ustawia tylko sam element).</summary>
    private sealed class ResizeHandle : Grid
    {
        public ResizeHandle()
        {
            Height = 8;
            Background = Ui.Brush(Colors.Transparent);
            ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.SizeNorthSouth);
        }
    }
}
