using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Text;

/// <summary>
/// Wyszukiwanie: odpowiednik Song.foldString / Song.searchFold / Song.matches z wersji macOS (wzorzec).
/// Zgodność pilnują shared/fixtures/search.json.
/// </summary>
public static partial class TextFold
{
    /// <summary>Tekst bez polskich znaków diakrytycznych i bez wielkich liter, przycięty.</summary>
    public static string Fold(string? value)
    {
        var text = (value ?? "").Replace('ł', 'l').Replace('Ł', 'l').Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(text.Length);
        foreach (var c in text)
        {
            var category = CharUnicodeInfo.GetUnicodeCategory(c);
            if (category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark) continue;
            switch (c)
            {
                case 'ß': case 'ẞ': builder.Append("ss"); break;
                case 'ﬁ': builder.Append("fi"); break;
                case 'ﬂ': builder.Append("fl"); break;
                case 'ﬀ': builder.Append("ff"); break;
                case 'ﬃ': builder.Append("ffi"); break;
                case 'ﬄ': builder.Append("ffl"); break;
                default: builder.Append(c); break;
            }
        }
        return builder.ToString().ToLowerInvariant().Trim();
    }

    [GeneratedRegex(@"[^\p{L}\p{M}\p{N}]+")]
    private static partial Regex NonWord();

    /// <summary>Jak <see cref="Fold"/>, a do tego interpunkcja zamieniona na spacje i spacje zwinięte.</summary>
    public static string SearchFold(string? value) => NonWord().Replace(Fold(value), " ").Trim();
}

/// <summary>Zakresy wyszukiwania; kody zgodne z wersją macOS i webową.</summary>
public enum SearchScope { All, TitleAndAuthor, TitleOnly, AuthorOnly }

public static class SongSearch
{
    public static bool Matches(string title, string author, IEnumerable<string> tags, string lyrics, string query, SearchScope scope = SearchScope.All)
    {
        var q = TextFold.SearchFold(query);
        if (q.Length == 0) return true;
        var t = TextFold.SearchFold(title);
        var a = TextFold.SearchFold(author);
        return scope switch
        {
            SearchScope.TitleAndAuthor => t.Contains(q) || a.Contains(q),
            SearchScope.TitleOnly => t.Contains(q),
            SearchScope.AuthorOnly => a.Contains(q),
            _ => t.Contains(q) || a.Contains(q) || tags.Any(tag => TextFold.SearchFold(tag).Contains(q)) || TextFold.SearchFold(lyrics).Contains(q),
        };
    }

    /// <summary>Wers z tekstu pasujący do zapytania (gdy nie pasuje tytuł), skrócony do 70 znaków.</summary>
    public static string? MatchingSnippet(string title, string lyrics, string query)
    {
        var q = TextFold.SearchFold(query);
        if (q.Length == 0 || TextFold.SearchFold(title).Contains(q)) return null;
        foreach (var line in lyrics.Split('\n', '\r', '\u2028', '\u2029'))
        {
            if (!TextFold.SearchFold(line).Contains(q)) continue;
            var trimmed = line.Trim();
            var count = new StringInfo(trimmed).LengthInTextElements;
            return count > 70 ? new StringInfo(trimmed).SubstringByTextElements(0, 67) + "..." : trimmed;
        }
        return null;
    }
}
