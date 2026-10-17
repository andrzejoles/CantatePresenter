using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Środkowy panel: wybrana pieśń i karty slajdów (SongSlidesView w macOS).</summary>
public sealed partial class MainWindow
{
    private StackPanel? songButtons;
    private Grid? songHeader;
    private FrameworkElement? songTitleBlock;
    private ScrollViewer? slidesScroll;
    private string? renderedSongId;

    private void RenderMiddle()
    {
        middlePanel.Children.Clear();
        middlePanel.RowDefinitions.Clear();
        songButtons = null;
        var song = library.SelectedSong;
        // Ta sama pieśń: przewinięcie zostaje (panel jest budowany od nowa przy każdej zmianie slajdu).
        var previousOffset = slidesScroll is not null && song?.Id == renderedSongId ? slidesScroll.VerticalOffset : 0;
        renderedSongId = song?.Id;
        slidesScroll = null;
        if (song is null)
        {
            var empty = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            empty.Children.Add(new FontIcon { Glyph = Glyphs.List, FontFamily = Ui.SymbolFont, FontSize = 48, Foreground = Ui.Secondary, Opacity = 0.45 });
            empty.Children.Add(new TextBlock { Text = L("Wybierz pieśń z biblioteki po lewej stronie"), FontSize = 15, FontWeight = FontWeights.Medium, Foreground = Ui.Secondary, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            middlePanel.Children.Add(empty);
            return;
        }
        for (var i = 0; i < 3; i++) middlePanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        middlePanel.RowDefinitions[2].Height = new GridLength(1, GridUnitType.Star);
        var isTemporary = song == library.TemporarySong;

        // Baner: na ekranie jest inna pieśń niż oglądana.
        if (library.IsLive && library.ActiveSong is Song liveSong && liveSong.Id != song.Id)
        {
            var back = new Button { Content = L("Wróć do prezentowanej pieśni"), FontSize = 12, Padding = new Thickness(8, 2, 8, 3), MinHeight = 0 };
            back.Click += (_, _) => library.SelectSong(liveSong.Id);
            var text = new TextBlock
            {
                Text = L("PROJEKTOR: Trwa projekcja '{0}' (slajd {1}/{2})", liveSong.Title, library.ActiveSlideIndex + 1, liveSong.Slides.Count),
                FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Red), TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center,
            };
            var banner = new Border
            {
                Child = Ui.Columns(8, (Ui.Dot(Ui.Red), 0), (text, -1), (back, 0)),
                Padding = new Thickness(14, 6, 14, 6),
                Background = Ui.Brush(Ui.Red, 0.12),
                BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"),
                BorderThickness = new Thickness(0, 0, 0, 1),
            };
            middlePanel.Children.Add(banner);
        }

        // Nagłówek: tytuł, tonacja, autor; przyciski obok tytułu, a w wąskim panelu pod nim, w końcu same ikony.
        var title = new StackPanel { Spacing = 4 };
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        titleRow.Children.Add(new TextBlock { Text = song.Title, FontSize = 20, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap, MaxLines = 2, TextTrimming = TextTrimming.CharacterEllipsis });
        if (song.Key.Trim().Length > 0) titleRow.Children.Add(Ui.Badge(song.Key.Trim(), Ui.Blue, 13));
        title.Children.Add(titleRow);
        if (song.Author.Trim().Length > 0) title.Children.Add(new TextBlock { Text = song.Author, FontSize = 13, Foreground = Ui.Secondary, TextTrimming = TextTrimming.CharacterEllipsis, MaxLines = 1 });
        songTitleBlock = title;

        songButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var present = Ui.Button(Glyphs.Play, L("Prezentuj"), (_, _) => library.Present(song), accent: true);
        present.FontWeight = FontWeights.SemiBold;
        songButtons.Children.Add(present);
        var toPlan = Ui.Button(Glyphs.AddTo, L("+ Do planu"), (_, _) => library.AddSongToPlan(song.Id));
        toPlan.IsEnabled = !isTemporary && library.ActivePlan is not null;
        songButtons.Children.Add(toPlan);
        var chordsText = song.HasChords ? L("Chwyty (✓)") : L("Chwyty");
        var chords = new Button { Content = GuitarLabel(chordsText), Padding = new Thickness(10, 5, 10, 6) };
        ToolTipService.SetToolTip(chords, chordsText);
        Ui.AutomationName(chords, chordsText);
        if (song.HasChords) Ui.SoftTint(chords, Ui.Orange);
        chords.Click += async (_, _) => await ChordsDialog.ShowAsync(this, song, (sheet, key) =>
        {
            song.Chords = sheet.Trim().Length > 0 ? sheet : null;
            if (key.Length > 0 && song.Key.Trim().Length == 0) song.Key = key;
            if (!isTemporary) library.UpdateSong(song);
        });
        songButtons.Children.Add(chords);
        var edit = Ui.Button(Glyphs.Edit, L("Edytuj pieśń i chwyty"), async (_, _) => await EditSongAsync(song), Lw("Edytuj słowa, sekcje i chwyty wybranej pieśni (⌘E)"));
        edit.IsEnabled = !isTemporary;
        songButtons.Children.Add(edit);

        songHeader = new Grid { ColumnSpacing = 12, RowSpacing = 8 };
        songHeader.ColumnDefinitions.Add(new ColumnDefinition());
        songHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        songHeader.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        songHeader.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        songHeader.Children.Add(title);
        songHeader.Children.Add(songButtons);
        var header = new StackPanel { Spacing = 8, Padding = new Thickness(14), Background = Ui.Resource("SolidBackgroundFillColorBaseBrush") };
        header.Children.Add(songHeader);
        if (song.Tags.Count > 0)
        {
            var tags = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            foreach (var tag in song.Tags)
            {
                tags.Children.Add(new Border
                {
                    Child = new TextBlock { Text = tag, FontSize = 11, Foreground = Ui.Secondary },
                    Padding = new Thickness(6, 2, 6, 3),
                    CornerRadius = new CornerRadius(4),
                    Background = Ui.Brush(Ui.Gray, 0.14),
                });
            }
            header.Children.Add(new ScrollViewer { Content = tags, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollMode = ScrollMode.Enabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollMode = ScrollMode.Disabled });
        }
        if (song.Copyright is not null || song.CcliNumber is not null)
            header.Children.Add(new TextBlock { Text = string.Join(" · ", new[] { song.Copyright, song.CcliNumber is null ? null : $"CCLI {song.CcliNumber}" }.OfType<string>()), Foreground = Ui.Secondary, FontSize = 11, TextWrapping = TextWrapping.Wrap });
        var headerBorder = new Border { Child = header, BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"), BorderThickness = new Thickness(0, 0, 0, 1) };
        Grid.SetRow(headerBorder, 1);
        middlePanel.Children.Add(headerBorder);
        header.SizeChanged += (_, e) => LayoutSongHeader(e.NewSize.Width - 28);

        // Karty slajdów.
        var body = new StackPanel { Spacing = 12, Padding = new Thickness(14) };
        var isActive = library.IsLive && library.ActiveSong?.Id == song.Id;
        var verse = 0;
        Border? liveCard = null;
        for (var index = 0; index < song.Slides.Count; index++)
        {
            var slide = song.Slides[index];
            var hint = slide.Type == SlideTypes.Verse ? $"[{slide.Number ?? ++verse}]" : slide.Type == SlideTypes.Chorus ? "[R]" : "";
            var position = index;
            var isLiveCard = isActive && library.ActiveSlideIndex == index;
            var card = SlideCard(slide, hint, isLiveCard, () => library.Present(song, position));
            if (isLiveCard) liveCard = card;
            body.Children.Add(card);
        }
        var scroll = new ScrollViewer { Content = body };
        slidesScroll = scroll;
        scroll.Loaded += (_, _) =>
        {
            if (previousOffset > 0) scroll.ChangeView(null, previousOffset, null, true);
            liveCard?.StartBringIntoView(new BringIntoViewOptions { AnimationDesired = false });
        };
        Grid.SetRow(scroll, 2);
        middlePanel.Children.Add(scroll);
    }

    /// <summary>Gitara (emoji) z napisem: Fluent Icons nie ma ikony gitary.</summary>
    private static StackPanel GuitarLabel(string text)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = "🎸", FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        panel.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }

    /// <summary>Przyciski obok tytułu, gdy się mieszczą; inaczej pod tytułem, a w bardzo wąskim panelu same ikony.</summary>
    private void LayoutSongHeader(double width)
    {
        if (songHeader is null || songButtons is null || songTitleBlock is null || width <= 0) return;
        foreach (var label in songButtons.Children.OfType<Button>().Select(b => (b.Content as StackPanel)?.Children.OfType<TextBlock>().LastOrDefault()).OfType<TextBlock>())
            label.Visibility = Visibility.Visible;
        songButtons.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var buttonsWidth = songButtons.DesiredSize.Width;
        songTitleBlock.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var titleWidth = Math.Min(songTitleBlock.DesiredSize.Width, 360);
        var sideBySide = titleWidth + 12 + buttonsWidth <= width;
        Grid.SetColumn(songButtons, sideBySide ? 1 : 0);
        Grid.SetRow(songButtons, sideBySide ? 0 : 1);
        Grid.SetColumnSpan(songTitleBlock, sideBySide ? 1 : 2);
        songButtons.VerticalAlignment = VerticalAlignment.Top;
        var compact = !sideBySide && buttonsWidth > width;
        foreach (var label in songButtons.Children.OfType<Button>().Select(b => (b.Content as StackPanel)?.Children.OfType<TextBlock>().LastOrDefault()).OfType<TextBlock>())
            label.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Karta slajdu: plakietka rodzaju, etykieta, klawisz, a na ekranie zielona ramka i „NA EKRANIE”.</summary>
    private static Border SlideCard(SongSlide slide, string hint, bool isLive, Action select)
    {
        var head = new Grid { ColumnSpacing = 8 };
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.ColumnDefinitions.Add(new ColumnDefinition());
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(Ui.SlideTypeBadge(slide.Type, 11));
        var label = new TextBlock { Text = Labels.Slide(slide), FontSize = 13, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center };
        if (isLive) label.Foreground = Ui.Brush(Ui.Green);
        Grid.SetColumn(label, 1);
        head.Children.Add(label);
        var hintText = new TextBlock { Text = hint, FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11, Foreground = Ui.Secondary, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(hintText, 2);
        head.Children.Add(hintText);
        if (isLive)
        {
            var onScreen = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            onScreen.Children.Add(Ui.Dot(Ui.Red));
            onScreen.Children.Add(new TextBlock { Text = L("NA EKRANIE"), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(Ui.Red) });
            var pill = new Border { Child = onScreen, Padding = new Thickness(6, 2, 6, 2), CornerRadius = new CornerRadius(4), Background = Ui.Brush(Ui.Red, 0.12) };
            Grid.SetColumn(pill, 3);
            head.Children.Add(pill);
        }
        var content = new StackPanel { Spacing = 8 };
        content.Children.Add(head);
        content.Children.Add(new TextBlock
        {
            Text = slide.Text, FontSize = 15, TextWrapping = TextWrapping.Wrap,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight, LineHeight = 22,
            Opacity = isLive ? 1 : 0.92,
        });
        var normal = Ui.Resource("CardBackgroundFillColorDefaultBrush");
        var card = new Border
        {
            Child = content,
            Padding = new Thickness(12),
            CornerRadius = new CornerRadius(8),
            Background = isLive ? Ui.Brush(Ui.Green, 0.08) : normal,
            BorderBrush = isLive ? Ui.Brush(Ui.Green) : Ui.Resource("CardStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(isLive ? 2.5 : 1),
        };
        if (!isLive)
        {
            card.PointerEntered += (_, _) => { card.Background = Ui.Brush(Ui.Gray, 0.1); card.BorderBrush = Ui.Brush(Ui.Gray, 0.35); };
            card.PointerExited += (_, _) => { card.Background = normal; card.BorderBrush = Ui.Resource("CardStrokeColorDefaultBrush"); };
        }
        card.Tapped += (_, _) => select();
        Ui.AutomationName(card, Labels.Slide(slide));
        return card;
    }
}
