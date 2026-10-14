using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CantatePresenter.Models
{
    public enum SlideType
    {
        Verse,
        Chorus,
        Bridge,
        PreChorus,
        Coda,
        Interlude,
        Ending,
        Intro,
        Outro,
        Tag,
        Custom
    }

    public enum SearchScope
    {
        All,
        TitleAndAuthor,
        TitleOnly,
        AuthorOnly
    }

    public class SongSlide
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("type")]
        public string TypeString { get; set; } = "Zwrotka";

        [JsonIgnore]
        public SlideType Type
        {
            get => ParseSlideType(TypeString);
            set => TypeString = SlideTypeToPolish(value);
        }

        [JsonPropertyName("label")]
        public string Label { get; set; } = "";

        [JsonPropertyName("text")]
        public string Text { get; set; } = "";

        public SongSlide() { }

        public SongSlide(SlideType type, string label, string text)
        {
            Id = Guid.NewGuid();
            Type = type;
            Label = label;
            Text = text;
        }

        public static SlideType ParseSlideType(string val)
        {
            if (string.IsNullOrWhiteSpace(val)) return SlideType.Verse;
            var low = val.Trim().ToLowerInvariant();
            if (low.Contains("refren") || low.Contains("chorus")) return SlideType.Chorus;
            if (low.Contains("bridge") || low.Contains("most")) return SlideType.Bridge;
            if (low.Contains("coda") || low.Contains("koda")) return SlideType.Coda;
            if (low.Contains("przej") || low.Contains("interlude")) return SlideType.Interlude;
            if (low.Contains("zako") || low.Contains("ending")) return SlideType.Ending;
            if (low.Contains("intro") || low.Contains("wst")) return SlideType.Intro;
            if (low.Contains("outro")) return SlideType.Outro;
            if (low.Contains("pre")) return SlideType.PreChorus;
            if (low.Contains("tag")) return SlideType.Tag;
            return SlideType.Verse;
        }

        public static string SlideTypeToPolish(SlideType t)
        {
            return t switch
            {
                SlideType.Verse => "Zwrotka",
                SlideType.Chorus => "Refren",
                SlideType.Bridge => "Bridge",
                SlideType.PreChorus => "Pre-Chorus",
                SlideType.Coda => "Coda",
                SlideType.Interlude => "Przejście",
                SlideType.Ending => "Zakończenie",
                SlideType.Intro => "Intro",
                SlideType.Outro => "Outro",
                SlideType.Tag => "Tag",
                _ => "Zwrotka"
            };
        }
    }

    public class Song
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("title")]
        public string Title { get; set; } = "";

        [JsonPropertyName("author")]
        public string Author { get; set; } = "";

        [JsonPropertyName("key")]
        public string Key { get; set; } = "";

        [JsonPropertyName("tags")]
        public List<string> Tags { get; set; } = new();

        [JsonPropertyName("rawLyrics")]
        public string RawLyrics { get; set; } = "";

        [JsonPropertyName("chords")]
        public string? Chords { get; set; }

        [JsonPropertyName("slides")]
        public List<SongSlide> Slides { get; set; } = new();

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("updatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        public Song() { }

        public Song(string title, string author = "", string key = "", string rawLyrics = "")
        {
            Id = Guid.NewGuid();
            Title = title;
            Author = author;
            Key = key;
            RawLyrics = rawLyrics;
            Slides = ParseLyrics(rawLyrics);
            CreatedAt = DateTime.UtcNow;
            UpdatedAt = DateTime.UtcNow;
        }

        public static string FoldString(string? text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            var sb = new StringBuilder(text.Length);
            foreach (char c in text.ToLowerInvariant())
            {
                switch (c)
                {
                    case 'ą': sb.Append('a'); break;
                    case 'ć': sb.Append('c'); break;
                    case 'ę': sb.Append('e'); break;
                    case 'ł': sb.Append('l'); break;
                    case 'ń': sb.Append('n'); break;
                    case 'ó': sb.Append('o'); break;
                    case 'ś': sb.Append('s'); break;
                    case 'ź': sb.Append('z'); break;
                    case 'ż': sb.Append('z'); break;
                    default:
                        if (char.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                            sb.Append(c);
                        break;
                }
            }
            return sb.ToString().Trim();
        }

        public bool Matches(string query, SearchScope scope = SearchScope.All)
        {
            var clean = FoldString(query);
            if (string.IsNullOrEmpty(clean)) return true;

            var fTitle = FoldString(Title);
            var fAuthor = FoldString(Author);

            return scope switch
            {
                SearchScope.All => fTitle.Contains(clean) ||
                                   fAuthor.Contains(clean) ||
                                   Tags.Any(t => FoldString(t).Contains(clean)) ||
                                   FoldString(RawLyrics).Contains(clean),
                SearchScope.TitleAndAuthor => fTitle.Contains(clean) || fAuthor.Contains(clean),
                SearchScope.TitleOnly => fTitle.Contains(clean),
                SearchScope.AuthorOnly => fAuthor.Contains(clean),
                _ => true
            };
        }

        public string? MatchingSnippet(string query)
        {
            var clean = FoldString(query);
            if (string.IsNullOrEmpty(clean)) return null;
            if (FoldString(Title).Contains(clean)) return null;

            var lines = (RawLyrics ?? "").Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            foreach (var line in lines)
            {
                if (FoldString(line).Contains(clean))
                {
                    var trimmed = line.Trim();
                    return trimmed.Length > 70 ? trimmed[..67] + "..." : trimmed;
                }
            }
            return null;
        }

        public static List<SongSlide> ParseLyrics(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw))
                return new List<SongSlide> { new(SlideType.Verse, "Zwrotka 1", "") };

            var normalized = raw.Replace("\r\n", "\n").Replace("\r", "\n");
            var blocks = normalized.Split(new[] { "\n\n" }, StringSplitOptions.RemoveEmptyEntries)
                                   .Select(b => b.Trim())
                                   .Where(b => !string.IsNullOrEmpty(b))
                                   .ToList();

            if (blocks.Count == 0)
                return new List<SongSlide> { new(SlideType.Verse, "Zwrotka 1", raw.Trim()) };

            var slides = new List<SongSlide>();
            int verseCounter = 1;
            int chorusCounter = 1;
            int bridgeCounter = 1;
            int codaCounter = 1;
            int interludeCounter = 1;
            int endingCounter = 1;

            var headerRegex = new Regex(@"^\[([^\]]+)\]$|^([0-9]+)\.?$|^(ref(ren)?|chorus|bridge|most(ek)?|coda|koda|interlude|przej[sś]cie|solo|intro|wst[eę]p|outro|zako[nń]czenie|ending|tag|zwrotka|z)(\s*[0-9]*)?:?$", RegexOptions.IgnoreCase);

            foreach (var block in blocks)
            {
                var lines = block.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
                if (lines.Count == 0) continue;

                var firstLine = lines[0];
                var lower = firstLine.ToLowerInvariant();
                SlideType type = SlideType.Verse;
                string label = "";

                if (headerRegex.IsMatch(firstLine) || lower.StartsWith("[") || lower.StartsWith("ref:") || lower.StartsWith("refren:") || lower.StartsWith("chorus:") || lower.StartsWith("coda:") || lower.StartsWith("koda:") || lower.StartsWith("przejście:") || lower.StartsWith("przejscie:") || lower.StartsWith("zakończenie:"))
                {
                    var headerContent = firstLine.Trim('[', ']', ':', ' ', '\t');
                    var hLower = headerContent.ToLowerInvariant();

                    if (hLower.Contains("coda") || hLower.Contains("koda"))
                    {
                        type = SlideType.Coda;
                        label = codaCounter > 1 ? $"Coda {codaCounter}" : "Coda";
                        codaCounter++;
                    }
                    else if (hLower.Contains("interlude") || hLower.Contains("przejscie") || hLower.Contains("przejście") || hLower.Contains("solo"))
                    {
                        type = SlideType.Interlude;
                        label = interludeCounter > 1 ? $"Przejście {interludeCounter}" : "Przejście";
                        interludeCounter++;
                    }
                    else if (hLower.Contains("zakonczenie") || hLower.Contains("zakończenie") || hLower.Contains("ending"))
                    {
                        type = SlideType.Ending;
                        label = endingCounter > 1 ? $"Zakończenie {endingCounter}" : "Zakończenie";
                        endingCounter++;
                    }
                    else if (hLower.Contains("outro"))
                    {
                        type = SlideType.Outro;
                        label = "Outro";
                    }
                    else if (hLower.Contains("intro") || hLower.Contains("wstep") || hLower.Contains("wstęp"))
                    {
                        type = SlideType.Intro;
                        label = "Intro";
                    }
                    else if (hLower.Contains("ref") || hLower.Contains("chorus") || hLower == "r")
                    {
                        type = SlideType.Chorus;
                        label = chorusCounter > 1 ? $"Refren {chorusCounter}" : "Refren";
                        chorusCounter++;
                    }
                    else if (hLower.Contains("bridge") || hLower == "b" || hLower.Contains("most"))
                    {
                        type = SlideType.Bridge;
                        label = bridgeCounter > 1 ? $"Bridge {bridgeCounter}" : "Bridge";
                        bridgeCounter++;
                    }
                    else if (hLower.Contains("pre"))
                    {
                        type = SlideType.PreChorus;
                        label = "Pre-Chorus";
                    }
                    else if (hLower.Contains("tag"))
                    {
                        type = SlideType.Tag;
                        label = "Tag";
                    }
                    else
                    {
                        type = SlideType.Verse;
                        label = headerContent;
                    }
                    lines.RemoveAt(0);
                }
                else
                {
                    if (lower.StartsWith("ref:") || lower.StartsWith("refren:"))
                    {
                        type = SlideType.Chorus;
                        label = chorusCounter > 1 ? $"Refren {chorusCounter}" : "Refren";
                        chorusCounter++;
                        lines[0] = lines[0].Substring(lines[0].IndexOf(':') + 1).Trim();
                    }
                    else
                    {
                        type = SlideType.Verse;
                        label = $"Zwrotka {verseCounter}";
                        verseCounter++;
                    }
                }

                var text = string.Join("\n", lines).Trim();
                if (!string.IsNullOrEmpty(text))
                {
                    slides.Add(new SongSlide(type, label, text));
                }
            }

            return slides.Count > 0 ? slides : new List<SongSlide> { new(SlideType.Verse, "Zwrotka 1", raw.Trim()) };
        }
    }
}
