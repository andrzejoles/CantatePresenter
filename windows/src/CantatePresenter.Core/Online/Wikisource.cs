using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Online;

public sealed record WikisourceResult(string Title, string Author, string Page, string Lyrics, string Url, string License);

/// <summary>
/// Wyszukiwanie pieśni w Wikiźródłach przez API MediaWiki: odpowiednik OnlineSearchService i WikisourceParser z macOS (S9).
/// Zgodność pilnują shared/fixtures/wikisource.json.
/// </summary>
public static partial class Wikisource
{
    private static readonly HashSet<string> Supported = ["pl", "en", "de", "es", "uk", "fr", "it", "la"];
    private const int MaxResults = 12;

    public static string Host(string language) => $"{(Supported.Contains(language) ? language : "pl")}.wikisource.org";

    /// <summary>Jak addingPercentEncoding(.urlPathAllowed) w macOS.</summary>
    public static string PageUrl(string title, string language)
    {
        const string allowed = "-._~!$&'()*+,;=:@/";
        var builder = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(title.Replace(' ', '_')))
        {
            var c = (char)b;
            if (b < 128 && (char.IsAsciiLetterOrDigit(c) || allowed.Contains(c))) builder.Append(c);
            else builder.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return $"https://{Host(language)}/wiki/{builder}";
    }

    private static IEnumerable<string> Matches(string pattern, string text) =>
        Regex.Matches(text, pattern, RegexOptions.Singleline).Select(m => m.Groups[1].Value);

    private static string Replacing(string pattern, string text, string replacement) =>
        Regex.Replace(text, pattern, replacement, RegexOptions.Singleline | RegexOptions.IgnoreCase);

