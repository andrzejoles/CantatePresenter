using System.Text.RegularExpressions;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Online;

/// <summary>Kandydat z wyszukiwania (OnlineSearchResult w macOS).</summary>
public sealed record LookupCandidate(string Title, string Artist, string Source, string Snippet);

/// <summary>Propozycja tytułu i autora dla pieśni (SongMatchProposal w macOS).</summary>
public sealed class LookupProposal(string songId, string currentTitle, string currentAuthor, string proposedTitle, string proposedAuthor, string source, int confidence)
{
    public string SongId { get; } = songId;
    public string CurrentTitle { get; } = currentTitle;
    public string CurrentAuthor { get; } = currentAuthor;
    public string ProposedTitle { get; } = proposedTitle;
    public string ProposedAuthor { get; } = proposedAuthor;
    public string Source { get; } = source;
    public int Confidence { get; } = confidence;
    public bool IsSelected { get; set; } = confidence >= 45;
    public bool IsApplied { get; set; }
    public bool AcceptAuthor { get; set; } = true;
}

/// <summary>
/// Wyszukiwarka tytułu i autora: zapytanie z pierwszych słów tekstu i ocena kandydatów, 1:1 z AuthorTitleLookupService (macOS).
/// Kandydaci pochodzą z Wikiźródeł (to samo źródło co okno „Online”).
/// </summary>
public static partial class AuthorTitleLookup
{
    [GeneratedRegex(@"^[0-9]+[.\-_\s]+")]
    private static partial Regex LeadingNumber();

    [GeneratedRegex(@"[^\p{L}\p{M}\p{N}]+")]
    private static partial Regex NonAlphanumeric();

    /// <summary>Pierwsza sensowna linia tekstu (do 6 słów), a bez niej tytuł bez numeru i „.txt”.</summary>
    public static string SuggestedQuery(Song song)
    {
        foreach (var slide in song.Slides)
        {
            var lines = slide.Text.Split('\n').Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith('[') && !l.StartsWith("1.", StringComparison.Ordinal) && !l.StartsWith("2.", StringComparison.Ordinal))
                .ToList();
            if (lines.FirstOrDefault() is string first && first.Length >= 8)
            {
                var words = first.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (words.Length >= 2) return string.Join(" ", words.Take(6));
            }
        }
        var title = LeadingNumber().Replace(song.Title, "");
        if (title.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) title = title[..^4];
        return title.Trim();
    }

    private static HashSet<string> Words(string folded) =>
        NonAlphanumeric().Split(folded).Where(w => w.EnumerateRunes().Count() > 2).ToHashSet();

    /// <summary>Ocena 15–99: tytuł, wspólne słowa tekstu, kara za brak autora (jak w macOS).</summary>
    public static int Score(Song song, string candidateTitle, string candidateArtist, string candidateLyrics)
    {
        var score = 30;
        var songTitle = TextFold.Fold(song.Title);
        var title = TextFold.Fold(candidateTitle);
        if (title == songTitle) score += 40;
        else if (title.Contains(songTitle, StringComparison.Ordinal) || songTitle.Contains(title, StringComparison.Ordinal)) score += 25;
        var songWords = Words(TextFold.Fold(song.RawLyrics));
        var words = Words(TextFold.Fold(candidateLyrics));
        if (songWords.Count > 0 && words.Count > 0)
        {
            var common = songWords.Count(words.Contains);
            var ratio = (double)common / Math.Min(songWords.Count, 25);
            score += (int)Math.Min(35.0, ratio * 35.0);
        }
        if (candidateArtist.Trim().Length == 0) score -= 10;
        return Math.Min(99, Math.Max(15, score));
    }

    /// <summary>Najlepsza propozycja spośród wyników (z tekstami do porównania) albo null.</summary>
    public static LookupProposal? Best(Song song, IEnumerable<(LookupCandidate Candidate, string Lyrics)> results)
    {
        var scored = results.Select(r => (r.Candidate, Score: Score(song, r.Candidate.Title, r.Candidate.Artist, r.Lyrics)))
            .OrderByDescending(r => r.Score).ToList();
        if (scored.Count == 0) return null;
        var (top, confidence) = scored[0];
        return new LookupProposal(song.Id, song.Title, song.Author, top.Title, top.Artist, top.Source, confidence);
    }

    /// <summary>Kandydat z wyniku Wikiźródeł (fragment: pierwsze dwie linie tekstu).</summary>
    public static LookupCandidate FromWikisource(WikisourceResult result, string source) =>
        new(result.Title, result.Author, source, string.Join(" / ", result.Lyrics.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).Take(2)));
}
