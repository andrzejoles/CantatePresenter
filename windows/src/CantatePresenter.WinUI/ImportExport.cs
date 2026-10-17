using System.Text.Json.Nodes;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Import;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;
using Windows.Storage;
using Windows.Storage.Pickers;
using static CantatePresenter.WinUI.Services;

namespace CantatePresenter.WinUI;

/// <summary>Import pieśni, kopie zapasowe .cantatebackup, eksport pieśni i raportu CCLI (jak Import/Eksport w macOS).</summary>
public static class ImportExport
{
    private static nint Handle(MainWindow window) => WinRT.Interop.WindowNative.GetWindowHandle(window);

    private static async Task<IReadOnlyList<StorageFile>> PickFilesAsync(MainWindow window, bool multiple, params string[] extensions)
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        foreach (var extension in extensions) picker.FileTypeFilter.Add(extension);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Handle(window));
        if (multiple) return await picker.PickMultipleFilesAsync() ?? (IReadOnlyList<StorageFile>)[];
        return await picker.PickSingleFileAsync() is StorageFile file ? [file] : [];
    }

    private static async Task<string?> PickSaveAsync(MainWindow window, string suggestedName, string typeName, string extension)
    {
        var picker = new FileSavePicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary, SuggestedFileName = suggestedName };
        picker.FileTypeChoices.Add(typeName, [extension]);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Handle(window));
        return (await picker.PickSaveFileAsync())?.Path;
    }

    /// <summary>Pieśni z jednego pliku; pusta lista, gdy pliku nie da się odczytać.</summary>
    public static List<Song> SongsFromFile(byte[] bytes, string fileName)
    {
        var extension = Path.GetExtension(fileName).TrimStart('.').ToLowerInvariant();
        var baseName = Path.GetFileNameWithoutExtension(fileName);
        if (HolyricsImporter.Extensions.Contains(extension) || extension == "xml") return HolyricsImporter.ReadFile(bytes, fileName).Select(ToSong).ToList();
        var text = TextImport.Decode(bytes);
        if (extension == "json")
        {
            var data = JsonNode.Parse(text);
            var list = data as JsonArray ?? data?["songs"] as JsonArray ?? (data is JsonObject ? new JsonArray(data.DeepClone()) : []);
            return list.OfType<JsonObject>().Where(o => Json.OptStr(o["title"]) is not null).Select(Song.FromJson).ToList();
        }
        if (extension == "usr") return SongSelectImporter.ParseUsr(text) is ImportedSong usr ? [ToSong(usr)] : [];
        if (SongSelectImporter.ChordProExtensions.Contains(extension)) return [ToSong(SongSelectImporter.ParseChordPro(text, baseName))];
        if (SongSelectImporter.IsSongSelectText(text)) return SongSelectImporter.ParseText(text) is ImportedSong song ? [ToSong(song)] : [];
        return [ToSong(TextImport.ParseTextSong(text, baseName))];
    }

    public static Song ToSong(ImportedSong imported)
    {
        var song = Song.Create(imported.Title, imported.Author, imported.Key, imported.Tags, imported.RawLyrics, imported.Chords);
        song.Copyright = imported.Copyright;
        song.CcliNumber = imported.CcliNumber;
        song.Source = imported.Source;
        return song;
    }

    private static readonly string[] ImportExtensions = [".txt", ".json", ".pro", ".cho", ".chopro", ".chordpro", ".usr", ".mufl", ".muf", ".hly", ".holyrics", ".zip", ".xml"];

    public static async Task ImportFilesAsync(MainWindow window)
    {
        var files = await PickFilesAsync(window, true, ImportExtensions);
        if (files.Count == 0) return;
        await ImportPathsAsync(window, files.Select(f => f.Path).ToList());
    }

    /// <summary>Cały folder (z podfolderami), jak „Wybierz cały folder...” w macOS.</summary>
    public static async Task ImportFolderAsync(MainWindow window)
    {
        if (await PickFolderAsync(window) is not string folder) return;
        List<string> paths;
        try
        {
            paths = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)
                .Where(p => ImportExtensions.Contains(Path.GetExtension(p).ToLowerInvariant())).Order(StringComparer.OrdinalIgnoreCase).ToList();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Import/Eksport"), error.Message);
            return;
        }
        if (paths.Count == 0)
        {
            await Dialogs.InfoAsync(window, L("Import/Eksport"), L("Nie znaleziono żadnych pieśni w wybranych plikach."));
            return;
        }
        await ImportPathsAsync(window, paths);
    }

    private static async Task<string?> PickFolderAsync(MainWindow window)
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Handle(window));
        return (await picker.PickSingleFolderAsync())?.Path;
    }

    private static async Task ImportPathsAsync(MainWindow window, IReadOnlyList<string> paths)
    {
        var imported = new List<Song>();
        var unreadable = 0;
        foreach (var path in paths)
        {
            try
            {
                var songs = SongsFromFile(await File.ReadAllBytesAsync(path), Path.GetFileName(path));
                if (songs.Count == 0) unreadable++;
                imported.AddRange(songs);
            }
            catch (Exception error) when (error is IOException or System.Text.Json.JsonException or UnauthorizedAccessException)
            {
                unreadable++;
            }
        }
        // Duplikaty i pieśni o tym samym tytule w bibliotece jak w macOS (SongDeduplicationService); przegląd tylko, gdy jest o czym decydować.
        var report = SongDeduplication.Process(imported, Services.Library.Songs, (key, args) => L(key, args));
        var toAdd = report.NeedsReview ? await ImportReviewDialog.ShowAsync(window, report) : report.UniqueSongs;
        if (toAdd is null) return;
        if (toAdd.Count > 0) Services.Library.AddSongs(toAdd);
        var duplicates = Math.Max(0, imported.Count - toAdd.Count);
        var parts = new List<string> { L("Zaimportowano {0} pieśni.", toAdd.Count) };
        if (duplicates > 0) parts.Add(L("Pominięto duplikaty: {0}.", duplicates));
        if (unreadable > 0) parts.Add(L("Nieczytelne pliki: {0}.", unreadable));
        await Dialogs.InfoAsync(window, L("Import/Eksport"), string.Join(" ", parts));
    }

    public static async Task CreateBackupAsync(MainWindow window)
    {
        if (await PickSaveAsync(window, Path.GetFileNameWithoutExtension(Backup.FileName()), "CantatePresenter", ".cantatebackup") is not string path) return;
        try
        {
            Backup.Create(Services.Library, path, Services.Version);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Błąd tworzenia kopii zapasowej"), error.Message);
        }
    }

    public static async Task RestoreBackupAsync(MainWindow window)
    {
        var files = await PickFilesAsync(window, false, ".cantatebackup", ".holyricsbackup", ".zip");
        if (files.Count == 0) return;
        await RestoreArchiveAsync(window, files[0].Path);
    }

    /// <summary>Przywraca kopię z pliku (wybranego na dysku albo pobranego z Dysku Google) po potwierdzeniu.</summary>
    public static async Task RestoreArchiveAsync(MainWindow window, string path)
    {
        if (!await Dialogs.ConfirmAsync(window, L("Przywrócić kopię? Obecna biblioteka ({0} pieśni) zostanie zastąpiona przez {1} pieśni z kopii. Poprzedni stan można przywrócić przyciskiem „Cofnij ostatnie przywrócenie”.", Services.Library.Songs.Count, SongsInArchive(path)))) return;
        try
        {
            var result = Backup.Restore(path, Services.Library.DataDirectory, (key, args) => L(key, args));
            Services.Library.Reload();
            await Dialogs.InfoAsync(window, L("Import/Eksport"), L("Przywrócono kopię: {0} pieśni, {1} planów.", result.SongsCount, result.PlansCount));
        }
        catch (Exception error) when (error is BackupException or IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Błąd przywracania: {0}", error.Message), "");
        }
    }

    /// <summary>Liczba pieśni w kopii (do pytania przed przywróceniem); „?”, gdy nie da się jej odczytać.</summary>
    private static string SongsInArchive(string path)
    {
        try
        {
            using var zip = System.IO.Compression.ZipFile.OpenRead(path);
            var entry = zip.Entries.Where(e => e.Name == "songs.json").OrderBy(e => e.FullName.Length).FirstOrDefault();
            if (entry is null) return "0";
            using var reader = new StreamReader(entry.Open());
            return ((JsonNode.Parse(reader.ReadToEnd()) as JsonArray)?.Count ?? 0).ToString();
        }
        catch (Exception error) when (error is IOException or InvalidDataException or System.Text.Json.JsonException)
        {
            return "?";
        }
    }

    public static async Task UndoRestoreAsync(MainWindow window)
    {
        try
        {
            Backup.UndoLastRestore(Services.Library.DataDirectory, (key, args) => L(key, args));
            Services.Library.Reload();
        }
        catch (Exception error) when (error is BackupException or IOException)
        {
            await Dialogs.InfoAsync(window, error.Message, "");
        }
    }

    public static async Task ExportSongAsync(MainWindow window, Song? chosen = null)
    {
        if ((chosen ?? Services.Library.SelectedSong) is not Song song) return;
        if (await PickSaveAsync(window, SongExport.SafeFileName(song.Title), "Text", ".txt") is not string path) return;
        try
        {
            await File.WriteAllTextAsync(path, SongExport.ToText(song));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Błąd zapisu"), error.Message);
        }
    }

    /// <summary>Każda pieśń jako osobny plik .txt w wybranym folderze (jak w macOS).</summary>
    public static async Task ExportFolderAsync(MainWindow window, IReadOnlyList<Song> songs)
    {
        if (songs.Count == 0 || await PickFolderAsync(window) is not string folder) return;
        var written = 0;
        try
        {
            foreach (var (fileName, text) in SongExport.Folder(songs))
            {
                await File.WriteAllTextAsync(Path.Combine(folder, fileName), text);
                written++;
            }
            await Dialogs.InfoAsync(window, L("Import/Eksport"), L("Pomyślnie wyeksportowano {0} pieśni jako osobne pliki .txt.", written));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Błąd zapisu"), error.Message);
        }
    }

    /// <summary>Pieśni jako tablica JSON w formacie songs.json (jak „Eksportuj jako plik JSON” w macOS).</summary>
    public static async Task ExportSongsJsonAsync(MainWindow window, IReadOnlyList<Song> songs, string suggestedName)
    {
        if (songs.Count == 0) return;
        if (await PickSaveAsync(window, SongExport.SafeFileName(suggestedName), "JSON", ".json") is not string path) return;
        try
        {
            await File.WriteAllTextAsync(path, SongExport.ToJson(songs));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            await Dialogs.InfoAsync(window, L("Błąd zapisu"), error.Message);
        }
    }

    public static Task ExportLibraryJsonAsync(MainWindow window) => ExportSongsJsonAsync(window, Services.Library.Songs, "Baza_piesni");

    public static async Task ExportCcliAsync(MainWindow window)
    {
        if (await PickSaveAsync(window, $"CCLI_usage_{DateTime.Now:yyyy-MM-dd}", "CSV", ".csv") is not string path) return;
        await File.WriteAllTextAsync(path, Ccli.UsageCsv(Services.Library.CcliUsage));
    }
}
