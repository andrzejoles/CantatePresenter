using CantatePresenter.Core.Models;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;
using Windows.UI;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Prawy panel: ekran na żywo, sterowanie, podgląd następnego slajdu, ekrany i projektor (LiveOutputView w macOS).</summary>
public sealed partial class MainWindow
{
    private readonly SlideView livePreview = new();
    private readonly SlideView nextPreview = new();
    // Ramki podglądów istnieją przez cały czas życia okna (element może mieć tylko jednego rodzica).
    private Grid? liveFrame;
    private Border? liveFrameBorder;
    private TextBlock? liveOverlay;
    private Grid? nextFrame;
    private Border? nextFrameBorder;
    private Border? nextLabel;
    private StackPanel? nextPlaceholder;

    private Size TargetSize()
    {
        if (presentation.IsOpen && !presentation.IsWindowed) return presentation.TargetSize;
        var screen = Screens.Target();
        return screen is null ? new Size(1920, 1080) : new Size(screen.Bounds.Width, screen.Bounds.Height);
    }

    /// <summary>Proporcje ekranu jak ScreenManager.formattedAspectRatio w macOS.</summary>
    public static string AspectRatio(Size size)
    {
        var ratio = size.Width / Math.Max(1, size.Height);
        if (Math.Abs(ratio - 16.0 / 9) < 0.03) return "16:9";
        if (Math.Abs(ratio - 16.0 / 10) < 0.08) return "16:10";
        if (Math.Abs(ratio - 4.0 / 3) < 0.03) return "4:3";
        if (Math.Abs(ratio - 21.0 / 9) < 0.08) return "21:9";
        if (Math.Abs(ratio - 5.0 / 4) < 0.03) return "5:4";
        return ratio.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + ":1";
    }

    /// <summary>Nagłówek sekcji: ikona, tytuł (zawija się w wąskim panelu), proporcje ekranu i stan po prawej.</summary>
    private static Grid SectionHead(string glyph, string title, string ratio, UIElement right)
    {
        var text = new TextBlock { Text = title, FontWeight = FontWeights.Bold, FontSize = 14, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
        return Ui.Columns(6, (Ui.Icon(glyph, 14), 0), (text, -1), (Ui.MutedBadge(ratio, 10), 0), (right, 0));
    }

    private void RenderRight()
    {
        rightPanel.Children.Clear();
        // Odstępy jak w macOS: 6 w sekcji, 14 między sekcjami. Stałe ramki podglądów idą prosto do panelu,
        // który jest czyszczony w całości (element XAML może mieć tylko jednego rodzica).
        void Add(FrameworkElement element, double top)
        {
            element.Margin = new Thickness(0, rightPanel.Children.Count == 0 ? 0 : top, 0, 0);
            rightPanel.Children.Add(element);
        }
        var target = TargetSize();
        var ratio = AspectRatio(target);
        var width = rightPanelWidth > 0 ? Math.Clamp(rightPanelWidth - 30, 200, 640) : 320.0;
        var height = width * target.Height / target.Width;

        // MARK: Ekran na żywo

        UIElement state;
        if (library.IsLive)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            row.Children.Add(Ui.Dot(Ui.Red));
            row.Children.Add(new TextBlock { Text = L("LIVE"), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Red) });
            state = new Border { Child = row, Padding = new Thickness(6, 2, 6, 2), CornerRadius = new CornerRadius(4), Background = Ui.Brush(Ui.Red, 0.12), VerticalAlignment = VerticalAlignment.Center };
        }
        else
        {
            state = Ui.MutedBadge(L("OFF AIR"), 11);
        }
        Add(SectionHead(Glyphs.Monitor, L("Ekran na żywo"), ratio, state), 0);

