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

    /// <summary>Te same pieśni (tytuł i tekst bez znaków diakrytycznych i interpunkcji) są pomijane.</summary>
    public static (List<Song> Unique, int Duplicates) WithoutDuplicates(IEnumerable<Song> imported, IEnumerable<Song> library)
    {
        static string Signature(Song s) => TextFold.SearchFold(s.Title) + "\n" + TextFold.SearchFold(s.RawLyrics);
        var known = library.Select(Signature).ToHashSet();
        var unique = new List<Song>();
        var duplicates = 0;
        foreach (var song in imported)
        {
            if (known.Add(Signature(song))) unique.Add(song); else duplicates++;
        }
        return (unique, duplicates);
    }

    public static async Task ImportFilesAsync(MainWindow window)
    {
        var files = await PickFilesAsync(window, true, ".txt", ".json", ".pro", ".cho", ".chopro", ".chordpro", ".usr", ".mufl", ".muf", ".hly", ".holyrics", ".zip", ".xml");
        if (files.Count == 0) return;
        var imported = new List<Song>();
        var unreadable = 0;
        foreach (var file in files)
        {
            try
            {
                var songs = SongsFromFile(await File.ReadAllBytesAsync(file.Path), file.Name);
                if (songs.Count == 0) unreadable++;
                imported.AddRange(songs);
            }
            catch (Exception error) when (error is IOException or System.Text.Json.JsonException or UnauthorizedAccessException)
            {
                unreadable++;
            }
        }
        var (unique, duplicates) = WithoutDuplicates(imported, Services.Library.Songs);
        if (unique.Count > 0) Services.Library.AddSongs(unique);
        var parts = new List<string> { L("Zaimportowano {0} pieśni.", unique.Count) };
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
        if (!await Dialogs.ConfirmAsync(window, L("Przywrócić kopię? Obecna biblioteka ({0} pieśni) zostanie zastąpiona przez {1} pieśni z kopii. Poprzedni stan można przywrócić przyciskiem „Cofnij ostatnie przywrócenie”.", Services.Library.Songs.Count, SongsInArchive(files[0].Path)))) return;
        try
        {
            var result = Backup.Restore(files[0].Path, Services.Library.DataDirectory, (key, args) => L(key, args));
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

    public static async Task ExportSongAsync(MainWindow window)
    {
        if (Services.Library.SelectedSong is not Song song) return;
        var name = string.Concat(song.Title.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        if (await PickSaveAsync(window, name.Length > 0 ? name : "piesn", "Text", ".txt") is not string path) return;
        // Nagłówki eksportu .txt to format danych (nie tłumaczone), jak SongExporter w macOS.
        var header = new[] { $"Tytuł: {song.Title}", song.Author.Length > 0 ? $"Autor: {song.Author}" : null, song.Key.Length > 0 ? $"Tonacja: {song.Key}" : null,
            song.Tags.Count > 0 ? $"Tagi: {string.Join(", ", song.Tags)}" : null }.OfType<string>();
        await File.WriteAllTextAsync(path, $"{string.Join("\n", header)}\n\n{song.RawLyrics}\n");
    }

    public static async Task ExportCcliAsync(MainWindow window)
    {
        if (await PickSaveAsync(window, $"CCLI_usage_{DateTime.Now:yyyy-MM-dd}", "CSV", ".csv") is not string path) return;
        await File.WriteAllTextAsync(path, Ccli.UsageCsv(Services.Library.CcliUsage));
    }
}
