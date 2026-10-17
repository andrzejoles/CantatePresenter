using CantatePresenter.Core.Data;
using CantatePresenter.Core.Input;
using CantatePresenter.Core.Models;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI.Core;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Okno główne: górny pasek, biblioteka/plan, slajdy pieśni, ekran na żywo i pasek skrótów (układ jak MainView w macOS).
/// Skróty idą przez <see cref="KeyboardRouter"/> (te same reguły i kody co w macOS); przy otwartym oknie dialogowym nie działają.
/// Panele są w osobnych plikach: MainWindow.Library.cs, MainWindow.Song.cs, MainWindow.Live.cs.
/// </summary>
public sealed partial class MainWindow : Window
{
    private Library library => Services.Library;
    private readonly PresentationWindow presentation = new();
    private MusiciansWindow? musicians;
    private readonly Grid root = new();
    // Powiększenie interfejsu (uiScale, jak w macOS): układ liczony dla rozmiaru okna podzielonego przez skalę
    // i powiększany przez Viewbox, więc wszystko (tekst, przyciski, odstępy) rośnie razem.
    private readonly Grid scaleHost = new();
    private readonly Viewbox scaleBox = new() { Stretch = Stretch.Fill };
    private TextBlock? zoomLabel;
    private readonly Grid leftPanel = new();
    private readonly Grid middlePanel = new();
    private readonly StackPanel rightPanel = new() { Spacing = 14, Padding = new Thickness(14) };
    private ShortcutBar? shortcutBar;
    internal bool DialogOpen;
    private bool exitBackupDone;

    public MainWindow()
    {
        Title = L("CantatePresenter — Prezenter Pieśni & Słowa");
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        FitToScreen();
        scaleBox.Child = root;
        scaleHost.Children.Add(scaleBox);
        scaleHost.SizeChanged += (_, _) => ApplyScale();
        Content = scaleHost;
        root.PreviewKeyDown += OnPreviewKeyDown;
        presentation.KeyPressed += key => HandleKey(key, KeyContext.Presentation);
        presentation.StateChanged += () => { RenderToolbar(); RenderRight(); };
        presentation.AppWindow.Hide();
        library.Changed += reason => DispatcherQueue.TryEnqueue(() => OnLibraryChanged(reason));
        // Kopia na Dysk Google przy zamykaniu (gdy włączona): zamknięcie czeka na wysyłkę, „Pomiń” albo limit czasu.
        AppWindow.Closing += async (_, e) =>
        {
            if (exitBackupDone || DialogOpen || !GoogleDriveDialog.ShouldBackupOnExit) return;
            e.Cancel = true;
            exitBackupDone = true;
            await GoogleDriveDialog.BackupOnExitAsync(this);
            Close();
        };
        Closed += (_, _) =>
        {
            Services.AppClosing = true;
            RemoteDialog.StopServer();
            presentation.Close();
            musicians?.Close();
            UserManualWindow.CloseIfOpen();
            Updater.LaunchPendingSetup();
        };
        BuildUi();
    }

    public PresentationWindow Presentation => presentation;

