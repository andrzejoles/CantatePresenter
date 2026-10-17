using System.Globalization;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.GoogleDrive;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Kopie zapasowe na Dysku Google (jak sekcja Dysku w Ustawieniach i GoogleDriveBackupsSheet w macOS): połączenie konta,
/// wysłanie kopii, lista kopii z przywracaniem, kopia przy zamykaniu i folder na Dysku.
/// </summary>
public static class GoogleDriveDialog
{
    public static string FormatSize(long? bytes) => bytes switch
    {
        null => "?",
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => string.Format(CultureInfo.CurrentCulture, "{0:0.#} KB", bytes / 1024.0),
        _ => string.Format(CultureInfo.CurrentCulture, "{0:0.#} MB", bytes / 1024.0 / 1024.0),
    };

    /// <summary>Tworzy kopię w pliku tymczasowym i wysyła ją na Dysk; plik tymczasowy jest usuwany.</summary>
    public static async Task<RemoteBackupItem> UploadBackupAsync(string comment, CancellationToken cancellation = default)
    {
        var archive = Path.Combine(Path.GetTempPath(), Backup.FileName());
        Backup.Create(Library, archive, Version, comment);
        try
        {
            var item = await Drive.UploadAsync(archive, Library.Settings.GoogleDrive.FolderName, cancellation);
            Library.UpdateSettings(s => s.GoogleDrive.LastBackupDate = Core.Models.Json.IsoDate());
            return item;
        }
        finally
        {
            File.Delete(archive);
        }
    }

