using CantatePresenter.Core.Data;
using CantatePresenter.Core.Models;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>
/// Import, eksport i kopia zapasowa (ImportExportSheet w macOS): zakładki Eksport, Import oraz Pełny backup i Dysk Google.
/// Działania z własnym oknem (przegląd importu, Dysk Google, komunikaty) startują po zamknięciu tego okna,
/// bo WinUI pokazuje tylko jedno okno dialogowe naraz.
/// </summary>
public static class ImportExportDialog
{
    public static async Task ShowAsync(MainWindow window, int startTab = 0)
    {
        var library = Services.Library;
        ContentDialog? dialog = null;
        Func<Task>? after = null;
        void Then(Func<Task> action)
        {
            after = action;
            dialog?.Hide();
        }

        // MARK: Zakładki
        string[] tabNames = [L("Eksport pieśni"), L("Import pieśni"), L("Pełny backup & Dysk Google")];
        var tabButtons = new List<ToggleButton>();
        var pages = new List<StackPanel>();
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        void Show(int index)
        {
            for (var i = 0; i < tabButtons.Count; i++)
            {
                tabButtons[i].IsChecked = i == index;
                pages[i].Visibility = i == index ? Visibility.Visible : Visibility.Collapsed;
            }
        }
        for (var i = 0; i < tabNames.Length; i++)
        {
            var index = i;
            var button = new ToggleButton
            {
                Content = tabNames[i], MinWidth = 180,
                CornerRadius = new CornerRadius(i == 0 ? 4 : 0, i == tabNames.Length - 1 ? 4 : 0, i == tabNames.Length - 1 ? 4 : 0, i == 0 ? 4 : 0),
            };
            button.Click += (_, _) => Show(index);
            tabButtons.Add(button);
            tabs.Children.Add(button);
            pages.Add(new StackPanel { Spacing = 18 });
        }

        // MARK: Eksport
        var export = pages[0];
        var selected = library.SelectedSong is Song s && s != library.TemporarySong ? s : null;
        var wholeLibrary = new RadioButton { Content = L("Cała biblioteka pieśni ({0} utworów)", library.Songs.Count), GroupName = "scope", IsChecked = true };
        var onlySelected = new RadioButton { Content = selected is null ? "" : L("Tylko zaznaczona pieśń: '{0}'", selected.Title), GroupName = "scope", Visibility = selected is null ? Visibility.Collapsed : Visibility.Visible };
        export.Children.Add(Ui.Group(Glyphs.Upload, L("Zakres eksportu"), out var scopeBody));
        scopeBody.Children.Add(wholeLibrary);
        scopeBody.Children.Add(onlySelected);
        var firstFormat = new RadioButton { GroupName = "format", IsChecked = true };
        var secondFormat = new RadioButton { GroupName = "format" };
        void Formats()
        {
            var all = wholeLibrary.IsChecked == true;
            firstFormat.Content = all ? L("Kopia zapasowa JSON (.json) — przeniesienie całej bazy") : L("Plik tekstowy (.txt)");
            secondFormat.Content = all ? L("Folder z osobnymi plikami tekstowymi (.txt)") : L("Plik JSON (.json)");
        }
        Formats();
        wholeLibrary.Checked += (_, _) => Formats();
        onlySelected.Checked += (_, _) => Formats();
        export.Children.Add(Ui.Group(Glyphs.Document, L("Format eksportu"), out var formatBody));
        formatBody.Children.Add(firstFormat);
        formatBody.Children.Add(secondFormat);
        var exportButton = Ui.Button(Glyphs.Upload, L("Eksportuj..."), (_, _) =>
        {
            var all = wholeLibrary.IsChecked == true || selected is null;
            var first = firstFormat.IsChecked == true;
            if (all && first) Then(() => ImportExport.ExportSongsJsonAsync(window, library.Songs, "Baza_piesni"));
            else if (all) Then(() => ImportExport.ExportFolderAsync(window, library.Songs));
            else if (first) Then(() => ImportExport.ExportSongAsync(window, selected));
            else Then(() => ImportExport.ExportSongsJsonAsync(window, [selected!], selected!.Title));
        }, accent: true);
        exportButton.HorizontalAlignment = HorizontalAlignment.Right;
        export.Children.Add(exportButton);

        // MARK: Import
        var import = pages[1];
        import.Children.Add(Ui.Group(Glyphs.Download, L("Wybierz pliki do importu"), out var importBody));
        importBody.Children.Add(Ui.Note(L("Aplikacja obsługuje pliki bazy Holyrics (.muf, .mufl, .hly), pliki tekstowe (.txt) z dowolnym kodowaniem, formaty XML (OpenLyrics / OpenSong), pliki JSON, archiwa ZIP oraz pliki pobrane z CCLI SongSelect (.txt, .usr, ChordPro .pro).")));
        var importButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        importButtons.Children.Add(Ui.Button(Glyphs.Add, L("Wybierz pliki (Holyrics .mufl, .txt, .json)..."), (_, _) => Then(() => ImportExport.ImportFilesAsync(window)), accent: true));
        importButtons.Children.Add(Ui.Button(Glyphs.Library, L("Wybierz cały folder..."), (_, _) => Then(() => ImportExport.ImportFolderAsync(window))));
        importBody.Children.Add(importButtons);
        import.Children.Add(Ui.Group(Glyphs.List, L("Stan aktualnej biblioteki"), out var statsBody));
        StackPanel Stat(int value, string label)
        {
            var panel = new StackPanel { Spacing = 0 };
            panel.Children.Add(new TextBlock { Text = value.ToString(), FontSize = 24, FontWeight = FontWeights.Bold });
            panel.Children.Add(new TextBlock { Text = label, FontSize = 12, Foreground = Ui.Secondary });
            return panel;
        }
        var stats = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 30 };
        stats.Children.Add(Stat(library.Songs.Count, L("Pieśni w bazie")));
        stats.Children.Add(Stat(library.Plans.Count, L("Zapisanych planów")));
        statsBody.Children.Add(stats);

