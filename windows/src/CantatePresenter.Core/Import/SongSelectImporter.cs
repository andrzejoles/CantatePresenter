using System.Text;
using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Import;

/// <summary>Pieśń z importu, zanim trafi do biblioteki (nowe id i daty nadaje biblioteka).</summary>
public sealed record ImportedSong(string Title, string Author, string Key, IReadOnlyList<string> Tags, string RawLyrics)
{
    public string? Chords { get; init; }
    public string? Copyright { get; init; }
    public string? CcliNumber { get; init; }
    public string? Source { get; init; }
}

/// <summary>Import plików z CCLI SongSelect (.txt, .usr, ChordPro): odpowiednik SongSelectImporter z macOS.</summary>
public static partial class SongSelectImporter
{
    public static readonly IReadOnlySet<string> ChordProExtensions = new HashSet<string> { "pro", "cho", "chopro", "chordpro", "crd" };

    public static string SongUrl(string number) => $"https://songselect.ccli.com/songs/{number}";
    public static string SearchUrl(string query) => $"https://songselect.ccli.com/search/results?search={Uri.EscapeDataString(query)}";

    [GeneratedRegex(@"^(verse|chorus|refrain|pre-chorus|pre chorus|prechorus|bridge|tag|ending|outro|intro|interlude|instrumental|vamp|misc|strophe|coro|verso|puente)(\s+\d+)?:?$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Section();

    [GeneratedRegex(@"^\s*CCLI Song (#|No\.?)\s*\d+", RegexOptions.Multiline)]
    private static partial Regex Footer();

    [GeneratedRegex(@"^\s*CCLI Song (#|No\.?)")]
    private static partial Regex FooterLine();

    [GeneratedRegex(@"^CCLI Licen[cs]e")]
    private static partial Regex LicenseLine();

    [GeneratedRegex(@"\d+")]
    private static partial Regex Digits();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex MultiSpace();

    /// <summary>„Verse 2” → „[Zwrotka 2]”, „Chorus” → „[Refren]”; null, gdy to nie nagłówek.</summary>
    public static string? SectionMarker(string line)
    {
        var m = Section().Match(line.Trim());
        if (!m.Success) return null;
        var number = m.Groups[2].Success ? " " + m.Groups[2].Value.Trim() : "";
        return m.Groups[1].Value.ToLowerInvariant() switch
        {
            "verse" or "strophe" or "verso" => $"[Zwrotka{number}]",
            "chorus" or "refrain" or "coro" => "[Refren]",
            "pre-chorus" or "pre chorus" or "prechorus" => "[Pre-Chorus]",
            "bridge" or "puente" => "[Bridge]",
            "tag" => "[Tag]",
            "ending" => "[Zakończenie]",
            "outro" => "[Outro]",
            "intro" => "[Intro]",
            "interlude" or "instrumental" => "[Przejście]",
            _ => $"[{m.Groups[1].Value}{number}]",
        };
    }

    private static string[] Lines(string text) => text.Replace("\r\n", "\n").Replace("\r", "\n").Replace("﻿", "").Split('\n');
    private static string DigitsIn(string text) => Digits().Match(text) is { Success: true } m ? m.Value : "";
    private static string Authors(string line) => string.Join(", ", line.Split('|').Select(a => a.Trim()).Where(a => a.Length > 0));

    private static string Collapse(IEnumerable<string> input)
    {
        var output = new List<string>();
        foreach (var line in input)
        {
            if (line.Length == 0 && (output.Count == 0 || output[^1].Length == 0)) continue;
            output.Add(line);
        }
        return string.Join("\n", output).Trim();
    }

    private static ImportedSong Make(string title, string author, string key, string rawLyrics, string? copyright, string ccliNumber, string? chords = null) =>
        new(title, author, key, ["SongSelect"], rawLyrics)
        {
            Copyright = string.IsNullOrEmpty(copyright) ? null : copyright,
            Chords = string.IsNullOrEmpty(chords) ? null : chords,
            CcliNumber = ccliNumber.Length > 0 ? ccliNumber : null,
            Source = ccliNumber.Length > 0 ? SongUrl(ccliNumber) : null,
        };

    public static bool IsSongSelectText(string text) => Footer().IsMatch(text);

    public static ImportedSong? ParseText(string text)
    {
        var all = Lines(text);
        var titleIndex = Array.FindIndex(all, l => l.Trim().Length > 0);
        var footerIndex = Array.FindIndex(all, l => FooterLine().IsMatch(l));
        if (titleIndex < 0 || footerIndex <= titleIndex) return null;
        var author = "";
        string? copyright = null;
        foreach (var line in all.Skip(footerIndex + 1))
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith("For use solely") || trimmed.StartsWith("Note:") || LicenseLine().IsMatch(trimmed)) continue;
            if (trimmed.StartsWith('©') || trimmed.ToLowerInvariant().StartsWith("copyright")) copyright = trimmed;
            else if (author.Length == 0) author = Authors(trimmed);
        }
        var body = new List<string>();
        foreach (var line in all[(titleIndex + 1)..footerIndex])
        {
            var trimmed = line.Trim();
            var marker = SectionMarker(trimmed);
            if (marker is not null)
            {
                if (body.Count > 0 && body[^1].Length > 0) body.Add("");
                body.Add(marker);
            }
            else
            {
                body.Add(trimmed);
            }
        }
        return Make(all[titleIndex].Trim(), author, "", Collapse(body), copyright, DigitsIn(all[footerIndex]));
    }

