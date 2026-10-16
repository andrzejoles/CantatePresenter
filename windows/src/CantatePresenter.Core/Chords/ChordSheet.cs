using System.Text.RegularExpressions;
using CantatePresenter.Core.Import;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Chords;

/// <summary>Wiersz dla muzyków: akordy nad tekstem (kolumny jak w arkuszu) albo sam tekst.</summary>
public sealed record ChordLine(string? Chords, string Text);

public sealed record ChordSheetResult(IReadOnlyList<ChordLine> Lines, string? BorrowedFrom);

/// <summary>
/// Dopasowanie arkusza chwytów do slajdu dla ekranu muzyków: odpowiednik ChordSheet z wersji macOS (wzorzec).
/// Zgodność pilnują shared/fixtures/chordsheet.json.
/// </summary>
public static partial class ChordSheet
{
    private sealed class Section
    {
        public string? Header;
        public List<ChordLine> Lines = [];
        public bool IsChorus;
        public bool HasChords => Lines.Any(l => l.Chords is not null);
        public List<ChordLine> LyricLines => Lines.Where(l => l.Text.Length > 0).ToList();
    }

    private static readonly HashSet<string> HeaderWords = ["ref", "r", "refren", "chorus", "zwrotka", "z", "verse", "bridge", "coda", "koda"];

    [GeneratedRegex(@"^[A-Ha-h](?:is|es|s|#|b)?(?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*(?:/[A-Ha-h](?:is|es|s|#|b)?)?", RegexOptions.CultureInvariant)]
    private static partial Regex ChordAtStart();

    [GeneratedRegex(@"\s*\(([^()]+)\)\s*$")]
    private static partial Regex TrailingGroup();

    [GeneratedRegex(@"^\p{N}+$")]
    private static partial Regex AllDigits();

    private static string[] Tokens(string s) => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
        .SelectMany(t => t.Split(',', StringSplitOptions.RemoveEmptyEntries)).ToArray();

