using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Data;

public enum LoadStatus { Missing, Loaded, Unreadable }

public sealed record LoadResult(LoadStatus Status, JsonNode? Value, string? QuarantinedCopy, string? Error);

/// <summary>
/// Odczyt i zapis plików JSON bez ryzyka utraty danych, jak JSONFileStore w macOS (K1): brak pliku ≠ plik nieczytelny,
/// nieczytelny plik trafia do kopii „nazwa.corrupt-data.json”, przed każdym zapisem poprzednia wersja idzie do history/.
/// </summary>
public sealed class JsonFileStore(int historyLimit = 5)
{
    public const string HistoryDirectoryName = "history";

    public LoadResult Load(string path)
    {
        if (!File.Exists(path)) return new LoadResult(LoadStatus.Missing, null, null, null);
        try
        {
            var text = File.ReadAllText(path, Encoding.UTF8);
            var node = JsonNode.Parse(text) ?? throw new JsonException("null");
            return new LoadResult(LoadStatus.Loaded, node, null, null);
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            return new LoadResult(LoadStatus.Unreadable, null, Quarantine(path), error.Message);
        }
    }

    private static string Stamp(string format = "yyyy-MM-dd_HH-mm-ss") => DateTime.Now.ToString(format, CultureInfo.InvariantCulture);

    /// <summary>Kopia nieczytelnego pliku obok oryginału; oryginał zostaje na miejscu.</summary>
    private static string? Quarantine(string path)
    {
        try
        {
            var directory = Path.GetDirectoryName(path)!;
            var name = Path.GetFileNameWithoutExtension(path);
            var candidate = Path.Combine(directory, $"{name}.corrupt-{Stamp()}.json");
            for (var counter = 2; File.Exists(candidate); counter++) candidate = Path.Combine(directory, $"{name}.corrupt-{Stamp()}-{counter}.json");
            File.Copy(path, candidate);
            return candidate;
        }
        catch (IOException)
        {
            return null;
        }
    }

    public void Save(JsonNode value, string path)
    {
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        if (File.Exists(path))
        {
            var history = Path.Combine(directory, HistoryDirectoryName);
            Directory.CreateDirectory(history);
            var name = Path.GetFileNameWithoutExtension(path);
            File.Copy(path, Path.Combine(history, $"{name}-{Stamp("yyyy-MM-dd_HH-mm-ss-fff")}.json"), overwrite: true);
            foreach (var old in Directory.GetFiles(history, $"{name}-*.json").Order(StringComparer.Ordinal).SkipLast(historyLimit)) File.Delete(old);
        }
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, value.ToJsonString(Json.Pretty), new UTF8Encoding(false));
        File.Move(temporary, path, overwrite: true);
    }
}
