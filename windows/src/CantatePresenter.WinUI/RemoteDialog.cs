using CantatePresenter.Core.Remote;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Pilot ze smartfona i podgląd dla muzyków na tabletach (jak RemoteControlSheet w macOS): włączenie serwera
/// w sieci lokalnej, kod QR z adresem i tokenem, liczba połączonych telefonów, nowy kod.
/// </summary>
public static class RemoteDialog
{
    /// <summary>Serwer dla całej aplikacji; żądania wykonywane w wątku interfejsu (Library nie jest bezpieczna wątkowo).</summary>
    public static RemoteServer Server(MainWindow window) => server ??= new RemoteServer((request, token, stageToken) =>
    {
        var result = new TaskCompletionSource<RemoteHttpResponse>();
        var queued = window.DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                result.SetResult(RemoteBridge.Router(Library, token, stageToken, Labels.Slide).Respond(request));
            }
            catch (Exception error)
            {
                Trace("pilot: " + error);
                result.SetResult(RemoteHttpResponse.Text("Error", 500));
            }
        });
        if (!queued) result.SetResult(RemoteHttpResponse.Text("Error", 500));
        return result.Task;
    });

    private static RemoteServer? server;

    public static bool IsRunning => server?.IsRunning == true;

    public static void StopServer() => server?.Stop();

    public static async Task ShowAsync(MainWindow window)
    {
        var dialog = Build(window, out var timer);
        timer.Start();
        try
        {
            await Dialogs.ShowAsync(window, dialog);
        }
        finally
        {
            timer.Stop();
        }
    }

    /// <summary>Okno bez pokazywania (próba w CI robi zrzut otwartego okna).</summary>
    public static ContentDialog Build(MainWindow window, out DispatcherTimer timer)
    {
        var remote = Server(window);
        var showsMusicianCode = false;
        var body = new StackPanel { Spacing = 12, Width = 420 };
        var toggle = new ToggleSwitch { Header = L("Włącz pilota"), IsOn = remote.IsRunning, OnContent = "", OffContent = "" };
        var codeChoice = new RadioButtons { MaxColumns = 2 };
        codeChoice.Items.Add(L("Sterowanie"));
        codeChoice.Items.Add(L("Muzycy (chwyty, tylko podgląd)"));
        codeChoice.SelectedIndex = 0;
        var details = new StackPanel { Spacing = 10 };
        var connected = new TextBlock { FontWeight = FontWeights.Medium, FontSize = 12 };
        var error = new TextBlock { Foreground = new SolidColorBrush(Colors.IndianRed), TextWrapping = TextWrapping.Wrap, FontSize = 12 };

        void UpdateConnected() => connected.Text = L("Połączone telefony: {0}", remote.ConnectedDevices());

        void Render()
        {
            details.Children.Clear();
            codeChoice.Visibility = remote.IsRunning ? Visibility.Visible : Visibility.Collapsed;
            error.Text = remote.ErrorMessage is string message && !remote.IsRunning ? L("Nie udało się uruchomić pilota: {0}", message) : "";
            if (!remote.IsRunning) return;
            var address = showsMusicianCode ? remote.StageAddress : remote.Address;
            if (address is null)
            {
                details.Children.Add(new TextBlock { Text = L("Ten komputer nie jest połączony z siecią lokalną (Wi-Fi lub Ethernet)."), Foreground = new SolidColorBrush(Colors.Orange), TextWrapping = TextWrapping.Wrap });
                return;
            }
            details.Children.Add(new Border
            {
                Background = new SolidColorBrush(Colors.White),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(10),
                HorizontalAlignment = HorizontalAlignment.Center,
                Child = QrImage(address, 220),
            });
            details.Children.Add(new TextBlock
            {
                Text = showsMusicianCode
                    ? L("Muzycy skanują ten kod: bieżący slajd z chwytami na tablecie lub telefonie, bez sterowania prezentacją.")
                    : L("Zeskanuj kod aparatem telefonu albo wpisz adres w przeglądarce:"),
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12,
                Opacity = 0.75,
            });
            details.Children.Add(new TextBox { Text = address, IsReadOnly = true, FontFamily = new FontFamily("Consolas"), FontSize = 12 });
            UpdateConnected();
            details.Children.Add(connected);
            var regenerate = new Button { Content = "⟳  " + L("Nowy kod (rozłącza telefony)") };
            regenerate.Click += (_, _) =>
            {
                remote.RegenerateTokens();
                Render();
            };
            details.Children.Add(regenerate);
        }

        toggle.Toggled += (_, _) =>
        {
            if (toggle.IsOn) remote.Start(); else remote.Stop();
            if (toggle.IsOn != remote.IsRunning) toggle.IsOn = remote.IsRunning;
            Render();
            window.RenderToolbar();
        };
        codeChoice.SelectionChanged += (_, _) =>
        {
            showsMusicianCode = codeChoice.SelectedIndex == 1;
            Render();
        };

        body.Children.Add(toggle);
        body.Children.Add(codeChoice);
        body.Children.Add(details);
        body.Children.Add(error);
        body.Children.Add(new TextBlock
        {
            Text = L("Telefon musi być w tej samej sieci Wi-Fi co ten komputer. Przy pierwszym włączeniu Zapora systemu Windows może zapytać o zgodę na dostęp do sieci: zezwól w sieciach prywatnych. Pilot działa, dopóki aplikacja jest otwarta."),
            TextWrapping = TextWrapping.Wrap,
            FontSize = 11,
            Opacity = 0.7,
        });
        Render();

        timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        timer.Tick += (_, _) => { if (remote.IsRunning) UpdateConnected(); };
        return new ContentDialog
        {
            Title = "📱  " + L("Pilot ze smartfona"),
            Content = new ScrollViewer { Content = body, MaxHeight = 640 },
            CloseButtonText = L("Zamknij"),
        };
    }

    /// <summary>Kod QR jako wektor (moduły ciemne + margines 4 modułów), ostry w każdej skali.</summary>
    public static FrameworkElement QrImage(string text, double pixels)
    {
        var modules = QrCode.Encode(text);
        var size = modules.GetLength(0);
        var geometry = new GeometryGroup { FillRule = FillRule.Nonzero };
        for (var y = 0; y < size; y++)
        {
            for (var x = 0; x < size; x++)
            {
                if (modules[y, x]) geometry.Children.Add(new RectangleGeometry { Rect = new Windows.Foundation.Rect(x + 4, y + 4, 1, 1) });
            }
        }
        var canvas = new Canvas { Width = size + 8, Height = size + 8, Background = new SolidColorBrush(Colors.White) };
        canvas.Children.Add(new Microsoft.UI.Xaml.Shapes.Path { Data = geometry, Fill = new SolidColorBrush(Colors.Black) });
        return new Viewbox { Width = pixels, Height = pixels, Child = canvas };
    }
}