    /// <summary>Słowa do porównania: bez znaków diakrytycznych, interpunkcji i oznaczeń sekcji („Ref.”).</summary>
    public static List<string> Words(string text) =>
        TextFold.SearchFold(text).Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => !HeaderWords.Contains(w) && !AllDigits().IsMatch(w)).ToList();

    private static bool IsHeader(string line)
    {
        var trimmed = LyricsParser.TrimSpaces(line);
        if (trimmed.StartsWith('[') && trimmed.EndsWith(']')) return true;
        return trimmed.EndsWith(':') && trimmed.Length <= 30 && !ChordTransposer.IsChordLine(trimmed[..^1]);
    }

    /// <summary>„Afis” → ["A", "fis"]; null, gdy to nie same akordy.</summary>
    public static List<string>? SplitConcatenatedChords(string token)
    {
        var rest = token;
        var chords = new List<string>();
        while (rest.Length > 0)
        {
            var match = ChordAtStart().Match(rest);
            if (!match.Success || match.Length == 0) return null;
            chords.Add(match.Value);
            rest = rest[match.Length..];
        }
        return chords.Count > 0 ? chords : null;
    }

    private static List<string>? ChordsIn(string group)
    {
        var chords = new List<string>();
        foreach (var token in Tokens(group))
        {
            var split = SplitConcatenatedChords(token);
            if (split is null) return null;
            chords.AddRange(split);
        }
        return chords.Count > 0 ? chords : null;
    }

    private static string? ParenthesizedChordLine(string line)
    {
        if (!line.StartsWith('(') || !line.EndsWith(')') || line.Length <= 2) return null;
        var chords = ChordsIn(line[1..^1]);
        return chords is null ? null : string.Join(" ", chords);
    }

    private static ChordLine? TrailingChords(string line)
    {
        var match = TrailingGroup().Match(line);
        if (!match.Success) return null;
        var chords = ChordsIn(match.Groups[1].Value);
        var text = LyricsParser.TrimSpaces(line[..match.Index]);
        return chords is not null && text.Length > 0 ? new ChordLine(string.Join(" ", chords), text) : null;
    }

    private static List<Section> Sections(string sheet)
    {
        var result = new List<Section>();
        var current = new Section();
        string? pending = null;

        void Finish()
        {
            if (pending is not null)
            {
                current.Lines.Add(new ChordLine(pending, ""));
                pending = null;
            }
            if (current.Lines.Count > 0)
            {
                var header = (current.Header ?? "").ToLowerInvariant();
                var firstText = TextFold.SearchFold(current.Lines.FirstOrDefault(l => l.Text.Length > 0)?.Text ?? "");
                current.IsChorus = header.Contains("ref") || header.Contains("chorus") || firstText.StartsWith("ref ") || firstText.StartsWith("r ");
                result.Add(current);
            }
            current = new Section();
        }

        foreach (var rawLine in sheet.Replace("\r\n", "\n").Split('\n'))
        {
            var line = rawLine.Replace("\t", "    ");
            var trimmed = LyricsParser.TrimSpaces(line);
            var parenthesized = trimmed.Length > 0 ? ParenthesizedChordLine(trimmed) : null;
            (string? Chords, string Lyrics)? bracketed = trimmed.Contains('[') ? SongSelectImporter.SplitChords(trimmed) : null;
            if (trimmed.Length == 0)
            {
                Finish();
            }
            else if (parenthesized is not null)
            {
                if (pending is not null) current.Lines.Add(new ChordLine(pending, ""));
                pending = parenthesized;
            }
            else if (ChordTransposer.IsChordLine(line))
            {
                if (pending is not null) current.Lines.Add(new ChordLine(pending, ""));
                pending = line.Trim('\n', '\r');
            }
            else if (IsHeader(trimmed))
            {
                if (current.Lines.Count > 0 || pending is not null) Finish();
                current.Header = trimmed.Trim('[', ']', ':');
            }
            else if (bracketed?.Chords is string bracketChords)
            {
                current.Lines.Add(new ChordLine(bracketChords, bracketed.Value.Lyrics));
            }
            else if (TrailingChords(trimmed) is ChordLine inline)
            {
                // Chwyty przy wierszu wygrywają; wcześniejsza linia samych akordów to wstęp.
                if (pending is not null)
                {
                    current.Lines.Add(new ChordLine(pending, ""));
                    pending = null;
                }
                current.Lines.Add(inline);
            }
            else
            {
                current.Lines.Add(new ChordLine(pending, trimmed));
                pending = null;
            }
        }
        Finish();
        return result;
    }

    private static double Coverage(List<string> slideWords, IEnumerable<string> lines)
    {
        if (slideWords.Count == 0) return 0;
        var available = new Dictionary<string, int>();
        foreach (var word in Words(string.Join(" ", lines))) available[word] = available.GetValueOrDefault(word) + 1;
        var found = 0;
        foreach (var word in slideWords)
        {
            if (available.GetValueOrDefault(word) > 0)
            {
                available[word]--;
                found++;
            }
        }
        return (double)found / slideWords.Count;
    }

    /// <summary>Wiersze slajdu z chwytami, transponowanymi o <paramref name="semitones"/> względem pierwszego akordu pieśni.</summary>
    public static ChordSheetResult LinesForSlide(string slideText, string slideType, string? sheet, int semitones = 0)
    {
        var slideLines = slideText.Split('\n');
        var plain = new ChordSheetResult(slideLines.Select(t => new ChordLine(null, t)).ToList(), null);
        if (string.IsNullOrWhiteSpace(sheet)) return plain;
        var all = Sections(sheet);
        if (!all.Any(s => s.HasChords)) return plain;
        var slideWords = Words(slideText);
        var slideSet = slideWords.ToHashSet();
        var isChorus = slideType == SlideTypes.Chorus;

        var flat = new List<(int Section, int Position, ChordLine Line)>();
        for (var s = 0; s < all.Count; s++)
        {
            var lyrics = all[s].LyricLines;
            for (var p = 0; p < lyrics.Count; p++) flat.Add((s, p, lyrics[p]));
        }
        var candidate = flat.Select(entry =>
        {
            var lineWords = Words(entry.Line.Text);
            return lineWords.Count > 0 && (double)lineWords.Count(slideSet.Contains) / lineWords.Count >= 0.6;
        }).ToList();
        (int Start, int End)? best = null;
        int? start = null;
        for (var index = 0; index <= flat.Count; index++)
        {
            if (index < flat.Count && candidate[index])
            {
                start ??= index;
            }
            else if (start is int runStart)
            {
                if (index - runStart > (best is { } b ? b.End - b.Start : 0)) best = (runStart, index);
                start = null;
            }
        }

        List<ChordLine> lines;
        string? borrowedFrom = null;
        var run = best is { } r ? flat.GetRange(r.Start, r.End - r.Start) : [];
        if (best is not null && Coverage(slideWords, run.Select(e => e.Line.Text)) >= 0.5)
        {
            lines = run.Select(e => e.Line).ToList();
            var runIsChorus = all[run[0].Section].IsChorus;
            var donor = lines.Any(l => l.Chords is not null) ? null : all.FirstOrDefault(s => s.HasChords && s.IsChorus == runIsChorus);
            if (donor is not null)
            {
                var donorLines = donor.LyricLines;
                for (var offset = 0; offset < run.Count; offset++)
                {
                    if (run[offset].Position < donorLines.Count) lines[offset] = lines[offset] with { Chords = donorLines[run[offset].Position].Chords };
                }
                borrowedFrom = donor.Header ?? donorLines.FirstOrDefault()?.Text;
            }
        }
        else
        {
            var donor = all.FirstOrDefault(s => s.HasChords && s.IsChorus == isChorus) ?? all.FirstOrDefault(s => s.HasChords);
            if (donor is null) return plain;
            // Inna wersja tekstu niż w arkuszu: chwyty pierwszej sekcji tego rodzaju, wiersz po wierszu.
            var donorLines = donor.LyricLines;
            lines = slideLines.Select((text, index) => new ChordLine(index < donorLines.Count ? donorLines[index].Chords : null, text)).ToList();
            borrowedFrom = donor.Header ?? donorLines.FirstOrDefault()?.Text;
        }

        if (semitones % 12 != 0)
        {
            // Wszystkie linie chwytów razem z pierwszym akordem pieśni: ta sama tonacja i zapis na każdym slajdzie.
            var reference = all.SelectMany(s => s.Lines).FirstOrDefault(l => l.Chords is not null)?.Chords ?? "";
            var indices = Enumerable.Range(0, lines.Count).Where(i => lines[i].Chords is not null).ToList();
            var joined = string.Join("\n", new[] { reference }.Concat(indices.Select(i => lines[i].Chords!)));
            var transposed = ChordTransposer.Transpose(joined, semitones).Split('\n').Skip(1).ToList();
            for (var k = 0; k < indices.Count; k++) lines[indices[k]] = lines[indices[k]] with { Chords = transposed[k] };
        }
        return new ChordSheetResult(lines, borrowedFrom);
    }
}
