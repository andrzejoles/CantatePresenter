using System.Globalization;
using System.IO.Compression;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Data;

public sealed class BackupException(string message) : Exception(message);

/// <summary>
/// Kopia zapasowa .cantatebackup zgodna z macOS i wersją webową (ZIP: pliki danych + manifest.json) oraz przywracanie
/// jak BackupRestorer (S5): walidacja, podmiana całego katalogu, poprzedni stan zachowany do cofnięcia.
/// </summary>
public static class Backup
{
    public static readonly string[] AllowedItems = ["songs.json", "plans.json", "settings.json", "custom_languages.json", "standby.html", "logos", "templates", "ccli_usage.json"];
    public const int PreviousStatesLimit = 3;

    /// <summary>Nazwa pliku jak w macOS: CantatePresenter_Backup_RRRR-MM-DD_GG-MM-SS.cantatebackup.</summary>
    public static string FileName(DateTime? date = null) =>
        $"CantatePresenter_Backup_{(date ?? DateTime.Now).ToString("yyyy-MM-dd_HH-mm-ss", CultureInfo.InvariantCulture)}.cantatebackup";

    public static void Create(Library library, string archivePath, string appVersion, string? comment = null)
    {
        var included = new List<string>();
        var temporary = archivePath + ".tmp";
        using (var zip = ZipFile.Open(temporary, ZipArchiveMode.Create))
        {
            foreach (var item in AllowedItems)
            {
                var source = Path.Combine(library.DataDirectory, item);
                if (File.Exists(source))
                {
                    zip.CreateEntryFromFile(source, item);
                    included.Add(item);
                }
                else if (Directory.Exists(source))
                {
                    foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
                    {
                        zip.CreateEntryFromFile(file, Path.GetRelativePath(library.DataDirectory, file).Replace('\\', '/'));
                    }
                    included.Add(item + "/");
                }
            }
            var manifest = new JsonObject
            {
                ["activeLogoId"] = library.Settings.ActiveLogoId,
                ["appLanguage"] = library.Settings.AppLanguage,
                ["appName"] = "CantatePresenter",
                ["createdAt"] = Json.IsoDate(),
                ["deviceName"] = Environment.MachineName,
                ["includedFiles"] = new JsonArray(included.Select(i => (JsonNode?)i).ToArray()),
                ["plansCount"] = library.Plans.Count,
                ["schemaVersion"] = AppSettings.SchemaVersionCurrent,
                ["songsCount"] = library.Songs.Count,
                ["version"] = appVersion,
            };
            if (comment is not null) manifest["comment"] = comment;
            using var writer = new StreamWriter(zip.CreateEntry("manifest.json").Open());
            writer.Write(manifest.ToJsonString(Json.Pretty));
        }
        File.Move(temporary, archivePath, overwrite: true);
    }

    public sealed record RestoreResult(int SongsCount, int PlansCount, string PreviousState);

    /// <summary>Przywraca kopię (.cantatebackup / .zip; katalog danych może być zagnieżdżony w archiwum).</summary>
    public static RestoreResult Restore(string archivePath, string dataDirectory, Func<string, object[], string> t)
    {
        var extract = Path.Combine(Path.GetTempPath(), "CantateRestore_" + Guid.NewGuid());
        try
        {
            try
            {
                ZipFile.ExtractToDirectory(archivePath, extract);
            }
            catch (InvalidDataException)
            {
                throw new BackupException(t("To nie jest plik kopii zapasowej (.cantatebackup lub .zip).", []));
            }
            var root = File.Exists(Path.Combine(extract, "songs.json"))
                ? extract
                : Directory.GetDirectories(extract).FirstOrDefault(d => File.Exists(Path.Combine(d, "songs.json")))
                  ?? throw new BackupException(t("Kopia zapasowa nie zawiera pliku songs.json.", []));
            var (songs, plans) = Validate(root, t);
            var previous = Swap(root, dataDirectory);
            return new RestoreResult(songs, plans, previous);
        }
        finally
        {
            if (Directory.Exists(extract)) Directory.Delete(extract, recursive: true);
        }
    }

