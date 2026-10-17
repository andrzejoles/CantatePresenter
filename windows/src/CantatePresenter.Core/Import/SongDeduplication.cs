using System.Text.RegularExpressions;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Import;

/// <summary>Para pieśni: główna i jej duplikat, z powodem i podobieństwem 0–100.</summary>
public sealed class DuplicateRecord(Song primarySong, Song duplicateSong, string reason, int similarityScore, bool shouldSkipDuplicate = true)
{
    public string Id { get; } = Guid.NewGuid().ToString();
    public Song PrimarySong { get; } = primarySong;
    public Song DuplicateSong { get; } = duplicateSong;
    public string Reason { get; } = reason;
    public int SimilarityScore { get; } = similarityScore;
    /// <summary>Domyślna decyzja w przeglądzie: pominąć duplikat.</summary>
    public bool ShouldSkipDuplicate { get; } = shouldSkipDuplicate;
}

/// <param name="DuplicateRecords">Duplikaty wewnątrz importu.</param>
/// <param name="ExistingCollisions">Pieśni o tym samym tytule już w bibliotece.</param>
public sealed record ImportReport(int TotalScanned, List<Song> UniqueSongs, List<DuplicateRecord> DuplicateRecords, List<DuplicateRecord> ExistingCollisions)
{
    public bool NeedsReview => DuplicateRecords.Count > 0 || ExistingCollisions.Count > 0;
}

/// <summary>
/// Wykrywanie duplikatów przy imporcie: odpowiednik SongDeduplicationService z wersji macOS (bez wzbogacania
/// metadanych z wbudowanego katalogu), 1:1 z web/src/core/dedup.js. Zgodność pilnuje shared/fixtures/dedup.json.
/// </summary>
public static partial class SongDeduplication
{
    private static readonly string[] UnknownAuthors = ["", "autor nieznany", "nieznany", "brak", "tradycyjna", "nn", "various", "-"];

    /// <summary>Autor pusty albo zastępczy („nieznany”, „brak”, „NN”…).</summary>
    public static bool IsUnknownAuthor(string? author) => UnknownAuthors.Contains(TextFold.Fold(author));

    [GeneratedRegex(@"[^\p{L}\p{M}\p{N}]+")]
    private static partial Regex NonWord();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();

    /// <summary>Słowa tekstu (co najmniej 3 znaki) jako zbiór.</summary>
    public static HashSet<string> LyricsTokens(string foldedLyrics) =>
        NonWord().Split(foldedLyrics).Where(word => word.EnumerateRunes().Count() >= 3).ToHashSet();

    /// <summary>Podobieństwo zbiorów słów (Jaccard) w procentach, zaokrąglone w dół.</summary>
    public static int TokenSimilarity(HashSet<string> a, HashSet<string> b)
    {
        if (a.Count == 0 && b.Count == 0) return 100;
        if (a.Count == 0 || b.Count == 0) return 0;
        var intersection = a.Count(b.Contains);
        var union = a.Count + b.Count - intersection;
        return union > 0 ? (int)Math.Floor((double)intersection / union * 100) : 0;
    }

    /// <summary>Pierwsze 6 słów tekstu (po zwinięciu), klucz szybkiego porównania początku.</summary>
    private static string PrefixKey(string foldedLyrics) =>
        string.Join(" ", Whitespace().Split(foldedLyrics).Where(word => word.Length > 0).Take(6));

    private static void AddIndex(Dictionary<string, List<int>> index, string key, int position)
    {
        if (key.Length == 0) return;
        if (!index.TryGetValue(key, out var list)) index[key] = list = [];
        if (!list.Contains(position)) list.Add(position);
    }

