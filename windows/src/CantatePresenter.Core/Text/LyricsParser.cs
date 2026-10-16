using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Text;

/// <summary>Kody typów slajdów zapisywane w JSON (jak SlideType w Swift).</summary>
public static class SlideTypes
{
    public const string Verse = "verse", Chorus = "chorus", Bridge = "bridge", PreChorus = "preChorus", Coda = "coda",
        Interlude = "interlude", Intro = "intro", Outro = "outro", Ending = "ending", Tag = "tag", Blank = "blank", Custom = "custom";

    public static readonly IReadOnlyList<string> All = [Verse, Chorus, Bridge, PreChorus, Coda, Interlude, Intro, Outro, Ending, Tag, Blank, Custom];

    /// <summary>Domyślne polskie nazwy typów (klucze tłumaczeń).</summary>
    public static readonly IReadOnlyDictionary<string, string> PolishName = new Dictionary<string, string>
    {
        [Verse] = "Zwrotka", [Chorus] = "Refren", [Bridge] = "Bridge", [PreChorus] = "Pre-Chorus", [Coda] = "Coda",
        [Interlude] = "Przejście", [Intro] = "Intro", [Outro] = "Outro", [Ending] = "Zakończenie", [Tag] = "Tag",
        [Blank] = "Pusty", [Custom] = "Własny",
    };

    public static readonly IReadOnlyDictionary<string, string> ShortBadge = new Dictionary<string, string>
    {
        [Verse] = "Z", [Chorus] = "R", [Bridge] = "B", [PreChorus] = "PC", [Coda] = "CODA", [Interlude] = "PRZ",
        [Intro] = "IN", [Outro] = "OUT", [Ending] = "ZAK", [Tag] = "TAG", [Blank] = "—", [Custom] = "•",
    };

    /// <summary>Kod z JSON: kod, stara polska nazwa albo „custom” dla nieznanych.</summary>
    public static string From(string? value)
    {
        var text = value ?? "";
        if (All.Contains(text)) return text;
        foreach (var (code, name) in PolishName) if (name == text) return code;
        return Custom;
    }
}

public sealed record ParsedSlide(string Type, string Label, string Text, int? Number);

/// <summary>
/// Podział tekstu na slajdy: odpowiednik Song.parseLyrics z wersji macOS (wzorzec).
/// Zgodność pilnują shared/fixtures/lyrics.json.
/// </summary>
public static partial class LyricsParser
{
    private static readonly string[] PreChorusWords = ["pre-chorus", "prechorus", "pre chorus", "przed-refren", "przedrefren", "przed refren"];
    private static readonly HashSet<string> Numbered = [SlideTypes.Verse, SlideTypes.Chorus, SlideTypes.Bridge, SlideTypes.Coda, SlideTypes.Interlude, SlideTypes.Ending];
    private static readonly string[] Prefixes = ["[", "ref:", "refren:", "chorus:", "coda:", "koda:", "przejście:", "przejscie:", "zakończenie:"];