        // MARK: Kopia zapasowa i Dysk Google
        var backup = pages[2];
        backup.Children.Add(Ui.Group(Glyphs.Save, L("Lokalna kopia zapasowa (.cantatebackup)"), out var localBody));
        localBody.Children.Add(Ui.Note(L("Pełna kopia zapasowa zabezpiecza wszystkie elementy aplikacji: bazę pieśni wraz z chwytami, plany nabożeństw, pełne ustawienia, ekran początkowy Standby, zainstalowane języki tłumaczeń oraz bibliotekę oficjalnych logotypów.")));
        var localButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        localButtons.Children.Add(Ui.Button(Glyphs.Save, L("Utwórz pełną kopię zapasową (.cantatebackup)..."), (_, _) => Then(() => ImportExport.CreateBackupAsync(window)), accent: true));
        localButtons.Children.Add(Ui.Button(Glyphs.Refresh, L("Przywróć z pliku kopii zapasowej..."), (_, _) => Then(() => ImportExport.RestoreBackupAsync(window))));
        var undo = Ui.Button(Glyphs.Undo, L("Cofnij ostatnie przywrócenie"), (_, _) => Then(() => ImportExport.UndoRestoreAsync(window)));
        undo.IsEnabled = Backup.CanUndo(library.DataDirectory);
        localButtons.Children.Add(undo);
        localBody.Children.Add(localButtons);
        backup.Children.Add(Ui.Group(Glyphs.Cloud, L("Kopia w chmurze Google Drive"), out var driveBody));
        var drive = library.Settings.GoogleDrive;
        var state = !drive.IsEnabled ? L("Nie połączono") : Drive.IsSignedIn ? (drive.AccountEmail.Length > 0 ? drive.AccountEmail : L("Połączono")) : L("Nie połączono");
        driveBody.Children.Add(Ui.Columns(10, (new TextBlock { Text = L("Integracja z kontem Dysku Google:"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center }, -1),
            (Ui.Badge(state, Ui.Blue, 11), 0)));
        var driveButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        driveButtons.Children.Add(Ui.Button(Glyphs.Cloud, L("Przeglądaj i przywróć kopie z Dysku Google..."), (_, _) => Then(() => GoogleDriveDialog.ShowAsync(window)), accent: true));
        driveBody.Children.Add(driveButtons);
        driveBody.Children.Add(Ui.Note(L("Logowanie, wysyłanie kopii, przywracanie z Dysku i kopia przy zamykaniu aplikacji.")));

        var content = new Grid();
        foreach (var page in pages) content.Children.Add(page);
        var body = new StackPanel { Spacing = 14, Width = 680 };
        body.Children.Add(tabs);
        body.Children.Add(new ScrollViewer { Content = content, MaxHeight = 520, Padding = new Thickness(0, 0, 12, 0) });
        Show(Math.Clamp(startTab, 0, 2));
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        title.Children.Add(Ui.Icon(Glyphs.ImportExport, 20, Ui.Blue));
        title.Children.Add(new TextBlock { Text = L("Import, Eksport i Kopia Zapasowa"), FontSize = 18, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        dialog = new ContentDialog { Title = title, Content = body, CloseButtonText = L("Zamknij") };
        dialog.Resources["ContentDialogMaxWidth"] = 760.0;
        await Dialogs.ShowAsync(window, dialog);
        if (after is not null) await after();
    }
}