    /// <summary>Dzieli import na pieśni unikalne, duplikaty wewnątrz importu i kolizje z biblioteką (jak macOS).</summary>
    public static ImportReport Process(IReadOnlyList<Song> incoming, IReadOnlyList<Song> existingLibrary, Func<string, object[], string> translate)
    {
        var unique = new List<Song>();
        var uniqueTokens = new List<HashSet<string>>();
        var duplicates = new List<DuplicateRecord>();
        var byTitle = new Dictionary<string, List<int>>();
        var byPrefix = new Dictionary<string, List<int>>();
        var byLyrics = new Dictionary<string, List<int>>();

        foreach (var candidate in incoming)
        {
            var title = TextFold.Fold(candidate.Title);
            var lyrics = TextFold.Fold(candidate.RawLyrics);
            var tokens = LyricsTokens(lyrics);
            var prefix = PrefixKey(lyrics);
            int? match = null;
            var score = 0;
            var reason = "";

            // 1. Identyczny tekst.
            if (lyrics.Length > 0 && byLyrics.TryGetValue(lyrics, out var sameLyrics) && sameLyrics.Count > 0)
            {
                match = sameLyrics[0];
                score = 100;
                reason = translate("Identyczny tekst utworu (100% zgodności)", []);
            }
            else if (byTitle.TryGetValue(title, out var sameTitle))
            {
                // 2. Ten sam tytuł i wystarczająco podobny tekst.
                foreach (var position in sameTitle)
                {
                    var similarity = TokenSimilarity(tokens, uniqueTokens[position]);
                    if (similarity >= 35 || tokens.Count == 0)
                    {
                        match = position;
                        score = Math.Max(score, similarity);
                        reason = translate("Ten sam tytuł i zgodność tekstu ({0}%)", [similarity]);
                        break;
                    }
                }
            }
            // 3. Ten sam początek (6 słów) i bardzo podobny tekst.
            if (match is null && prefix.Length > 0 && byPrefix.TryGetValue(prefix, out var samePrefix))
            {
                foreach (var position in samePrefix)
                {
                    var similarity = TokenSimilarity(tokens, uniqueTokens[position]);
                    if (similarity >= 70)
                    {
                        match = position;
                        score = similarity;
                        reason = translate("Identyczny początek i bardzo wysokie podobieństwo tekstu ({0}%)", [similarity]);
                        break;
                    }
                }
            }

            if (match is int found)
            {
                var primary = unique[found];
                if (!IsUnknownAuthor(candidate.Author) && IsUnknownAuthor(primary.Author))
                {
                    // Nowa pieśń ma autora, a dotychczasowa główna nie: zamiana; nowa główna trafia do indeksów (N8).
                    unique[found] = candidate;
                    uniqueTokens[found] = tokens;
                    AddIndex(byTitle, title, found);
                    AddIndex(byPrefix, prefix, found);
                    AddIndex(byLyrics, lyrics, found);
                    duplicates.Add(new DuplicateRecord(candidate, primary, reason, score));
                }
                else
                {
                    duplicates.Add(new DuplicateRecord(primary, candidate, reason, score));
                }
            }
            else
            {
                var position = unique.Count;
                unique.Add(candidate);
                uniqueTokens.Add(tokens);
                AddIndex(byTitle, title, position);
                AddIndex(byPrefix, prefix, position);
                AddIndex(byLyrics, lyrics, position);
            }
        }

        // Kolizje z biblioteką: wszystkie pieśni o danym tytule, wygrywa najbardziej podobna.
        var collisions = new List<DuplicateRecord>();
        if (existingLibrary.Count > 0)
        {
            var libraryByTitle = existingLibrary.GroupBy(song => TextFold.Fold(song.Title)).ToDictionary(group => group.Key, group => group.ToList());
            for (var index = 0; index < unique.Count; index++)
            {
                Song? best = null;
                var bestScore = -1;
                foreach (var librarySong in libraryByTitle.GetValueOrDefault(TextFold.Fold(unique[index].Title)) ?? [])
                {
                    var similarity = TokenSimilarity(uniqueTokens[index], LyricsTokens(TextFold.Fold(librarySong.RawLyrics)));
                    if (similarity > bestScore) { best = librarySong; bestScore = similarity; }
                }
                // Prawie identyczne pieśni (np. ponowny import własnego eksportu) domyślnie pomijane.
                if (best is not null)
                    collisions.Add(new DuplicateRecord(best, unique[index], translate("Utwór o tym tytule istnieje już w bibliotece ({0}% zgodności)", [bestScore]), bestScore, bestScore >= 90));
            }
        }

        return new ImportReport(incoming.Count, unique, duplicates, collisions);
    }

    /// <summary>
    /// Pieśni do dodania po przeglądzie: unikalne bez pominiętych kolizji oraz duplikaty, których nie pominięto
    /// (jako „(wersja alternatywna)”). Brak decyzji w słowniku = wartość domyślna rekordu.
    /// </summary>
    public static List<Song> SongsToCommit(ImportReport report, IReadOnlyDictionary<string, bool>? duplicateSkips = null, IReadOnlyDictionary<string, bool>? collisionSkips = null)
    {
        var skipped = report.ExistingCollisions
            .Where(r => collisionSkips?.GetValueOrDefault(r.Id, r.ShouldSkipDuplicate) ?? r.ShouldSkipDuplicate)
            .Select(r => r.DuplicateSong)
            .ToHashSet(ReferenceEqualityComparer.Instance);
        var result = report.UniqueSongs.Where(song => !skipped.Contains(song)).ToList();
        foreach (var r in report.DuplicateRecords)
        {
            if (duplicateSkips?.GetValueOrDefault(r.Id, r.ShouldSkipDuplicate) ?? r.ShouldSkipDuplicate) continue;
            var copy = Song.FromJson(r.DuplicateSong.ToJson());
            copy.Title = $"{r.DuplicateSong.Title} (wersja alternatywna)";
            result.Add(copy);
        }
        return result;
    }
}
