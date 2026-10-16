using System.Globalization;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Foundation;
using Windows.Graphics;

namespace CantatePresenter.WinUI;

/// <summary>Monitor do wyboru w Ustawieniach (DisplayArea z Windows App SDK).</summary>
public sealed record Screen(string Id, string Label, RectInt32 Bounds, bool IsPrimary);

public static class Screens
{
    public static List<Screen> All()
    {
        var result = new List<Screen>();
        var areas = DisplayArea.FindAll();
        var primary = DisplayArea.Primary?.DisplayId.Value;
        // Kolekcję czyta się po indeksie (wyliczanie DisplayArea.FindAll() bywa zawodne).
        for (var i = 0; i < areas.Count; i++)
        {
            var area = areas[i];
            var bounds = area.OuterBounds;
            var isPrimary = area.DisplayId.Value == primary;
            var label = Services.L("Ekran {0}", i + 1) + $" ({bounds.Width}×{bounds.Height}" + (isPrimary ? ", " + Services.L("główny") : "") + ")";
            result.Add(new Screen(area.DisplayId.Value.ToString(CultureInfo.InvariantCulture), label, bounds, isPrimary));
        }
        return result;
    }

    /// <summary>Ekran z ustawień; bez wyboru drugi ekran (projektor), a gdy go nie ma, null.</summary>
    public static Screen? Target()
    {
        var all = All();
        var saved = Services.Library.Settings.WindowsScreenDevice;
        if (saved.Length > 0) return all.FirstOrDefault(s => s.Id == saved);
        return all.FirstOrDefault(s => !s.IsPrimary);
    }
}

/// <summary>
/// Okno projekcji: pełny ekran bez ramki na wybranym monitorze. Po odłączeniu monitora chowa się zamiast przeskakiwać
/// na ekran operatora, a po ponownym podłączeniu wraca (S1).
/// </summary>
public sealed class PresentationWindow : Window
{
    private readonly SlideView view = new();
    private readonly DispatcherTimer monitorTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private string? screenId;
    private bool windowed;
    public bool IsOpen { get; private set; }

    public event Action<Windows.System.VirtualKey>? KeyPressed;

    public PresentationWindow()
    {
        Title = Services.L("CantatePresenter — Projekcja");
        Content = view;
        view.SizeChanged += (_, _) => Render();
        view.KeyDown += (_, e) =>
        {
            KeyPressed?.Invoke(e.Key);
            e.Handled = true;
        };
        view.IsTabStop = true;
        Services.Library.Changed += reason =>
        {
            if (reason is "live" or "settings" or "songs" or "all") DispatcherQueue.TryEnqueue(Render);
        };
        monitorTimer.Tick += (_, _) => CheckScreen();
        Closed += (_, _) =>
        {
            IsOpen = false;
            monitorTimer.Stop();
        };
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
    }

    public Size TargetSize => new(view.ActualWidth > 0 ? view.ActualWidth : 1920, view.ActualHeight > 0 ? view.ActualHeight : 1080);

    private void Render() => view.Render(ScreenState.FromLibrary(), TargetSize);

    /// <summary>Pełny ekran na monitorze; bez monitora projekcji — zwykłe okno (np. do prób na jednym ekranie).</summary>
    public void ShowOn(Screen? screen)
    {
        IsOpen = true;
        windowed = screen is null;
        screenId = screen?.Id;
        if (screen is null)
        {
            AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            AppWindow.Resize(new SizeInt32(1280, 720));
        }
        else
        {
            AppWindow.MoveAndResize(screen.Bounds);
            AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
        }
        AppWindow.Show();
        Activate();
        Render();
        monitorTimer.Start();
    }

    public void HideWindow()
    {
        IsOpen = false;
        monitorTimer.Stop();
        AppWindow.Hide();
    }

    private void CheckScreen()
    {
        if (windowed || screenId is null) return;
        var screen = Screens.All().FirstOrDefault(s => s.Id == screenId);
        if (screen is null)
        {
            if (AppWindow.IsVisible) AppWindow.Hide();
        }
        else if (!AppWindow.IsVisible)
        {
            AppWindow.MoveAndResize(screen.Bounds);
            AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
            AppWindow.Show(false);
        }
    }

    public FrameworkElement ContentElement => view;
}