    public static async Task ShowAsync(MainWindow window)
    {
        var settings = Library.Settings.GoogleDrive;
        using var cancellation = new CancellationTokenSource();
        string? downloaded = null;
        ContentDialog? dialog = null;

        var body = new StackPanel { Spacing = 12, Width = 560 };
        var enabled = new CheckBox { Content = L("Synchronizacja i kopie na koncie Dysk Google (Google Drive)"), IsChecked = settings.IsEnabled, FontWeight = FontWeights.SemiBold };
        var details = new StackPanel { Spacing = 12, Margin = new Thickness(26, 0, 0, 0) };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12 };
        var busy = new ProgressRing { IsActive = false, Width = 18, Height = 18 };
        var busyText = new TextBlock { FontSize = 12, Opacity = 0.7, VerticalAlignment = VerticalAlignment.Center };
        var busyRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Visibility = Visibility.Collapsed };
        busyRow.Children.Add(busy);
        busyRow.Children.Add(busyText);
        var backups = new StackPanel { Spacing = 6 };

        void Status(string text, bool success)
        {
            status.Text = text;
            status.Foreground = new SolidColorBrush(success ? Colors.SeaGreen : Colors.IndianRed);
        }

        void Busy(string? text)
        {
            busy.IsActive = text is not null;
            busyText.Text = text ?? "";
            busyRow.Visibility = text is null ? Visibility.Collapsed : Visibility.Visible;
        }

        async Task Run(string progress, Func<Task> action)
        {
            status.Text = "";
            Busy(progress);
            details.IsHitTestVisible = false;
            try
            {
                await action();
            }
            finally
            {
                Busy(null);
                details.IsHitTestVisible = true;
            }
        }

        void Render()
        {
            details.Children.Clear();
            details.Visibility = enabled.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            var signedIn = Drive.IsSignedIn;

            var account = new Grid { ColumnSpacing = 10 };
            account.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
            account.ColumnDefinitions.Add(new ColumnDefinition());
            account.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            account.Children.Add(new TextBlock { Text = L("Konto Google:"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            var email = new TextBlock
            {
                Text = signedIn ? (settings.AccountEmail.Length > 0 ? settings.AccountEmail : L("połączono")) : L("nie połączono"),
                Opacity = signedIn ? 1 : 0.6, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
            };
            Grid.SetColumn(email, 1);
            account.Children.Add(email);
            FrameworkElement accountAction;
            if (signedIn)
            {
                var disconnect = new Button { Content = L("Rozłącz") };
                disconnect.Click += (_, _) =>
                {
                    Drive.SignOut();
                    Library.UpdateSettings(s => s.GoogleDrive.AccountEmail = "");
                    backups.Children.Clear();
                    Render();
                    Status(L("Rozłączono konto Google. Tokeny usunięto z Menedżera poświadczeń Windows."), true);
                };
                accountAction = disconnect;
            }
            else if (Drive.IsSignInAvailable)
            {
                var connect = new Button { Content = L("Połącz z kontem Google..."), Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
                connect.Click += async (_, _) => await Run(L("Dokończ logowanie w przeglądarce..."), async () =>
                {
                    try
                    {
                        var address = await Drive.SignInAsync(url => _ = Windows.System.Launcher.LaunchUriAsync(new Uri(url)), cancellation.Token);
                        Library.UpdateSettings(s => s.GoogleDrive.AccountEmail = address);
                        Status(address.Length == 0 ? L("Połączono z kontem Google.") : L("Połączono z kontem Google: {0}.", address), true);
                    }
                    catch (Exception error) when (error is GoogleOAuthException or GoogleDriveException or HttpRequestException or IOException)
                    {
                        Status(L("Nie udało się połączyć z kontem Google: {0}", error.Message), false);
                    }
                    Render();
                });
                accountAction = connect;
            }
            else
            {
                accountAction = new TextBlock { Text = L("Logowanie Google niedostępne w tej wersji aplikacji"), Opacity = 0.6, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
            }
            Grid.SetColumn(accountAction, 2);
            account.Children.Add(accountAction);
            details.Children.Add(account);

            var folder = new TextBox { Text = settings.TargetFolder, PlaceholderText = GoogleDriveSettings.DefaultFolder };
            folder.LostFocus += (_, _) => { if (folder.Text.Trim() != settings.TargetFolder) Library.UpdateSettings(s => s.GoogleDrive.TargetFolder = folder.Text.Trim()); };
            var folderRow = new Grid { ColumnSpacing = 10 };
            folderRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
            folderRow.ColumnDefinitions.Add(new ColumnDefinition());
            folderRow.Children.Add(new TextBlock { Text = L("Folder na Dysku:"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            Grid.SetColumn(folder, 1);
            folderRow.Children.Add(folder);
            details.Children.Add(folderRow);

            var autoBackup = new CheckBox { Content = L("Twórz i wysyłaj kopię na Dysk Google automatycznie przy zamykaniu aplikacji"), IsChecked = settings.AutoBackupOnExit };
            autoBackup.Click += (_, _) => Library.UpdateSettings(s => s.GoogleDrive.AutoBackupOnExit = autoBackup.IsChecked == true);
            details.Children.Add(autoBackup);

            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var upload = new Button { Content = "⇪  " + L("Wyślij bieżący backup na Dysk Google"), IsEnabled = signedIn, Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
            upload.Click += async (_, _) => await Run(L("Wysyłanie kopii do chmury Google..."), async () =>
            {
                try
                {
                    var item = await UploadBackupAsync(L("Ręczny backup z Ustawień"), cancellation.Token);
                    Status(L("Pomyślnie przesłano kopię '{0}' na Dysk Google ({1}) do folderu '{2}'!", item.Name, FormatSize(item.Size), Library.Settings.GoogleDrive.FolderName), true);
                }
                catch (Exception error) when (error is GoogleOAuthException or GoogleDriveException or HttpRequestException or IOException or UnauthorizedAccessException)
                {
                    Status(L("Błąd wysyłania na Dysk Google: {0}", error.Message), false);
                }
            });
            var browse = new Button { Content = "⟲  " + L("Przeglądaj i przywróć kopie z Dysku Google..."), IsEnabled = signedIn };
            browse.Click += async (_, _) => await Run(L("Wczytywanie listy kopii zapasowych z Dysku Google..."), async () =>
            {
                backups.Children.Clear();
                try
                {
                    var items = await Drive.ListAsync(Library.Settings.GoogleDrive.FolderName, cancellation.Token);
                    backups.Children.Add(new TextBlock { Text = L("Kopie zapasowe na Dysku Google"), FontWeight = FontWeights.SemiBold });
                    if (items.Count == 0) backups.Children.Add(new TextBlock { Text = L("Brak zapisanych kopii zapasowych w folderze '{0}'", Library.Settings.GoogleDrive.FolderName), Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
                    foreach (var item in items) backups.Children.Add(BackupRow(item));
                }
                catch (Exception error) when (error is GoogleOAuthException or GoogleDriveException or HttpRequestException or IOException)
                {
                    Status(error.Message, false);
                }
            });
            actions.Children.Add(upload);
            actions.Children.Add(browse);
            details.Children.Add(actions);
            details.Children.Add(new ScrollViewer { Content = backups, MaxHeight = 240 });
        }

        FrameworkElement BackupRow(RemoteBackupItem item)
        {
            var row = new Grid { ColumnSpacing = 8, Padding = new Thickness(8), CornerRadius = new CornerRadius(6), Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"] };
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var info = new StackPanel();
            info.Children.Add(new TextBlock { Text = item.Name, TextTrimming = TextTrimming.CharacterEllipsis, FontSize = 12 });
            info.Children.Add(new TextBlock { Text = $"{item.CreatedTime?.ToLocalTime().ToString("g", CultureInfo.CurrentCulture) ?? "?"} · {FormatSize(item.Size)}", Opacity = 0.6, FontSize = 11 });
            row.Children.Add(info);
            var restore = new Button { Content = L("Przywróć tę kopię") };
            restore.Click += async (_, _) => await Run(L("Pobieranie kopii z Dysku Google..."), async () =>
            {
                try
                {
                    downloaded = await Drive.DownloadAsync(item.Id, cancellation.Token);
                    dialog?.Hide();
                }
                catch (Exception error) when (error is GoogleOAuthException or GoogleDriveException or HttpRequestException or IOException)
                {
                    Status(L("Błąd przywracania z Dysku Google: {0}", error.Message), false);
                }
            });
            Grid.SetColumn(restore, 1);
            row.Children.Add(restore);
            return row;
        }

        enabled.Click += (_, _) =>
        {
            Library.UpdateSettings(s => s.GoogleDrive.IsEnabled = enabled.IsChecked == true);
            Render();
        };
        body.Children.Add(enabled);
        body.Children.Add(details);
        body.Children.Add(busyRow);
        body.Children.Add(status);
        body.Children.Add(new TextBlock
        {
            Text = L("Kopie trafiają na Dysk Google Twojego konta. Aplikacja widzi tylko pliki, które sama utworzyła. Dane logowania są w Menedżerze poświadczeń Windows."),
            TextWrapping = TextWrapping.Wrap, FontSize = 11, Opacity = 0.65,
        });
        Render();

        dialog = new ContentDialog
        {
            Title = L("Kopie zapasowe na Dysku Google"),
            Content = new ScrollViewer { Content = body, MaxHeight = 640 },
            CloseButtonText = L("Zamknij"),
        };
        dialog.Resources["ContentDialogMaxWidth"] = 720.0;
        await Dialogs.ShowAsync(window, dialog);
        cancellation.Cancel();
        if (downloaded is null) return;
        try
        {
            await ImportExport.RestoreArchiveAsync(window, downloaded);
        }
        finally
        {
            File.Delete(downloaded);
        }
    }

    // MARK: - Kopia przy zamykaniu (W2)

    /// <summary>
    /// Kopia przy zamykaniu, gdy włączona: okno z postępem i „Pomiń i zamknij”, limit 60 s. Gdy wysyłka się nie uda,
    /// kopia zostaje w katalogu danych (backups/, 5 najnowszych), jak ExitBackupCoordinator w macOS.
    /// </summary>
    public static bool ShouldBackupOnExit => Library.Settings.GoogleDrive is { IsEnabled: true, AutoBackupOnExit: true } && Drive.IsSignedIn;

    public static async Task BackupOnExitAsync(MainWindow window)
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        var panel = new StackPanel { Spacing = 10, Width = 380 };
        var progress = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        progress.Children.Add(new ProgressRing { IsActive = true, Width = 20, Height = 20 });
        progress.Children.Add(new TextBlock { Text = L("Tworzenie kopii zapasowej na Dysku Google…"), VerticalAlignment = VerticalAlignment.Center });
        panel.Children.Add(progress);
        panel.Children.Add(new TextBlock { Text = L("Jeśli wysyłka się nie uda, kopia zostanie zapisana lokalnie."), FontSize = 12, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
        var dialog = new ContentDialog { Title = "CantatePresenter", Content = panel, CloseButtonText = L("Pomiń i zamknij") };
        var shown = Dialogs.ShowAsync(window, dialog);
        var archive = Path.Combine(Path.GetTempPath(), Backup.FileName());
        try
        {
            Backup.Create(Library, archive, Version, "Automatyczny backup przy zamykaniu CantatePresenter");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Trace("kopia przy zamykaniu: " + error.Message);
            dialog.Hide();
            return;
        }
        var folder = Library.Settings.GoogleDrive.FolderName;
        var work = Task.Run(async () =>
        {
            try
            {
                await Drive.UploadAsync(archive, folder, cancellation.Token);
                return true;
            }
            catch (Exception error)
            {
                Trace("kopia przy zamykaniu: " + error.Message);
                return false;
            }
        }, CancellationToken.None);
        // Pierwsze z trzech: koniec wysyłki, „Pomiń i zamknij” albo limit czasu.
        var timeout = Task.Delay(Timeout.Infinite, cancellation.Token).ContinueWith(_ => { }, TaskScheduler.Default);
        var finished = await Task.WhenAny(work, shown, timeout);
        var uploaded = finished == work && work.Result;
        cancellation.Cancel();
        if (uploaded) Library.UpdateSettings(s => s.GoogleDrive.LastBackupDate = Core.Models.Json.IsoDate());
        else KeepLocally(archive);
        dialog.Hide();
        // Wysyłka przerwana przez „Pomiń” kończy się sama po anulowaniu; plik usuwamy, gdy już go nie czyta.
        await Task.WhenAny(work, Task.Delay(2000));
        if (File.Exists(archive)) File.Delete(archive);
    }

    private static void KeepLocally(string archive)
    {
        try
        {
            if (!File.Exists(archive)) return;
            var directory = Path.Combine(Library.DataDirectory, "backups");
            Directory.CreateDirectory(directory);
            File.Copy(archive, Path.Combine(directory, Path.GetFileName(archive)), overwrite: true);
            foreach (var old in Directory.GetFiles(directory).Where(f => !Path.GetFileName(f).StartsWith('.')).Order(StringComparer.Ordinal).SkipLast(5)) File.Delete(old);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Trace("kopia lokalna: " + error.Message);
        }
    }
}
