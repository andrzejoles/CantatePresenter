using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Chords;

/// <summary>Akord: tonika (0–11), małe litery = moll, dopisek, bas.</summary>
public sealed record Chord(int Root, bool IsLowercase, string Suffix, int? Bass, bool BassIsLowercase, bool German);

/// <summary>
/// Transpozycja arkusza akordów: odpowiednik ChordTransposer z wersji macOS (wzorzec).
/// Notacja polska/niemiecka: H = H, B = B♭; krzyżyki i bemole jako #/b albo is/es.
/// Zgodność pilnują shared/fixtures/transpose.json.
/// </summary>
public static partial class ChordTransposer
{
    private static readonly Dictionary<char, int> Natural = new() { ['C'] = 0, ['D'] = 2, ['E'] = 4, ['F'] = 5, ['G'] = 7, ['A'] = 9, ['B'] = 10, ['H'] = 11 };
    private static readonly string[] Sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"];
    private static readonly string[] Flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "B", "H"];
    private static readonly string[] GermanSharp = ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "Ais", "H"];
    private static readonly string[] GermanFlat = ["C", "Des", "D", "Es", "E", "F", "Ges", "G", "As", "A", "B", "H"];
    /// <summary>Tonacje zapisywane z bemolami: F, B, Es, As, Des dur oraz d, g, c, f, b moll.</summary>
    private static readonly HashSet<int> FlatMajor = [5, 10, 3, 8, 1];
    private static readonly HashSet<int> FlatMinor = [2, 7, 0, 5, 10];

    [GeneratedRegex(@"^([A-Ha-h])(is|es|s|#|b)?((?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*)(?:/([A-Ha-h])(is|es|s|#|b)?)?$", RegexOptions.CultureInvariant)]
    private static partial Regex ChordPattern();

    [GeneratedRegex(@"^x?\d+x?$")]
    private static partial Regex Repeat();

    private static int? Pitch(char letter, string? accidental)
    {
        var upper = char.ToUpperInvariant(letter);
        if (!Natural.TryGetValue(upper, out var natural)) return null;
        var offset = accidental switch
        {
            "#" or "is" => 1,
            "b" when upper == 'B' => 0,
            "b" or "es" or "s" => -1,
            _ => 0,
        };
        return (natural + offset + 12) % 12;
    }

    public static Chord? Parse(string token)
    {
        var m = ChordPattern().Match(token);
        if (!m.Success) return null;
        var accidental = m.Groups[2].Success ? m.Groups[2].Value : null;
        var root = Pitch(m.Groups[1].Value[0], accidental);
        if (root is null) return null;
        int? bass = null;
        var bassLower = false;
        string? bassAccidental = null;
        if (m.Groups[4].Success)
        {
            bassAccidental = m.Groups[5].Success ? m.Groups[5].Value : null;
            bass = Pitch(m.Groups[4].Value[0], bassAccidental);
            if (bass is null) return null;
            bassLower = char.IsLower(m.Groups[4].Value[0]);
        }
        var german = new[] { accidental, bassAccidental }.Any(a => a is "is" or "es" or "s");
        return new Chord(root.Value, char.IsLower(m.Groups[1].Value[0]), m.Groups[3].Value, bass, bassLower, german);
    }

    private static bool IsMinor(Chord c) =>
        c.IsLowercase || (c.Suffix.StartsWith('m') && !c.Suffix.StartsWith("maj")) || c.Suffix.StartsWith("min");

    private static string StripBrackets(string s) => s.Trim('(', ')', '[', ']');

    private static List<string> Words(string line) =>
        line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToList();

    /// <summary>Wyraz dopuszczalny w linii akordowej, ale niebędący akordem (`|`, `-`, `x2`, `(x2)`).</summary>
    private static bool IsNeutral(string token)
    {
        var stripped = StripBrackets(token);
        if (stripped.Length == 0 || stripped.All(c => !char.IsLetterOrDigit(c))) return true;
        return Repeat().IsMatch(stripped);
    }

    /// <summary>Linia złożona wyłącznie z akordów (i znaków pomocniczych).</summary>
    public static bool IsChordLine(string line)
    {
        var chords = 0;
        foreach (var token in Words(line))
        {
            if (Parse(StripBrackets(token)) is not null) chords++;
            else if (!IsNeutral(token)) return false;
        }
        return chords > 0;
    }

    private sealed record Group(int Start, int End, string Content, char Open, char Close);

    /// <summary>Grupy `[...]` i `(...)` złożone z samych akordów, np. `[C]`, `(D A)`; `[Refren]` się nie liczy.</summary>
    private static List<Group> InlineGroups(string line)
    {
        var groups = new List<Group>();
        var i = 0;
        while (i < line.Length)
        {
            var c = line[i];
            char? close = c == '[' ? ']' : c == '(' ? ')' : null;
            var end = close is null ? -1 : line.IndexOf(close.Value, i + 1);
            if (close is not null && end >= 0)
            {
                var content = line[(i + 1)..end];
                var tokens = Words(content);
                if (tokens.Count > 0 && tokens.All(t => Parse(t) is not null)) groups.Add(new Group(i, end + 1, content, c, close.Value));
                i = end + 1;
            }
            else
            {
                i++;
            }
        }
        return groups;
    }

    private static IEnumerable<Chord> ChordsIn(string line)
    {
        if (IsChordLine(line)) return Words(line).Select(t => Parse(StripBrackets(t))).OfType<Chord>();
        return InlineGroups(line).SelectMany(g => Words(g.Content).Select(Parse).OfType<Chord>());
    }

    private static int Length(string s) => new StringInfo(s).LengthInTextElements;

    /// <summary>Transponuje arkusz o podaną liczbę półtonów: linie akordowe oraz akordy w `[ ]` i `( )` w tekście.</summary>
    public static string Transpose(string sheet, int semitones)
    {
        var shift = ((semitones % 12) + 12) % 12;
        if (shift == 0) return sheet;
        var lines = sheet.Split('\n');
        var all = lines.SelectMany(ChordsIn).ToList();
        if (all.Count == 0) return sheet;

        var first = all[0];
        var target = (first.Root + shift) % 12;
        var useFlats = IsMinor(first) ? FlatMinor.Contains(target) : FlatMajor.Contains(target);
        var german = all.Any(c => c.German);
        var names = german ? (useFlats ? GermanFlat : GermanSharp) : useFlats ? Flat : Sharp;

        string Render(Chord chord)
        {
            var result = names[(chord.Root + shift) % 12];
            if (chord.IsLowercase) result = result.ToLowerInvariant();
            result += chord.Suffix;
            if (chord.Bass is int bass)
            {
                var name = names[(bass + shift) % 12];
                result += "/" + (chord.BassIsLowercase ? name.ToLowerInvariant() : name);
            }
            return result;
        }

        return string.Join("\n", lines.Select(line => IsChordLine(line) ? TransposeChordLine(line, Render) : TransposeInline(line, Render)));
    }

    /// <summary>Akordy na swoich kolumnach; gdy poprzedni się wydłużył, jedna spacja odstępu.</summary>
    private static string TransposeChordLine(string line, Func<Chord, string> render)
    {
        var result = new StringBuilder();
        var resultLength = 0;
        var column = 0;
        var i = 0;
        while (i < line.Length)
        {
            if (char.IsWhiteSpace(line[i])) { i++; column++; continue; }
            var end = i;
            while (end < line.Length && !char.IsWhiteSpace(line[end])) end++;
            var token = line[i..end];
            var core = StripBrackets(token);
            var replacement = token;
            var chord = Parse(core);
            if (chord is not null && core.Length > 0 && token.Contains(core))
            {
                var at = token.IndexOf(core, StringComparison.Ordinal);
                replacement = token[..at] + render(chord) + token[(at + core.Length)..];
            }
            var padding = resultLength == 0 ? column : Math.Max(column - resultLength, 1);
            result.Append(' ', padding).Append(replacement);
            resultLength += padding + Length(replacement);
            column += Length(token);
            i = end;
        }
        return result.ToString();
    }

    private static string TransposeInline(string line, Func<Chord, string> render)
    {
        var result = new StringBuilder();
        var cursor = 0;
        foreach (var g in InlineGroups(line))
        {
            var transposed = string.Join(" ", g.Content.Split(' ').Select(t => Parse(t) is Chord c ? render(c) : t));
            result.Append(line, cursor, g.Start - cursor).Append(g.Open).Append(transposed).Append(g.Close);
            cursor = g.End;
        }
        return result.Append(line, cursor, line.Length - cursor).ToString();
    }
}