    [GeneratedRegex(@"^\[([^\]]+)\]$|^([0-9]+)\.?$|^(pre[- ]?chorus|przed[- ]?refren|ref(ren)?|chorus|bridge|most(ek)?|coda|koda|interlude|przej[sś]cie|solo|intro|wst[eę]p|outro|zako[nń]czenie|ending|tag|zwrotka|z)(\s*[0-9]*)?:?$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Header();

    [GeneratedRegex(@"(\d+)$")]
    private static partial Regex TrailingDigits();

    [GeneratedRegex(@"^[\p{Zs}\t]+|[\p{Zs}\t]+$")]
    private static partial Regex EdgeSpaces();

    private static readonly char[] NewLines = ['\n', '\u000B', '\u000C', '\r', '\u0085', '\u2028', '\u2029'];

    /// <summary>Przycięcie jak <c>.whitespaces</c> w Swift (spacje i tabulatory, bez znaków nowej linii).</summary>
    public static string TrimSpaces(string s) => EdgeSpaces().Replace(s, "");

    /// <summary>Przycięcie jak <c>.whitespacesAndNewlines</c>.</summary>
    public static string TrimAll(string s) => s.Trim().Trim('\u0085');

    private static string TrimChars(string s, string chars)
    {
        int start = 0, end = s.Length;
        while (start < end && chars.Contains(s[start])) start++;
        while (end > start && chars.Contains(s[end - 1])) end--;
        return s[start..end];
    }

    private static string? TextAfterHeader(string rest)
    {
        var text = TrimSpaces(rest.TrimStart(':', ' ', '\t'));
        return text.Length > 0 ? text : null;
    }

    private static string AfterColon(string s) => TrimSpaces(s[(s.IndexOf(':') + 1)..]);

    /// <summary>Liczba na końcu etykiety („Zwrotka 2” → 2).</summary>
    public static int? TrailingNumber(string label)
    {
        var match = TrailingDigits().Match(label);
        return match.Success && int.TryParse(match.Groups[1].Value, out var number) ? number : null;
    }

    public static IReadOnlyList<ParsedSlide> Parse(string? raw)
    {
        raw ??= "";
        var normalized = raw.Replace("\r\n", "\n").Replace("\r", "\n");
        var blocks = normalized.Split("\n\n").Select(TrimAll).Where(b => b.Length > 0).ToList();
        if (blocks.Count == 0) return [new ParsedSlide(SlideTypes.Verse, "Zwrotka 1", TrimAll(raw), null)];

        var slides = new List<ParsedSlide>();
        int verse = 1, chorus = 1, bridge = 1, coda = 1, interlude = 1, ending = 1;
        foreach (var block in blocks)
        {
            var lines = block.Split(NewLines).Select(TrimSpaces).ToList();
            if (lines.Count == 0) continue;
            string type, label;
            var first = lines[0];
            var lower = first.ToLowerInvariant();
            var prefixed = Prefixes.Any(lower.StartsWith);
            var isHeader = Header().IsMatch(first);
            if (isHeader || prefixed)
            {
                // Tekst w tej samej linii co nagłówek („Ref: Chwała Panu”, „[Refren] Chwała”) zostaje w slajdzie.
                string header;
                string? inline = null;
                var close = first.IndexOf(']');
                if (lower.StartsWith('[') && close >= 0)
                {
                    header = TrimChars(first[1..close], "[]: \t");
                    inline = TextAfterHeader(first[(close + 1)..]);
                }
                else if (!isHeader && first.Contains(':'))
                {
                    var colon = first.IndexOf(':');
                    header = TrimChars(first[..colon], "[]: \t");
                    inline = TextAfterHeader(first[(colon + 1)..]);
                }
                else
                {
                    header = TrimChars(first, "[]: \t");
                }
                var h = header.ToLowerInvariant();
                if (PreChorusWords.Any(h.Contains)) { type = SlideTypes.PreChorus; label = "Pre-Chorus"; }
                else if (h.Contains("coda") || h.Contains("koda")) { type = SlideTypes.Coda; label = coda > 1 ? $"Coda {coda}" : "Coda"; coda++; }
                else if (h.Contains("interlude") || h.Contains("przejscie") || h.Contains("przejście") || h.Contains("solo")) { type = SlideTypes.Interlude; label = interlude > 1 ? $"Przejście {interlude}" : "Przejście"; interlude++; }
                else if (h.Contains("zakonczenie") || h.Contains("zakończenie") || h.Contains("ending")) { type = SlideTypes.Ending; label = ending > 1 ? $"Zakończenie {ending}" : "Zakończenie"; ending++; }
                else if (h.Contains("outro")) { type = SlideTypes.Outro; label = "Outro"; }
                else if (h.Contains("intro") || h.Contains("wstep") || h.Contains("wstęp")) { type = SlideTypes.Intro; label = "Intro"; }
                else if (h.Contains("ref") || h.Contains("chorus") || h == "r") { type = SlideTypes.Chorus; label = chorus > 1 ? $"Refren {chorus}" : "Refren"; chorus++; }
                else if (h.Contains("bridge") || h == "b" || h.Contains("most")) { type = SlideTypes.Bridge; label = bridge > 1 ? $"Bridge {bridge}" : "Bridge"; bridge++; }
                else if (h.Contains("pre")) { type = SlideTypes.PreChorus; label = "Pre-Chorus"; }
                else if (h.Contains("tag")) { type = SlideTypes.Tag; label = "Tag"; }
                else { type = SlideTypes.Verse; label = header; }
                if (inline is not null) lines[0] = inline; else lines.RemoveAt(0);
            }
            else if (lower.StartsWith("ref:") || lower.StartsWith("refren:"))
            {
                type = SlideTypes.Chorus; label = chorus > 1 ? $"Refren {chorus}" : "Refren"; chorus++;
                lines[0] = AfterColon(lines[0]);
            }
            else if (lower.StartsWith("r:"))
            {
                type = SlideTypes.Chorus; label = chorus > 1 ? $"Refren {chorus}" : "Refren"; chorus++;
                lines[0] = TrimSpaces(lines[0][2..]);
            }
            else if (lower.StartsWith("coda:") || lower.StartsWith("koda:"))
            {
                type = SlideTypes.Coda; label = coda > 1 ? $"Coda {coda}" : "Coda"; coda++;
                lines[0] = AfterColon(lines[0]);
            }
            else if (lower.StartsWith("przejście:") || lower.StartsWith("przejscie:") || lower.StartsWith("interlude:"))
            {
                type = SlideTypes.Interlude; label = interlude > 1 ? $"Przejście {interlude}" : "Przejście"; interlude++;
                lines[0] = AfterColon(lines[0]);
            }
            else if (lower.StartsWith("zakończenie:") || lower.StartsWith("zakonczenie:") || lower.StartsWith("ending:"))
            {
                type = SlideTypes.Ending; label = ending > 1 ? $"Zakończenie {ending}" : "Zakończenie"; ending++;
                lines[0] = AfterColon(lines[0]);
            }
            else
            {
                type = SlideTypes.Verse; label = $"Zwrotka {verse}"; verse++;
            }

            var text = TrimAll(string.Join("\n", lines));
            if (text.Length > 0)
            {
                var number = TrailingNumber(label) ?? (Numbered.Contains(type) ? 1 : null);
                slides.Add(new ParsedSlide(type, label, text, number));
            }
        }
        return slides.Count > 0 ? slides : [new ParsedSlide(SlideTypes.Verse, "Zwrotka 1", raw, null)];
    }
}
