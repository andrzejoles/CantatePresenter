using System.Diagnostics;
using CantatePresenter.Core.Updates;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Aktualizacje jak Sparkle w macOS: sprawdzanie przy starcie (gdy włączone w Ustawieniach) i z okna „O programie”.
/// Zainstalowana aplikacja pobiera instalator, zamyka się i uruchamia go w trybie cichym (Inno Setup instaluje na
/// miejscu poprzedniej wersji i uruchamia nową). Wersja z ZIP-a tylko otwiera stronę wydania.
/// </summary>
public static class Updater
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };
    private static string? pendingSetup;
    private static bool checking;

    /// <summary>Zainstalowana instalatorem (obok jest deinstalator Inno Setup), a nie rozpakowana z ZIP-a.</summary>
    public static bool IsInstalled => File.Exists(Path.Combine(AppContext.BaseDirectory, "unins000.exe"));

    private static string DownloadDirectory => Path.Combine(Path.GetTempPath(), "CantatePresenter-update");

    /// <summary>Po starcie: tylko gdy jest nowsza wersja; błędy sieci bez komunikatu.</summary>
    public static async Task CheckOnStartAsync(MainWindow window)
    {
        if (!Services.Library.Settings.CheckForUpdatesAutomatically || UpdateChecker.ParseVersion(Services.Version) is null) return;
        try { Directory.Delete(DownloadDirectory, true); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        await Task.Delay(TimeSpan.FromSeconds(8));
        await CheckAsync(window, manual: false);
    }

    public static async Task CheckAsync(MainWindow window, bool manual)
    {
        if (checking) return;
        checking = true;
        try
        {
            WindowsRelease? release;
            try
            {
                release = await UpdateChecker.LatestAsync(Http);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or InvalidOperationException)
            {
                Trace($"aktualizacje: {error.Message}");
                if (manual) await Dialogs.InfoAsync(window, L("Uaktualnienia"), L("Nie można sprawdzić uaktualnień: {0}", error.Message));
                return;
            }
            if (release is null || !UpdateChecker.IsNewer(release.Version, Services.Version))
            {
                if (manual) await Dialogs.InfoAsync(window, L("Uaktualnienia"), L("Masz najnowszą wersję ({0}).", Services.Version));
                return;
            }
            // Przy starcie nie przerywamy pracy otwartym oknem ani projekcją.
            if (!manual && (window.DialogOpen || Services.Library.IsLive)) return;
            await OfferAsync(window, release);
        }
        finally
        {
            checking = false;
        }
    }

    private static async Task OfferAsync(MainWindow window, WindowsRelease release)
    {
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = L("Dostępna jest nowa wersja {0} (masz {1}).", release.Version, Services.Version), TextWrapping = TextWrapping.Wrap });
        if (release.Notes.Trim().Length > 0)
        {
            panel.Children.Add(new ScrollViewer
            {
                MaxHeight = 260,
                Content = new TextBlock { Text = release.Notes.Trim(), TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, FontSize = 13, Opacity = 0.85 },
            });
        }
        var progress = new ProgressBar { Minimum = 0, Maximum = 1, Visibility = Visibility.Collapsed };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        panel.Children.Add(progress);
        panel.Children.Add(status);
        if (!IsInstalled)
            panel.Children.Add(new TextBlock { Text = L("Ta kopia nie jest zainstalowana instalatorem, więc pobierz nową wersję ze strony wydania."), TextWrapping = TextWrapping.Wrap, Opacity = 0.75, FontSize = 12 });

        var dialog = new ContentDialog
        {
            Title = L("Uaktualnienia"),
            Content = panel,
            PrimaryButtonText = IsInstalled ? L("Zainstaluj i uruchom ponownie") : L("Otwórz stronę pobierania"),
            CloseButtonText = L("Później"),
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.Resources["ContentDialogMaxWidth"] = 640.0;
        var downloading = false;
        dialog.PrimaryButtonClick += async (_, e) =>
        {
            if (!IsInstalled)
            {
                _ = Windows.System.Launcher.LaunchUriAsync(new Uri(release.PageUrl));
                return;
            }
            e.Cancel = true;
            if (downloading) return;
            downloading = true;
            var deferral = e.GetDeferral();
            dialog.IsPrimaryButtonEnabled = false;
            progress.Visibility = status.Visibility = Visibility.Visible;
            status.Text = L("Pobieranie {0}...", release.SetupName);
            try
            {
                var reporter = new Progress<double>(value => progress.Value = value);
                pendingSetup = await UpdateChecker.DownloadSetupAsync(Http, release, DownloadDirectory, (key, args) => L(key, args), reporter);
                status.Text = L("Zamykanie aplikacji i instalacja...");
                deferral.Complete();
                dialog.Hide();
                return;
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException or UpdateException)
            {
                pendingSetup = null;
                status.Text = L("Nie można pobrać uaktualnienia: {0}", error.Message);
                dialog.IsPrimaryButtonEnabled = true;
                progress.Visibility = Visibility.Collapsed;
            }
            downloading = false;
            deferral.Complete();
        };
        await Dialogs.ShowAsync(window, dialog);
        // Zwykłe zamykanie (z kopią na Dysk Google, gdy włączona); instalator startuje po zamknięciu okna.
        if (pendingSetup is not null) window.Close();
    }

    /// <summary>Wywoływane po zamknięciu okna głównego: uruchamia pobrany instalator (cicha instalacja i ponowne uruchomienie).</summary>
    public static void LaunchPendingSetup()
    {
        if (pendingSetup is not string path || !File.Exists(path)) return;
        pendingSetup = null;
        try
        {
            Process.Start(new ProcessStartInfo(path, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH=1") { UseShellExecute = true });
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Trace($"aktualizacje: instalator nie wystartował: {error.Message}");
        }
    }
}