    /// <summary>
    /// Rozmiar startowy dopasowany do ekranu: 1500×920 na dużym monitorze, a na laptopie okno zmaksymalizowane,
    /// żeby pasek skrótów i podgląd następnego slajdu nie wypadały poza ekran.
    /// </summary>
    private void FitToScreen()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var work = area.WorkArea;
        var dpiScale = Content?.XamlRoot?.RasterizationScale ?? GetDpiScale();
        var width = (int)Math.Round(1500 * dpiScale);
        var height = (int)Math.Round(920 * dpiScale);
        if (width > work.Width * 0.92 || height > work.Height * 0.92)
        {
            if (AppWindow.Presenter is OverlappedPresenter overlapped) overlapped.Maximize();
            return;
        }
        AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private double GetDpiScale()
    {
        try
        {
            var dpi = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this));
            return dpi > 0 ? dpi / 96.0 : 1;
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return 1;
        }
    }

    // MARK: - Layout

    private void BuildUi()
    {
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RequestedTheme = ElementTheme.Default;
        root.Background = (Brush)Application.Current.Resources["ApplicationPageBackgroundThemeBrush"];
        scaleHost.Background = root.Background;

        var toolbar = Toolbar();
        Grid.SetRow(toolbar, 0);
        root.Children.Add(toolbar);

        var issues = IssuesBar();
        Grid.SetRow(issues, 1);
        root.Children.Add(issues);

        // Panele i ich ramki powstają raz: element XAML może mieć tylko jednego rodzica,
        // więc przy przebudowie wstawiany jest ten sam, już gotowy układ.
        mainGrid ??= MainGrid();
        Grid.SetRow(mainGrid, 2);
        root.Children.Add(mainGrid);

        shortcutBar = new ShortcutBar(this);
        Grid.SetRow(shortcutBar, 3);
        root.Children.Add(shortcutBar);

        Services.Trace("BuildUi: układ");
        RenderLeft();
        Services.Trace("BuildUi: lewy panel");
        RenderMiddle();
        Services.Trace("BuildUi: środkowy panel");
        RenderRight();
        Services.Trace("BuildUi: prawy panel");
    }

    private Grid? mainGrid;
    private double rightPanelWidth;

    /// <summary>Szerokość układu i okna (próba w CI sprawdza skalowanie).</summary>
    internal (double Root, double Host) ScaleWidths => (root.Width, scaleHost.ActualWidth);

    public double UiScale => Math.Clamp(library.Settings.UiScale, 0.7, 2);

    private void ApplyScale()
    {
        if (scaleHost.ActualWidth <= 0 || scaleHost.ActualHeight <= 0) return;
        root.Width = scaleHost.ActualWidth / UiScale;
        root.Height = scaleHost.ActualHeight / UiScale;
        if (zoomLabel is not null) zoomLabel.Text = $"{Math.Round(UiScale * 100)}%";
    }

    /// <summary>Zmiana skali o krok (A−/A+, Ctrl +/−), zaokrąglona do setnych jak w macOS i wersji webowej.</summary>
    public void Zoom(double delta) => library.UpdateSettings(s => s.UiScale = delta == 0 ? 1 : Math.Round(s.UiScale + delta, 2));

    private Grid MainGrid()
    {
        var main = new Grid { ColumnSpacing = 0 };
        // Proporcje 280 : 500 : 320 jak idealWidth paneli w macOS; przy powiększeniu lub wąskim oknie panele zwężają się razem.
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300, GridUnitType.Star), MinWidth = 230 });
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(500, GridUnitType.Star), MinWidth = 280 });
        main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(340, GridUnitType.Star), MinWidth = 280 });
        var leftBorder = Panel(leftPanel);
        var middleBorder = Panel(middlePanel);
        var rightBorder = Panel(new ScrollViewer { Content = rightPanel }, last: true);
        // Podglądy dopasowane do szerokości prawego panelu (zmienia się z oknem i powiększeniem).
        rightBorder.SizeChanged += (_, e) =>
        {
            if (Math.Abs(e.NewSize.Width - rightPanelWidth) < 8) return;
            rightPanelWidth = e.NewSize.Width;
            RenderRight();
        };
        Grid.SetColumn(leftBorder, 0);
        Grid.SetColumn(middleBorder, 1);
        Grid.SetColumn(rightBorder, 2);
        main.Children.Add(leftBorder);
        main.Children.Add(middleBorder);
        main.Children.Add(rightBorder);
        return main;
    }

    private static Border Panel(UIElement child, bool last = false) => new()
    {
        Child = child,
        BorderBrush = Ui.Resource("DividerStrokeColorDefaultBrush"),
        BorderThickness = new Thickness(0, 1, last ? 0 : 1, 0),
    };

    // MARK: - Toolbar

    private Button? remoteButton;
    private Button? musiciansButton;
    private Button? editButton;
    private ContentControl? statusHost;
    private readonly List<TextBlock> toolbarLabels = [];
    private StackPanel? toolbarActions;
    private Grid? toolbarGrid;

    /// <summary>Stan przycisków paska: pilot na zielono, muzycy na pomarańczowo, plakietka projektora (jak w macOS).</summary>
    public void RenderToolbar()
    {
        if (remoteButton is not null)
        {
            if (RemoteDialog.IsRunning) Ui.SoftTint(remoteButton, Ui.Green);
            else ClearTint(remoteButton);
        }
        if (musiciansButton is not null)
        {
            if (musicians is not null) Ui.SoftTint(musiciansButton, Ui.Orange);
            else ClearTint(musiciansButton);
        }
        if (editButton is not null) editButton.IsEnabled = library.SelectedSong is Song s && s != library.TemporarySong;
        if (statusHost is not null) statusHost.Content = StatusBadge();
    }

    private static void ClearTint(Button button)
    {
        foreach (var key in new[] { "ButtonBackground", "ButtonBackgroundPointerOver", "ButtonBackgroundPressed", "ButtonBorderBrush", "ButtonBorderBrushPointerOver" })
            button.Resources.Remove(key);
        button.ClearValue(Control.BackgroundProperty);
        button.ClearValue(Control.BorderBrushProperty);
    }

    /// <summary>Plakietka stanu projektora: odłączony (S1), pełny ekran albo okno testowe.</summary>
    private UIElement? StatusBadge()
    {
        static Border Pill(Microsoft.UI.Xaml.Shapes.Shape? dot, UIElement? icon, string text, Windows.UI.Color color, UIElement? extra = null)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            if (dot is not null) row.Children.Add(dot);
            if (icon is not null) row.Children.Add(icon);
            row.Children.Add(new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(color), VerticalAlignment = VerticalAlignment.Center });
            if (extra is not null) row.Children.Add(extra);
            return new Border { Child = row, Padding = new Thickness(8, 4, 8, 4), CornerRadius = new CornerRadius(6), Background = Ui.Brush(color, 0.13), VerticalAlignment = VerticalAlignment.Center };
        }
        if (presentation.IsWaitingForDisplay)
        {
            var stop = new Button { Content = L("Zakończ projekcję"), FontSize = 11, Padding = new Thickness(6, 1, 6, 2), MinHeight = 0 };
            stop.Click += (_, _) => { presentation.HideWindow(); RenderRight(); };
            return Pill(null, Ui.Icon(Glyphs.Warning, 12, Ui.Orange), L("Projektor odłączony – projekcja wróci po podłączeniu"), Ui.Orange, stop);
        }
        if (presentation.IsOpen && !presentation.IsWindowed) return Pill(Ui.Dot(Ui.Green), null, L("Projektor: Aktywny"), Ui.Green);
        if (presentation.IsOpen) return Pill(Ui.Dot(Ui.Blue), null, L("Okno testowe"), Ui.Blue);
        return null;
    }

    private FrameworkElement Toolbar()
    {
        toolbarLabels.Clear();
        var grid = new Grid { Padding = new Thickness(14, 8, 14, 8), ColumnSpacing = 12 };
        toolbarGrid = grid;
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Background = Ui.Resource("SolidBackgroundFillColorBaseBrush");

        var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, VerticalAlignment = VerticalAlignment.Center };
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        brand.Children.Add(Ui.Icon(Glyphs.Music, 18, Ui.Blue));
        brand.Children.Add(new TextBlock { Text = L("CantatePresenter"), FontWeight = FontWeights.Bold, FontSize = 15, VerticalAlignment = VerticalAlignment.Center });
        left.Children.Add(brand);
        statusHost = new ContentControl { VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(statusHost);

        var quick = Ui.Button(Glyphs.Bolt, L("Szybki tekst"), async (_, _) => await QuickTextAsync(), Lw("Wyświetl natychmiast dowolny tekst lub ogłoszenie bez zapisywania w bazie (⌘T)"));
        Ui.Tint(quick, Ui.Orange);
        quick.FontWeight = FontWeights.SemiBold;
        left.Children.Add(quick);

        // Akcje biblioteki; przy wąskim oknie same ikony z podpowiedzią (jak ViewThatFits w macOS).
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        toolbarActions = actions;
        Button Action(string glyph, string text, RoutedEventHandler click, string? tip = null, bool accent = false)
        {
            var b = Ui.Button(glyph, text, click, tip, accent);
            if (Ui.LabelText(b) is TextBlock label) toolbarLabels.Add(label);
            actions.Children.Add(b);
            return b;
        }
        Action(Glyphs.Add, L("Nowa pieśń"), async (_, _) => await EditSongAsync(null), accent: true);
        editButton = Action(Glyphs.Edit, L("Edytuj"), async (_, _) => { if (library.SelectedSong is Song s && s != library.TemporarySong) await EditSongAsync(s); }, Lw("Edytuj wybraną pieśń (podwójny klik lub ⌘E)"));
        Action(Glyphs.ImportExport, L("Import/Eksport"), async (_, _) => await ImportExportDialog.ShowAsync(this));
        Action(Glyphs.Contact, L("Tytuł/Autor"), async (_, _) => await AuthorTitleLookupDialog.ShowAsync(this, library.SelectedSong), L("Wyszukiwarka tytułu i autora (dla zaznaczonej lub dla wszystkich)"));
        Action(Glyphs.Globe, L("Online"), async (_, _) => await Dialogs.OnlineSearchAsync(this), L("Wyszukiwanie pieśni religijnych w internecie"));
        musiciansButton = Action(Glyphs.Music, L("Muzycy"), (_, _) => ToggleMusicians(), L("Ekran dla muzyków: bieżący slajd z chwytami (okno na osobny monitor)"));
        remoteButton = Action(Glyphs.Phone, L("Pilot"), async (_, _) => await RemoteDialog.ShowAsync(this), L("Pilot ze smartfona"));
        left.Children.Add(actions);
        grid.Children.Add(left);

        // Po prawej: rozmiar interfejsu, ustawienia, pomoc.
        var right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, VerticalAlignment = VerticalAlignment.Center };
        var zoom = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        zoom.Children.Add(new TextBlock { Text = L("Rozmiar UI") + ":", VerticalAlignment = VerticalAlignment.Center, Foreground = Ui.Secondary, FontSize = 12, Margin = new Thickness(0, 0, 2, 0) });
        Button ZoomButton(UIElement content, string tip, double delta)
        {
            var b = new Button { Content = content, Padding = new Thickness(8, 4, 8, 5), MinWidth = 0, AllowFocusOnInteraction = false };
            b.Click += (_, _) => Zoom(delta);
            ToolTipService.SetToolTip(b, tip);
            return b;
        }
        zoomLabel = new TextBlock { Text = $"{Math.Round(UiScale * 100)}%", FontFamily = new FontFamily("Consolas"), FontSize = 12 };
        zoom.Children.Add(ZoomButton(Ui.Icon(Glyphs.FontDecrease, 12), Lw("Zmniejsz rozmiar interfejsu (Cmd -)"), -0.05));
        zoom.Children.Add(ZoomButton(zoomLabel, Lw("Przywróć 100% rozmiaru (Cmd 0)"), 0));
        zoom.Children.Add(ZoomButton(Ui.Icon(Glyphs.FontIncrease, 12), Lw("Zwiększ rozmiar interfejsu (Cmd +)"), 0.05));
        right.Children.Add(new Border { Child = zoom, Padding = new Thickness(6, 3, 6, 3), CornerRadius = new CornerRadius(6), Background = Ui.Resource("ControlFillColorSecondaryBrush") });
        right.Children.Add(Ui.Divider(vertical: true, length: 20));
        var settings = new Button { Content = Ui.Icon(Glyphs.Settings, 15), Padding = new Thickness(8, 5, 8, 6) };
        settings.Click += async (_, _) => await SettingsDialog.ShowAsync(this);
        ToolTipService.SetToolTip(settings, L("Ustawienia wyglądu i prezentacji"));
        Ui.AutomationName(settings, L("Ustawienia"));
        right.Children.Add(settings);
        var help = new Button { Content = Ui.Icon(Glyphs.Help, 15), Padding = new Thickness(8, 5, 8, 6) };
        ToolTipService.SetToolTip(help, Lw("Instrukcja obsługi CantatePresenter (Cmd ?)"));
        Ui.AutomationName(help, L("Instrukcja obsługi"));
        var helpMenu = new MenuFlyout();
        void HelpItem(string glyph, string text, Func<Task> action)
        {
            var item = new MenuFlyoutItem { Text = text, Icon = new FontIcon { Glyph = glyph, FontFamily = Ui.SymbolFont } };
            item.Click += async (_, _) => await action();
            helpMenu.Items.Add(item);
        }
        HelpItem(Glyphs.Help, L("Instrukcja obsługi") + " (F1)", () => { UserManualWindow.Open(); return Task.CompletedTask; });
        HelpItem(Glyphs.Download, L("Sprawdź uaktualnienia..."), () => Updater.CheckAsync(this, manual: true));
        HelpItem(Glyphs.Info, L("O programie"), () => Dialogs.AboutAsync(this));
        help.Flyout = helpMenu;
        right.Children.Add(help);
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);

        grid.SizeChanged += (_, _) => FitToolbar();
        RenderToolbar();
        return grid;
    }

    /// <summary>Napisy przy akcjach tylko wtedy, gdy mieszczą się w pasku; inaczej same ikony.</summary>
    private void FitToolbar()
    {
        if (toolbarGrid is null || toolbarActions is null || toolbarGrid.ActualWidth <= 0) return;
        foreach (var label in toolbarLabels) label.Visibility = Visibility.Visible;
        toolbarGrid.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var fits = toolbarGrid.DesiredSize.Width <= toolbarGrid.ActualWidth;
        foreach (var label in toolbarLabels) label.Visibility = fits ? Visibility.Visible : Visibility.Collapsed;
    }

    private FrameworkElement IssuesBar()
    {
        var panel = new StackPanel();
        foreach (var issue in library.Issues)
        {
            var (title, message) = issue.Kind switch
            {
                PersistenceIssueKind.Unreadable => (L("Nie można odczytać pliku {0}", issue.FileName),
                    L("Plik jest uszkodzony albo ma nieznany format. Aplikacja go nie nadpisze: zmiany w tej części danych nie będą zapisywane do czasu przywrócenia kopii lub ponownego uruchomienia.\n\n{0}Szczegóły: {1}",
                        issue.QuarantinedCopy is null ? "" : L("Kopia pliku: {0}.\n\n", Path.GetFileName(issue.QuarantinedCopy)), issue.Detail)),
                PersistenceIssueKind.SaveFailed => (L("Nie można zapisać pliku {0}", issue.FileName), L("Ostatnie zmiany mogą nie zostać zachowane.\n\nSzczegóły: {0}", issue.Detail)),
                _ => (L("Dane z nowszej wersji aplikacji"),
                    L("Bibliotekę zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Pieśni i plany można wyświetlać, ale zmiany nie będą zapisywane, żeby nie uszkodzić danych. Zaktualizuj aplikację.", issue.FileName, AppSettings.SchemaVersionCurrent)),
            };
            panel.Children.Add(new InfoBar { Title = title, Message = message, Severity = InfoBarSeverity.Error, IsOpen = true });
        }
        return panel;
    }

    // MARK: - Windows

    public void ToggleProjection()
    {
        if (presentation.IsOpen) presentation.HideWindow();
        else presentation.ShowOn(Screens.Target());
        RenderToolbar();
        RenderRight();
    }

    /// <summary>„Prezentuj na pełnym ekranie”: wybrany ekran, a bez drugiego monitora ekran główny (jak w macOS).</summary>
    public void ToggleFullScreen()
    {
        if (presentation.IsOpen && !presentation.IsWindowed) presentation.HideWindow();
        else presentation.ShowFullScreen(Screens.Target() ?? Screens.All().FirstOrDefault(s => s.IsPrimary) ?? Screens.All().FirstOrDefault());
        RenderToolbar();
        RenderRight();
    }

    /// <summary>„Otwórz okno testowe”: projekcja w zwykłym oknie (bez drugiego monitora).</summary>
    public void ToggleTestWindow()
    {
        if (presentation.IsOpen && presentation.IsWindowed) presentation.HideWindow();
        else presentation.ShowOn(null);
        RenderToolbar();
        RenderRight();
    }

    public void OpenMusicians()
    {
        if (musicians is null)
        {
            musicians = new MusiciansWindow();
            musicians.Closed += (_, _) => { musicians = null; RenderToolbar(); };
        }
        musicians.Activate();
        RenderToolbar();
    }

    private void ToggleMusicians()
    {
        if (musicians is not null) musicians.Close();
        else OpenMusicians();
    }

    public MusiciansWindow? Musicians => musicians;

    // MARK: - Updates

    private void OnLibraryChanged(string reason)
    {
        switch (reason)
        {
            case "live":
                // Lista tylko przy zmianie pieśni na ekranie (czerwona kropka), nie przy każdym slajdzie: zachowuje fokus i przewinięcie.
                var liveId = library.IsLive ? library.ActiveSong?.Id : null;
                if (liveId != listedLiveId) RenderSongList();
                RenderMiddle();
                RenderRight();
                shortcutBar?.Render();
                if (showingPlan) RenderLeft();
                break;
            case "selection":
                RenderSongList();
                RenderMiddle();
                RenderToolbar();
                if (showingPlan) RenderLeft();
                break;
            case "settings":
                if (Catalog.Language != library.Settings.AppLanguage)
                {
                    Catalog.Language = library.Settings.AppLanguage;
                    Title = L("CantatePresenter — Prezenter Pieśni & Słowa");
                    BuildUi();
                }
                else
                {
                    RenderRight();
                    shortcutBar?.Render();
                }
                ApplyScale();
                break;
            default:
                BuildUi();
                break;
        }
    }

    // MARK: - Keyboard

    private KeyFocus FocusKind()
    {
        var element = FocusManager.GetFocusedElement(root.XamlRoot);
        return element switch
        {
            TextBox box => box.AcceptsReturn ? KeyFocus.MultilineText : KeyFocus.Text,
            ComboBox or PasswordBox => KeyFocus.MultilineText,
            ListView or ListViewItem => KeyFocus.List,
            _ => KeyFocus.Other,
        };
    }

    private static string Characters(VirtualKey key) => key switch
    {
        >= VirtualKey.Number0 and <= VirtualKey.Number9 => ((int)key - (int)VirtualKey.Number0).ToString(),
        >= VirtualKey.NumberPad0 and <= VirtualKey.NumberPad9 => ((int)key - (int)VirtualKey.NumberPad0).ToString(),
        >= VirtualKey.A and <= VirtualKey.Z => ((char)('a' + (key - VirtualKey.A))).ToString(),
        (VirtualKey)0xBB or VirtualKey.Add => "=",
        (VirtualKey)0xBD or VirtualKey.Subtract => "-",
        _ => "",
    };

    private static bool ControlDown => InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);

    private async void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (DialogOpen) return;
        // Skróty okna (w macOS z menu): Ctrl+E edycja, Ctrl+F szukaj, F1 instrukcja.
        if (ControlDown && e.Key == VirtualKey.E)
        {
            e.Handled = true;
            if (library.SelectedSong is Song song && song != library.TemporarySong) await EditSongAsync(song);
            return;
        }
        if (ControlDown && e.Key == VirtualKey.F)
        {
            e.Handled = true;
            FocusSearch();
            return;
        }
        if (e.Key == VirtualKey.F1)
        {
            e.Handled = true;
            UserManualWindow.Open();
            return;
        }
        if (HandleKey(e.Key, KeyContext.Main(FocusKind()))) e.Handled = true;
    }

    /// <summary>Wykonuje akcję skrótu; zwraca true, gdy klawisz został obsłużony.</summary>
    public bool HandleKey(VirtualKey key, KeyContext context)
    {
        if (DialogOpen) return false;
        var virtualKey = key >= VirtualKey.NumberPad0 && key <= VirtualKey.NumberPad9 ? VirtualKey.Number0 + (key - VirtualKey.NumberPad0) : key;
        var action = KeyboardRouter.Action(KeyboardRouter.MacCode((int)virtualKey), Characters(key), ControlDown, library.Settings.Shortcuts, context);
        if (action is null) return false;
        switch (action.Type)
        {
            case "nextSlide": library.NextSlide(); break;
            case "prevSlide": library.PrevSlide(); break;
            case "nextSong": library.NextSongInPlan(); break;
            case "prevSong": library.PrevSongInPlan(); break;
            case "blackScreen": library.ToggleBlackScreen(); break;
            case "clearText": library.ToggleClearText(); break;
            case "chorus": library.JumpToChorus(); break;
            case "verse": library.JumpToVerse(action.Number ?? 1); break;
            case "quickText": _ = QuickTextAsync(); break;
            case "zoomIn": Zoom(0.05); break;
            case "zoomOut": Zoom(-0.05); break;
            case "zoomReset": Zoom(0); break;
            case "endTextEditing": songList?.Focus(FocusState.Programmatic); break;
            case "startPresentation": if (library.SelectedSong is Song song) library.Present(song); break;
            case "stopPresentation": library.StopLive(); break;
        }
        return true;
    }

    // MARK: - Dialogs

    internal async Task QuickTextAsync()
    {
        if (await Dialogs.QuickTextAsync(this) is (string text, string title)) library.PresentQuickText(text, title);
    }

    internal async Task EditSongAsync(Song? song) => await SongEditorDialog.ShowAsync(this, song);

    public void FocusSearch()
    {
        showingPlan = false;
        RenderLeft();
        searchBox?.Focus(FocusState.Programmatic);
    }
}