    public static ImportedSong? ParseUsr(string text)
    {
        var values = new Dictionary<string, string>();
        var ccliNumber = "";
        foreach (var line in Lines(text))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("[S ")) ccliNumber = DigitsIn(trimmed);
            else if (trimmed.Contains('='))
            {
                var index = trimmed.IndexOf('=');
                values[trimmed[..index].ToLowerInvariant()] = trimmed[(index + 1)..];
            }
        }
        if (!values.TryGetValue("title", out var title) || title.Length == 0) return null;
        var fields = values.GetValueOrDefault("fields", "").Split("/t");
        var blocks = values.GetValueOrDefault("words", "").Split("/t").Select((section, index) =>
        {
            var body = section.Replace("/n", "\n").Trim();
            if (body.Length == 0) return null;
            var marker = index < fields.Length ? SectionMarker(fields[index]) : null;
            return marker is null ? body : marker + "\n" + body;
        }).OfType<string>();
        var copyrightValue = values.GetValueOrDefault("copyright", "");
        string? copyright = copyrightValue.Length == 0 ? null : copyrightValue.StartsWith('©') ? copyrightValue : $"© {copyrightValue}";
        if (values.TryGetValue("admin", out var admin) && admin.Length > 0 && copyright is not null) copyright = $"{copyright} (Admin. by {admin})";
        return Make(title, Authors(values.GetValueOrDefault("author", "")), values.GetValueOrDefault("keys", "").Split("/t")[0],
            string.Join("\n\n", blocks), copyright, ccliNumber);
    }

    /// <summary>„A[G]mazing [C]grace” → akordy nad tekstem.</summary>
    public static (string? Chords, string Lyrics) SplitChords(string line)
    {
        if (!line.Contains('[')) return (null, line);
        var lyrics = new StringBuilder();
        var chords = new StringBuilder();
        var lyricCount = 0;
        var found = false;
        var i = 0;
        while (i < line.Length)
        {
            var close = line[i] == '[' ? line.IndexOf(']', i) : -1;
            if (close > i)
            {
                var chord = line[(i + 1)..close];
                var chordCount = chords.Length;
                if (chordCount > lyricCount) { chords.Append(' '); chordCount++; }
                chords.Append(' ', Math.Max(0, lyricCount - chordCount)).Append(chord);
                found = true;
                i = close + 1;
            }
            else
            {
                lyrics.Append(line[i]);
                lyricCount++;
                i++;
            }
        }
        return found ? (chords.ToString(), MultiSpace().Replace(lyrics.ToString(), " ").Trim()) : (null, line);
    }

    public static ImportedSong ParseChordPro(string text, string fallbackTitle)
    {
        string title = "", key = "", ccliNumber = "";
        string? copyright = null;
        var hasChords = false;
        var authors = new List<string>();
        var lyricLines = new List<string>();
        var sheetLines = new List<string>();
        void AddSection(string marker, string label)
        {
            if (lyricLines.Count > 0 && lyricLines[^1].Length > 0) lyricLines.Add("");
            if (sheetLines.Count > 0 && sheetLines[^1].Length > 0) sheetLines.Add("");
            lyricLines.Add(marker);
            sheetLines.Add($"{label}:");
        }
        foreach (var line in Lines(text))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith('#')) continue;
            if (trimmed.StartsWith('{') && trimmed.EndsWith('}'))
            {
                var inner = trimmed[1..^1];
                var colon = inner.IndexOf(':');
                var name = (colon < 0 ? inner : inner[..colon]).Trim().ToLowerInvariant();
                var value = colon < 0 ? "" : inner[(colon + 1)..].Trim();
                switch (name)
                {
                    case "title" or "t": title = value; break;
                    case "artist" or "author" or "composer" or "lyricist" or "subtitle" or "st":
                        if (value.Length > 0) authors.AddRange(value.Split('|').Select(a => a.Trim())); break;
                    case "key": key = value; break;
                    case "copyright": copyright = value.StartsWith('©') ? value : $"© {value}"; break;
                    case "ccli": ccliNumber = DigitsIn(value); break;
                    case "comment" or "c" or "comment_italic" or "ci" or "comment_box" or "cb":
                        if (SectionMarker(value) is string marker) AddSection(marker, value);
                        break;
                    case "start_of_chorus" or "soc": AddSection("[Refren]", value.Length > 0 ? value : "Chorus"); break;
                    case "start_of_bridge" or "sob": AddSection("[Bridge]", value.Length > 0 ? value : "Bridge"); break;
                    case "start_of_verse" or "sov":
                        AddSection(value.Length > 0 ? SectionMarker(value) ?? $"[{value}]" : "[Zwrotka]", value.Length > 0 ? value : "Verse"); break;
                }
                continue;
            }
            if (SectionMarker(trimmed) is string section) { AddSection(section, trimmed.Trim(':')); continue; }
            var (chords, lyricsLine) = SplitChords(trimmed);
            if (chords is not null) { hasChords = true; sheetLines.Add(chords); }
            lyricLines.Add(lyricsLine);
            sheetLines.Add(lyricsLine);
        }
        return Make(title.Length > 0 ? title : fallbackTitle, string.Join(", ", authors), key, Collapse(lyricLines), copyright, ccliNumber,
            hasChords ? Collapse(sheetLines) : null);
    }
}
