using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public class GuitarChordResult
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Title { get; set; } = "";
        public string Artist { get; set; } = "Tradycyjna / Religijna";
        public string Key { get; set; } = "";
        public string ChordsSheet { get; set; } = "";
        public string Source { get; set; } = "Baza Chwytów Gitarowych";
        public string? Url { get; set; }

        public GuitarChordResult() { }

        public GuitarChordResult(string title, string artist, string key, string chordsSheet, string source = "Baza Chwytów", string? url = null)
        {
            Id = Guid.NewGuid();
            Title = title;
            Artist = artist;
            Key = key;
            ChordsSheet = chordsSheet;
            Source = source;
            Url = url;
        }
    }

    public class GuitarChordsService
    {
        private static readonly string[] ChromaticScaleSharps = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H" };
        private static readonly HttpClient HttpClient = new();
        private readonly Dictionary<string, GuitarChordResult> _curatedChords = new(StringComparer.OrdinalIgnoreCase);

        public GuitarChordsService()
        {
            PopulateCuratedChords();
        }

        private void PopulateCuratedChords()
        {
            AddCurated(new GuitarChordResult(
                "Barka",
                "Ks. Stanisław Szmidt",
                "D",
                "[Zwrotka 1]\n D          A         h\nPan kiedyś stanął nad brzegiem,\n    G              e        A\nSzukał ludzi gotowych pójść za Nim,\n D          A        h\nBy łowić serca słów Bożych prawdą.\n\n[Refren]\n   G              D\nO Panie, to Ty na mnie spojrzałeś,\n  A                  D       D7\nTwoje usta dziś wyrzekły me imię.\n   G              D\nSwoją barkę pozostawiam na brzegu,\n   A                  D\nRazem z Tobą nowy zacznę dziś łów.",
                "Oficjalny śpiewnik oazowy"
            ));

            AddCurated(new GuitarChordResult(
                "Abba Ojcze",
                "O. Jan Góra OP",
                "D",
                "[Zwrotka 1]\n D        A        h\nTy wyzwoliłeś nas Panie\n G         e        A\nZ kajdanów i z niemocy,\n D         A        h\nŚwiatło Twe rozproszyło\n G      A     D\nMroki naszej nocy.\n\n[Refren]\n D     A     h     G\nAbba, Ojcze! Abba, Ojcze!\n D     A     D\nAbba, Ojcze!",
                "Hymn ŚDM Częstochowa 1991"
            ));

            AddCurated(new GuitarChordResult(
                "Jezus Siłą Mą",
                "Piosenka Wspólnotowa",
                "C",
                "[Zwrotka 1]\n C           G\nJezus siłą mą, Jezus pieśnią mą,\n a              F       G\nOn moim Panem i Zbawcą moim jest!\n\n[Refren]\n C           G\nOn moim Panem jest,\n a           F    G\nI moim Królem jest!\n C           G             a   F G C\nNie zlęknę się, bo ze mną Pan!",
                "Baza Piosenek Uwielbieniowych"
            ));
        }

        private void AddCurated(GuitarChordResult chord)
        {
            _curatedChords[Song.FoldString(chord.Title)] = chord;
        }

        public GuitarChordResult? GetCuratedChords(string title)
        {
            var folded = Song.FoldString(title);
            if (_curatedChords.TryGetValue(folded, out var c))
                return c;

            foreach (var kvp in _curatedChords)
            {
                if (kvp.Key.Contains(folded) || folded.Contains(kvp.Key))
                    return kvp.Value;
            }
            return null;
        }

        public async Task<List<GuitarChordResult>> SearchChordsAsync(string songTitle, string? artist = null)
        {
            var list = new List<GuitarChordResult>();
            var cleanTitle = (songTitle ?? "").Trim();
            var folded = Song.FoldString(cleanTitle);

            if (_curatedChords.TryGetValue(folded, out var direct))
                list.Add(direct);

            foreach (var kvp in _curatedChords)
            {
                if (kvp.Key != folded && (kvp.Key.Contains(folded) || folded.Contains(kvp.Key)))
                {
                    if (!list.Any(x => x.Title.Equals(kvp.Value.Title, StringComparison.OrdinalIgnoreCase)))
                        list.Add(kvp.Value);
                }
            }

            try
            {
                var query = Uri.EscapeDataString(cleanTitle + " chwyty gitarowe");
                var url = $"https://duckduckgo.com/html/?q={query}";
                using var req = new HttpRequestMessage(HttpMethod.Get, url);
                req.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                var res = await HttpClient.SendAsync(req);
                if (res.IsSuccessStatusCode)
                {
                    var html = await res.Content.ReadAsStringAsync();
                    var match = Regex.Match(html, @"<a class=""result__snippet[^""]*""[^>]*>(.*?)</a>", RegexOptions.Singleline);
                    if (match.Success)
                    {
                        var snippet = Regex.Replace(match.Groups[1].Value, "<.*?>", "").Trim();
                        if (snippet.Length > 20 && !list.Any(x => x.Source.Contains("DuckDuckGo")))
                        {
                            list.Add(new GuitarChordResult(
                                cleanTitle,
                                artist ?? "Odnalezione w sieci",
                                "",
                                snippet,
                                "Internet (Wyszukiwarka Akordów)"
                            ));
                        }
                    }
                }
            }
            catch
            {
                // Fallback gracefully on network failure
            }

            return list;
        }

        public (string CleanLyrics, string? ExtractedChords) ExtractChordsAndCleanLyrics(string raw)
        {
            var lines = (raw ?? "").Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            var cleanLines = new List<string>();
            var chordSheetLines = new List<string>();
            bool foundAnyChords = false;

            var chordLineRegex = new Regex(@"^\s*([A-Ha-h][#b]?(?:m|maj|min|dim|sus|add)?[0-9]?(?:/[A-Ha-h][#b]?)?(\s+|$))+$");
            var inlineParensRegex = new Regex(@"\(([A-Ha-h0-9#b\s/]{1,8})\)");
            var inlineBracketsRegex = new Regex(@"\[([A-Ha-h0-9#b/]{1,6})\]");

            foreach (var line in lines)
            {
                if (chordLineRegex.IsMatch(line) && !line.Trim().StartsWith("[Zwrotka") && !line.Trim().StartsWith("[Refren"))
                {
                    chordSheetLines.Add(line);
                    foundAnyChords = true;
                    continue;
                }

                var clean = line;
                var inlineMatches = inlineBracketsRegex.Matches(clean);
                if (inlineMatches.Count > 0 && !clean.Trim().StartsWith("[Zwrotka") && !clean.Trim().StartsWith("[Refren") && !clean.Trim().StartsWith("[Coda") && !clean.Trim().StartsWith("[Bridge"))
                {
                    foundAnyChords = true;
                    chordSheetLines.Add(clean);
                    clean = inlineBracketsRegex.Replace(clean, "");
                }
                else
                {
                    chordSheetLines.Add(line);
                }

                cleanLines.Add(clean.TrimEnd());
            }

            var cleanResult = string.Join("\n", cleanLines).Trim();
            var chordsResult = foundAnyChords ? string.Join("\n", chordSheetLines).Trim() : null;
            return (cleanResult, chordsResult);
        }

        public string Transpose(string chordsSheet, int semitones)
        {
            if (semitones == 0 || string.IsNullOrWhiteSpace(chordsSheet)) return chordsSheet;

            int shift = (semitones % 12 + 12) % 12;
            var chordRegex = new Regex(@"\b([A-H][#b]?)(m|maj|min|dim|sus|add)?([0-9]?)(?:/([A-H][#b]?))?\b");

            string TransposeRoot(string root)
            {
                bool isLower = root == root.ToLower();
                string upper = root.ToUpper();
                int idx = Array.IndexOf(ChromaticScaleSharps, upper);
                if (idx < 0) return root;
                int newIdx = (idx + shift) % 12;
                var tr = ChromaticScaleSharps[newIdx];
                return isLower ? tr.ToLower() : tr;
            }

            var lines = chordsSheet.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            var transposedLines = new List<string>();

            foreach (var line in lines)
            {
                var trans = chordRegex.Replace(line, m =>
                {
                    var root = m.Groups[1].Value;
                    var mod = m.Groups[2].Value;
                    var num = m.Groups[3].Value;
                    var bass = m.Groups[4].Success ? m.Groups[4].Value : "";

                    var newRoot = TransposeRoot(root);
                    var res = newRoot + mod + num;
                    if (!string.IsNullOrEmpty(bass))
                        res += "/" + TransposeRoot(bass);
                    return res;
                });
                transposedLines.Add(trans);
            }

            return string.Join("\n", transposedLines);
        }
    }
}
