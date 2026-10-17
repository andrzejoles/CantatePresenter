using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Chords;

/// <summary>Opracowanie chwytów: wynik wyszukiwania w bazie (GuitarChordResult w macOS).</summary>
public sealed record ChordsResult(string Title, string Artist, string Key, string ChordsSheet, string Source);

/// <summary>
/// Wbudowana baza chwytów najpopularniejszych pieśni, jak curatedChords w GuitarChordsService (macOS).
/// Dane z chords_catalog.json (eksport z kodu Swift), wyszukiwanie po tytule: dokładnie, potem fragment w jedną lub drugą stronę.
/// Wyszukiwania w internecie z macOS (wyniki wyszukiwarki) Windows nie powtarza.
/// </summary>
public static class ChordsCatalog
{
    public const string SourceName = "Biblioteka Chwytów Holyrics";

    private static readonly Lazy<IReadOnlyList<ChordsResult>> Entries = new(Load);

    public static IReadOnlyList<ChordsResult> All => Entries.Value;

    private static IReadOnlyList<ChordsResult> Load()
    {
        using var stream = typeof(ChordsCatalog).Assembly.GetManifestResourceStream("chords_catalog.json");
        if (stream is null) return [];
        using var reader = new StreamReader(stream);
        return (JsonNode.Parse(reader.ReadToEnd()) as JsonArray ?? [])
            .OfType<JsonObject>()
            .Select(o => new ChordsResult(Json.Str(o["title"]), Json.Str(o["artist"]), Json.Str(o["key"]), Json.Str(o["chords"]), SourceName))
            .ToList();
    }

    public static List<ChordsResult> Search(string title)
    {
        var folded = TextFold.Fold(title.Trim());
        var results = new List<ChordsResult>();
        if (folded.Length == 0) return results;
        results.AddRange(All.Where(e => TextFold.Fold(e.Title) == folded));
        foreach (var entry in All)
        {
            var key = TextFold.Fold(entry.Title);
            if (key != folded && (key.Contains(folded, StringComparison.Ordinal) || folded.Contains(key, StringComparison.Ordinal)) && results.All(r => r.Title != entry.Title))
                results.Add(entry);
        }
        return results;
    }
}
