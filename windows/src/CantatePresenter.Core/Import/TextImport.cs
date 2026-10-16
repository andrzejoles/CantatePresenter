using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Import;

/// <summary>Import plików tekstowych: odpowiednik TextImporter z macOS (kodowanie, metadane w pierwszych liniach).</summary>
public static partial class TextImport
{
    private static readonly HashSet<char> PolishLetters = [.. "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"];
    private static readonly HashSet<char> Suspicious = [.. "±¶¼¦¬ˇ˘˝˙¤§¨®°µ·¸ŠšŤťŽľĽĹĺŕŔřŘůŮ∂∑∏√∞≈≠≤≥◊ﬁﬂ"];

    static TextImport() => Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

    /// <summary>Kodowania jednobajtowe próbowane, gdy plik nie jest poprawnym UTF-8; kolejność rozstrzyga remisy.</summary>
    private static readonly int[] SingleByte = [1250, 28592, 10000];

    private static int Score(string text)
    {
        var result = 0;
        foreach (var c in text)
        {
            if (PolishLetters.Contains(c)) result += 2;
            else if (Suspicious.Contains(c)) result -= 3;
            else if (char.IsControl(c) && c is not ('\n' or '\r' or '\t')) result -= 5;
        }
        return result;
    }

    /// <summary>UTF-8, a jeśli to niemożliwe, kodowanie jednobajtowe z najlepszym wynikiem (najwięcej polskich liter).</summary>
    public static string Decode(byte[] bytes)
    {
        try
        {
            var text = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(bytes);
            return text.StartsWith('﻿') ? text[1..] : text;
        }
        catch (DecoderFallbackException)
        {
            var best = "";
            var bestScore = int.MinValue;
            foreach (var codePage in SingleByte)
            {
                var text = Encoding.GetEncoding(codePage).GetString(bytes);
                var value = Score(text);
                if (value > bestScore) { best = text; bestScore = value; }
            }
            return best;
        }
    }

    [GeneratedRegex(@"^(tytuł|tytul|title):")] private static partial Regex TitleTag();
    [GeneratedRegex(@"^(autor|author):")] private static partial Regex AuthorTag();
    [GeneratedRegex(@"^(tonacja|klucz|key):")] private static partial Regex KeyTag();
    [GeneratedRegex(@"^(tagi|kategoria|tags):")] private static partial Regex TagsTag();

    /// <summary>Pieśń z tekstu: pierwsze linie mogą zawierać Tytuł:/Autor:/Tonacja:/Tagi:, pierwsza linia bez znacznika to tytuł.</summary>
    public static ImportedSong ParseTextSong(string rawContent, string fallbackTitle)
    {
        var lines = rawContent.Replace("\r\n", "\n").Replace("\r", "\n").Trim().Split('\n');
        string title = fallbackTitle, author = "", key = "";
        var tags = new List<string>();
        var start = 0;
        static string Value(string line) => line[(line.IndexOf(':') + 1)..].Trim();
        for (var i = 0; i < Math.Min(8, lines.Length); i++)
        {
            var line = lines[i].Trim();
            var lower = line.ToLower(CultureInfo.GetCultureInfo("pl-PL"));
            if (TitleTag().IsMatch(lower)) { title = Value(line); start = Math.Max(start, i + 1); }
            else if (AuthorTag().IsMatch(lower)) { author = Value(line); start = Math.Max(start, i + 1); }
            else if (KeyTag().IsMatch(lower)) { key = Value(line); start = Math.Max(start, i + 1); }
            else if (TagsTag().IsMatch(lower))
            {
                tags = Value(line).Split(',', ';').Select(t => t.Trim()).Where(t => t.Length > 0).ToList();
                start = Math.Max(start, i + 1);
            }
            else if (i == 0 && !line.StartsWith('[') && !lower.StartsWith("1.") && !lower.StartsWith("ref"))
            {
                title = line;
                start = 1;
            }
        }
        return new ImportedSong(title.Length > 0 ? title : fallbackTitle, author, key, tags, string.Join("\n", lines.Skip(start)).Trim());
    }
}