    public static string DecodeEntities(string text)
    {
        if (!text.Contains('&')) return text;
        var result = text;
        foreach (var (entity, value) in new[] { ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">") })
            result = result.Replace(entity, value);
        result = Regex.Replace(result, "&#(x?)([0-9a-fA-F]+);", m =>
        {
            var hex = m.Groups[1].Value.Length > 0;
            if (!int.TryParse(m.Groups[2].Value, hex ? NumberStyles.HexNumber : NumberStyles.None, CultureInfo.InvariantCulture, out var code)) return m.Value;
            return code is >= 0 and <= 0x10FFFF and (< 0xD800 or > 0xDFFF) ? char.ConvertFromUtf32(code) : m.Value;
        });
        return result.Replace("&amp;", "&");
    }

    private static List<List<string>> MergeSplitStanzas(List<List<List<string>>> blocks)
    {
        var frequency = new Dictionary<int, int>();
        foreach (var stanza in blocks.SelectMany(b => b)) frequency[stanza.Count] = frequency.GetValueOrDefault(stanza.Count) + 1;
        var typical = frequency.OrderByDescending(p => p.Value).ThenByDescending(p => p.Key).Select(p => p.Key).FirstOrDefault();
        var result = new List<List<string>>();
        var carry = false;
        foreach (var block in blocks)
        {
            for (var index = 0; index < block.Count; index++)
            {
                var stanza = block[index];
                var last = result.Count > 0 ? result[^1] : null;
                if (index == 0 && carry && last is not null && last.Count < typical && stanza.Count < typical && last.Count + stanza.Count <= typical)
                    result[^1] = [.. last, .. stanza];
                else
                    result.Add(stanza);
            }
            carry = true;
        }
        return result;
    }

    /// <summary>Tekst pieśni z bloków &lt;div class="poem"&gt;, bez numerów stron i przypisów.</summary>
    public static string LyricsFromHtml(string html)
    {
        var blocks = new List<List<List<string>>>();
        foreach (var body in Matches("<div class=\"poem\"[^>]*>(.*?)</div>", html))
        {
            var text = Replacing("<span[^>]*ws-pagenum[^>]*>.*?</span>", body, "");
            text = Replacing("<sup[^>]*>.*?</sup>", text, "");
            text = text.Replace("\n", "");
            text = Replacing(@"<br\s*/?>", text, "\n");
            text = Replacing("</p>", text, "\n\n");
            text = DecodeEntities(Replacing("<[^>]+>", text, ""));
            var stanzas = new List<List<string>>();
            var current = new List<string>();
            foreach (var line in text.Split('\n').Select(Text.LyricsParser.TrimSpaces))
            {
                if (line.Length > 0) current.Add(line);
                else if (current.Count > 0) { stanzas.Add(current); current = []; }
            }
            if (current.Count > 0) stanzas.Add(current);
            if (stanzas.Count > 0) blocks.Add(stanzas);
        }
        return string.Join("\n\n", MergeSplitStanzas(blocks).Select(s => string.Join("\n", s)));
    }

    /// <summary>„publicDomain”, „ccBySA” albo „unknown”.</summary>
    public static string LicenseFromHtml(string html)
    {
        var lower = html.ToLowerInvariant();
        if (lower.Contains("public domain") || lower.Contains("własnością publiczną") || lower.Contains("gemeinfrei")) return "publicDomain";
        return lower.Contains("creative commons") ? "ccBySA" : "unknown";
    }

    public static string AuthorFromWikitext(string wikitext)
    {
        var raw = Matches(@"\|\s*(?:autor|author)\s*=((?:\[\[[^\]]*\]\]|[^\n|\[])*)", wikitext).FirstOrDefault();
        if (raw is null) return "";
        var value = Replacing(@"\[\[[^\]|]*\|([^\]]*)\]\]", raw, "$1");
        value = Replacing(@"\[\[(?:[^\]:]*:)?([^\]]*)\]\]", value, "$1");
        return Text.LyricsParser.TrimSpaces(value.Replace("''", ""));
    }

    /// <summary>„Śpiewnik kościelny/Boże z twoich rąk żyjemy” → „Boże z twoich rąk żyjemy”; nawias z wydaniem odcięty.</summary>
    public static string ShortTitle(string title) => Regex.Replace(title.Split('/')[^1], @"\s*\([^)]*\)$", "");

    /// <summary>Wyniki tylko ze stron z tekstem pieśni lub wiersza; Wikimedia wymaga przedstawienia się programu (User-Agent).</summary>
    public static async Task<List<WikisourceResult>> SearchAsync(HttpClient http, string query, string language, string appVersion, CancellationToken cancel = default)
    {
        var clean = query.Trim();
        if (clean.Length == 0) return [];
        async Task<JsonNode?> Api(Dictionary<string, string> parameters)
        {
            parameters["format"] = "json";
            parameters["formatversion"] = "2";
            var queryString = string.Join("&", parameters.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => $"{p.Key}={Uri.EscapeDataString(p.Value)}"));
            using var request = new HttpRequestMessage(HttpMethod.Get, $"https://{Host(language)}/w/api.php?{queryString}");
            request.Headers.UserAgent.Add(new ProductInfoHeaderValue("CantatePresenter", appVersion));
            request.Headers.UserAgent.Add(new ProductInfoHeaderValue("(https://github.com/andrzejoles/CantatePresenter)"));
            using var response = await http.SendAsync(request, cancel).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            return JsonNode.Parse(await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false));
        }
        var found = await Api(new() { ["action"] = "query", ["list"] = "search", ["srsearch"] = clean, ["srnamespace"] = "0", ["srlimit"] = MaxResults.ToString(CultureInfo.InvariantCulture) }).ConfigureAwait(false);
        var titles = (found?["query"]?["search"] as JsonArray ?? []).Select(hit => Json.OptStr(hit?["title"])).OfType<string>().ToList();
        var pages = await Task.WhenAll(titles.Select(async page =>
        {
            try
            {
                var parsed = (await Api(new() { ["action"] = "parse", ["page"] = page, ["prop"] = "text|wikitext", ["disablelimitreport"] = "1" }).ConfigureAwait(false))?["parse"];
                if (Json.OptStr(parsed?["text"]) is not string html) return null;
                var lyrics = LyricsFromHtml(html);
                if (lyrics.Length == 0) return null;
                return new WikisourceResult(ShortTitle(page), AuthorFromWikitext(Json.Str(parsed?["wikitext"])), page, lyrics, PageUrl(page, language), LicenseFromHtml(html));
            }
            catch (Exception error) when (error is HttpRequestException or System.Text.Json.JsonException or TaskCanceledException)
            {
                return null;
            }
        })).ConfigureAwait(false);
        return pages.OfType<WikisourceResult>().ToList();
    }
}