        livePreview.Width = width;
        livePreview.Height = height;
        livePreview.Render(ScreenState.FromLibrary(), target);
        if (liveFrame is null)
        {
            liveOverlay = new TextBlock { FontSize = 12, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            liveFrame = new Grid();
            liveFrame.Children.Add(livePreview);
            liveFrame.Children.Add(liveOverlay);
            liveFrameBorder = new Border { Child = liveFrame, CornerRadius = new CornerRadius(8), HorizontalAlignment = HorizontalAlignment.Left };
        }
        // Napis na podglądzie przy czarnym ekranie i ukrytym tekście (jak w macOS).
        liveOverlay!.Text = !library.IsLive ? "" : library.IsBlackScreen ? L("CZARNY EKRAN") : library.IsClearText ? L("TEKST UKRYTY") : "";
        liveOverlay.Foreground = library.IsBlackScreen ? Ui.Brush(Colors.White, 0.5) : Ui.Brush(SlideView.ParseColor(library.Settings.TextColorHex, Colors.White), 0.4);
        liveFrameBorder!.BorderBrush = library.IsLive ? Ui.Brush(Ui.Red, 0.8) : Ui.Brush(Ui.Gray, 0.35);
        liveFrameBorder.BorderThickness = new Thickness(library.IsLive ? 2 : 1);
        Add(liveFrameBorder, 6);
        if (library.IsLive && library.ActiveSong is Song activeSong)
        {
            var songLine = new TextBlock { Text = activeSong.Title, FontSize = 12, FontWeight = FontWeights.Medium, TextTrimming = TextTrimming.CharacterEllipsis, MaxLines = 1 };
            var slideLine = new TextBlock { Text = L("Slajd {0}/{1}", library.ActiveSlideIndex + 1, activeSong.Slides.Count), FontSize = 12, Foreground = Ui.Secondary };
            Add(Ui.Columns(8, (songLine, -1), (slideLine, 0)), 6);
        }

        // MARK: Sterowanie
        var controls = new Grid { ColumnSpacing = 8, RowSpacing = 8 };
        controls.ColumnDefinitions.Add(new ColumnDefinition());
        controls.ColumnDefinitions.Add(new ColumnDefinition());
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        controls.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Button Control(UIElement content, int row, int column, Action action, bool enabled = true, bool accent = false, int span = 1)
        {
            var b = new Button { Content = content, IsEnabled = enabled, HorizontalAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(8, 6, 8, 7), AllowFocusOnInteraction = false };
            if (accent) b.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
            b.Click += (_, _) => action();
            Grid.SetRow(b, row);
            Grid.SetColumn(b, column);
            Grid.SetColumnSpan(b, span);
            controls.Children.Add(b);
            return b;
        }
        StackPanel Centered(params UIElement[] items)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
            foreach (var item in items) panel.Children.Add(item);
            return panel;
        }
        TextBlock Text(string text, bool bold = false) => new() { Text = text, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        Control(Centered(Ui.Icon(Glyphs.ArrowLeft, 13), Text(L("Poprzedni"), true)), 0, 0, library.PrevSlide, library.IsLive);
        Control(Centered(Ui.Icon(Glyphs.ArrowRight, 13), Text(L("Następny"), true)), 0, 1, library.NextSlide, library.IsLive, accent: true, span: 2);
        var black = Control(Centered(Ui.Dot(library.IsBlackScreen ? Ui.Red : Ui.Gray), Text(L("Czarny (B)"))), 1, 0, library.ToggleBlackScreen);
        if (library.IsBlackScreen) Ui.SoftTint(black, Ui.Red);
        var clear = Control(Centered(Ui.Dot(library.IsClearText ? Ui.Orange : Ui.Gray), Text(L("Czysty (C)"))), 1, 1, library.ToggleClearText);
        if (library.IsClearText) Ui.SoftTint(clear, Ui.Orange);
        if (library.IsLive)
        {
            var stop = Control(Ui.Icon(Glyphs.Stop, 12, Ui.Red), 1, 2, library.StopLive);
            ToolTipService.SetToolTip(stop, L("Zatrzymaj prezentację"));
            Ui.AutomationName(stop, L("Zatrzymaj prezentację"));
        }
        else if (library.StartCandidate is not null)
        {
            // Wznowienie po zatrzymaniu (ten sam slajd), jak przycisk „Start” pilota.
            var resume = Control(Ui.Icon(Glyphs.Play, 12, Ui.Green), 1, 2, library.StartOrResume);
            var tip = library.ActiveSong is null ? L("Rozpocznij projekcję") : L("Wznów projekcję");
            ToolTipService.SetToolTip(resume, tip);
            Ui.AutomationName(resume, tip);
        }
        Add(controls, 14);
        Add(Ui.Divider(), 16);

        // MARK: Podgląd następnego slajdu
        var next = library.IsLive ? library.NextSlidePreview : null;
        UIElement nextState = next is null ? Ui.MutedBadge(L("KONIEC"), 11) : Ui.Badge(L("NASTĘPNY"), Ui.Orange, 11);
        Add(SectionHead(Glyphs.Next, L("Podgląd następnego slajdu"), ratio, nextState), 16);
        if (nextFrame is null)
        {
            nextLabel = new Border
            {
                Child = new TextBlock { FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Orange) },
                Background = Ui.Brush(Colors.Black, 0.65),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(5, 2, 5, 2),
                Margin = new Thickness(8),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
            };
            nextPlaceholder = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(8) };
            nextPlaceholder.Children.Add(new FontIcon { Glyph = Glyphs.Flag, FontFamily = Ui.SymbolFont, FontSize = 20, Foreground = Ui.Secondary, Opacity = 0.5 });
            nextPlaceholder.Children.Add(new TextBlock { FontSize = 12, Foreground = Ui.Secondary, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            nextFrame = new Grid();
            nextFrame.Children.Add(nextPreview);
            nextFrame.Children.Add(nextPlaceholder);
            nextFrame.Children.Add(nextLabel);
            nextFrameBorder = new Border
            {
                Child = nextFrame, CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
                BorderBrush = Ui.Brush(Ui.Gray, 0.4), HorizontalAlignment = HorizontalAlignment.Left,
            };
        }
        nextFrame.Width = width;
        nextFrame.Height = height;
        if (next is null)
        {
            nextPreview.Visibility = Visibility.Collapsed;
            nextLabel!.Visibility = Visibility.Collapsed;
            nextPlaceholder!.Visibility = Visibility.Visible;
            ((TextBlock)nextPlaceholder.Children[1]).Text = library.IsLive ? L("Brak kolejnego slajdu (Koniec pieśni)") : L("Brak aktywnej prezentacji");
            nextFrame.Background = Ui.Resource("ControlFillColorSecondaryBrush");
        }
        else
        {
            nextPreview.Visibility = Visibility.Visible;
            nextPlaceholder!.Visibility = Visibility.Collapsed;
            nextLabel!.Visibility = Visibility.Visible;
            ((TextBlock)nextLabel.Child).Text = Labels.Slide(next);
            nextPreview.Width = width;
            nextPreview.Height = height;
            nextPreview.Render(ScreenState.FromLibrary(dimmed: true, textOverride: next.Text), target);
        }
        Add(nextFrameBorder!, 6);
        if (next is not null)
        {
            var lines = next.Text.Split('\n').Length;
            Add(Ui.Columns(8,
                (new TextBlock { Text = L("Następny: {0}", Labels.Slide(next)), FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, TextTrimming = TextTrimming.CharacterEllipsis }, -1),
                (new TextBlock { Text = L("{0} linie", lines), FontSize = 11, Foreground = Ui.Secondary }, 0)), 6);
        }
        Add(Ui.Divider(), 16);

        // MARK: Ekrany i projektor
        var screensSection = new StackPanel { Spacing = 8 };
        var refresh = new Button { Content = Ui.Icon(Glyphs.Refresh, 12), Padding = new Thickness(6), MinWidth = 0, MinHeight = 0, Background = Ui.Brush(Colors.Transparent), BorderThickness = new Thickness(0) };
        ToolTipService.SetToolTip(refresh, L("Odśwież listę monitorów"));
        Ui.AutomationName(refresh, L("Odśwież listę monitorów"));
        refresh.Click += (_, _) => RenderRight();
        screensSection.Children.Add(Ui.Columns(6, (Ui.Header(Glyphs.FullScreen, L("Ekrany i Projektor"), 14), -1), (refresh, 0)));
        var screens = Screens.All();
        var screenBox = new ComboBox { Header = L("Docelowy ekran:"), HorizontalAlignment = HorizontalAlignment.Stretch };
        screenBox.Items.Add(new ComboBoxItem { Content = L("Automatycznie (drugi ekran)"), Tag = "" });
        foreach (var screen in screens) screenBox.Items.Add(new ComboBoxItem { Content = screen.Label, Tag = screen.Id });
        screenBox.SelectedIndex = Math.Max(0, screens.FindIndex(s => s.Id == library.Settings.WindowsScreenDevice) + 1);
        screenBox.SelectionChanged += (_, _) =>
        {
            if (screenBox.SelectedItem is not ComboBoxItem item) return;
            library.UpdateSettings(s => s.WindowsScreenDevice = (string)item.Tag);
            if (presentation.IsOpen && !presentation.IsWindowed) presentation.ShowFullScreen(Screens.Target() ?? screens.FirstOrDefault(s => s.IsPrimary));
        };
        screensSection.Children.Add(screenBox);
        var fullScreenActive = presentation.IsOpen && !presentation.IsWindowed;
        var fullScreen = new Button
        {
            Content = Centered(Ui.Icon(fullScreenActive ? Glyphs.Stop : Glyphs.FullScreen, 13), Text(fullScreenActive ? L("Zatrzymaj pełny ekran") : L("Prezentuj na pełnym ekranie"), true)),
            HorizontalAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(8, 6, 8, 7),
        };
        if (fullScreenActive) Ui.Tint(fullScreen, Ui.Red);
        else fullScreen.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        fullScreen.Click += (_, _) => ToggleFullScreen();
        screensSection.Children.Add(fullScreen);
        var testActive = presentation.IsOpen && presentation.IsWindowed;
        var test = new Button
        {
            Content = Centered(Ui.Icon(testActive ? Glyphs.Close : Glyphs.NewWindow, 12), Text(testActive ? L("Zamknij okno testowe") : L("Otwórz okno testowe"))),
            HorizontalAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(8, 5, 8, 6),
        };
        test.Click += (_, _) => ToggleTestWindow();
        screensSection.Children.Add(test);
        Add(screensSection, 16);
    }
}