    private static (int Songs, int Plans) Validate(string root, Func<string, object[], string> t)
    {
        // Kopia z nowszej aplikacji: pola, których ta wersja nie zna, zginęłyby przy pierwszym zapisie.
        foreach (var name in new[] { "manifest.json", "settings.json" })
        {
            var path = Path.Combine(root, name);
            if (!File.Exists(path)) continue;
            try
            {
                if (JsonNode.Parse(File.ReadAllText(path)) is JsonObject obj && Json.Int(obj["schemaVersion"]) is int version && version > AppSettings.SchemaVersionCurrent)
                {
                    throw new BackupException(t("Kopię zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Zaktualizuj aplikację przed przywróceniem.", [version, AppSettings.SchemaVersionCurrent]));
                }
            }
            catch (System.Text.Json.JsonException) when (name == "manifest.json")
            {
                // Uszkodzony manifest nie przeszkadza (macOS też go wtedy pomija).
            }
        }
        JsonNode? Parse(string name)
        {
            var path = Path.Combine(root, name);
            if (!File.Exists(path)) return null;
            try
            {
                return JsonNode.Parse(File.ReadAllText(path));
            }
            catch (System.Text.Json.JsonException error)
            {
                throw new BackupException(t("Plik {0} w kopii zapasowej jest uszkodzony: {1}", [name, error.Message]));
            }
        }
        if (Parse("songs.json") is not JsonArray songs) throw new BackupException(t("Kopia zapasowa nie zawiera pliku songs.json.", []));
        var plans = Parse("plans.json") as JsonArray;
        Parse("settings.json");
        return (songs.Count, plans?.Count ?? 0);
    }

    private static string PreviousPrefix(string dataDirectory) => Path.GetFileName(dataDirectory.TrimEnd(Path.DirectorySeparatorChar)) + " przed przywróceniem ";

    private static string Swap(string root, string dataDirectory)
    {
        var parent = Path.GetDirectoryName(dataDirectory.TrimEnd(Path.DirectorySeparatorChar))!;
        var staging = Path.Combine(parent, $".{Path.GetFileName(dataDirectory)}-przywracanie-{Guid.NewGuid()}");
        try
        {
            // Obecne dane (np. history/) zostają, podmieniane są tylko pliki z kopii.
            if (Directory.Exists(dataDirectory)) CopyDirectory(dataDirectory, staging); else Directory.CreateDirectory(staging);
            foreach (var item in AllowedItems)
            {
                var source = Path.Combine(root, item);
                var target = Path.Combine(staging, item);
                if (File.Exists(source))
                {
                    File.Copy(source, target, overwrite: true);
                }
                else if (Directory.Exists(source))
                {
                    if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
                    CopyDirectory(source, target);
                }
            }
            var previous = Path.Combine(parent, PreviousPrefix(dataDirectory) + DateTime.Now.ToString("yyyy-MM-dd HH-mm-ss-fff", CultureInfo.InvariantCulture));
            if (Directory.Exists(dataDirectory)) Directory.Move(dataDirectory, previous); else Directory.CreateDirectory(previous);
            Directory.Move(staging, dataDirectory);
            PruneOldStates(dataDirectory);
            return previous;
        }
        catch
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
            throw;
        }
    }

    public static IReadOnlyList<string> PreviousStates(string dataDirectory)
    {
        var parent = Path.GetDirectoryName(dataDirectory.TrimEnd(Path.DirectorySeparatorChar))!;
        if (!Directory.Exists(parent)) return [];
        var prefix = PreviousPrefix(dataDirectory);
        return Directory.GetDirectories(parent).Where(d => Path.GetFileName(d).StartsWith(prefix, StringComparison.Ordinal))
            .OrderByDescending(d => Path.GetFileName(d), StringComparer.Ordinal).ToList();
    }

    private static void PruneOldStates(string dataDirectory)
    {
        foreach (var old in PreviousStates(dataDirectory).Skip(PreviousStatesLimit)) Directory.Delete(old, recursive: true);
    }

    public static bool CanUndo(string dataDirectory) => PreviousStates(dataDirectory).Count > 0;

    /// <summary>Wraca do danych sprzed ostatniego przywracania.</summary>
    public static void UndoLastRestore(string dataDirectory, Func<string, object[], string> t)
    {
        var latest = PreviousStates(dataDirectory).FirstOrDefault() ?? throw new BackupException(t("Brak poprzedniego stanu do przywrócenia.", []));
        var parent = Path.GetDirectoryName(dataDirectory.TrimEnd(Path.DirectorySeparatorChar))!;
        var aside = Path.Combine(parent, $".{Path.GetFileName(dataDirectory)}-cofniete-{Guid.NewGuid()}");
        Directory.Move(dataDirectory, aside);
        Directory.Move(latest, dataDirectory);
        Directory.Delete(aside, recursive: true);
    }

    private static void CopyDirectory(string source, string target)
    {
        Directory.CreateDirectory(target);
        foreach (var file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(target, Path.GetFileName(file)));
        foreach (var directory in Directory.GetDirectories(source)) CopyDirectory(directory, Path.Combine(target, Path.GetFileName(directory)));
    }
}
