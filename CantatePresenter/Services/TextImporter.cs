using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public static class TextImporter
    {
        public static string ReadTextWithBestEncoding(string filePath)
        {
            var bytes = File.ReadAllBytes(filePath);

            // 1. Try UTF-8
            try
            {
                var utf8NoBom = new UTF8Encoding(false, true);
                return utf8NoBom.GetString(bytes);
            }
            catch
            {
                // Fall through
            }

            // 2. Try Windows-1250 (Central European)
            try
            {
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                var cp1250 = Encoding.GetEncoding(1250);
                return cp1250.GetString(bytes);
            }
            catch
            {
                // Fall through
            }

            // 3. Fallback to ISO-8859-2
            try
            {
                var iso = Encoding.GetEncoding("iso-8859-2");
                return iso.GetString(bytes);
            }
            catch
            {
                return Encoding.Default.GetString(bytes);
            }
        }

        public static List<Song> ImportFromFile(string filePath)
        {
            var ext = Path.GetExtension(filePath).ToLowerInvariant();
            var fileName = Path.GetFileNameWithoutExtension(filePath);

            // 1. JSON
            if (ext == ".json")
            {
                try
                {
                    var json = ReadTextWithBestEncoding(filePath);
                    var list = JsonSerializer.Deserialize<List<Song>>(json);
                    if (list != null && list.Count > 0)
                        return list;

                    var single = JsonSerializer.Deserialize<Song>(json);
                    if (single != null)
                        return new List<Song> { single };
                }
                catch
                {
                    // Fall through to text parse
                }
            }

            // 2. Holyrics marker translation (.mufl, .muf, .hly, .txt)
            var content = ReadTextWithBestEncoding(filePath);
            content = PolishEncodingService.RepairMojibake(content);

            if (ext == ".mufl" || ext == ".muf" || content.Contains("##("))
            {
                content = TranslateHolyricsMarkers(content);
            }

            var song = ParseString(content, fileName);
            return new List<Song> { song };
        }

        public static string TranslateHolyricsMarkers(string text)
        {
            var result = text.Replace("\r\n", "\n").Replace("\r", "\n");
            result = Regex.Replace(result, @"##\(Verse\s*(\d+)\)", "[Zwrotka $1]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(Verse\)", "[Zwrotka]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(Chorus\s*(\d*)\)", "[Refren]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(Bridge\s*(\d*)\)", "[Bridge]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(Coda\s*(\d*)\)", "[Coda]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(Intro\s*(\d*)\)", "[Wstęp]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\((Outro|Ending)\s*(\d*)\)", "[Zakończenie]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\((Tag|Interlude)\s*(\d*)\)", "[Przejście]", RegexOptions.IgnoreCase);
            result = Regex.Replace(result, @"##\(([^)]+)\)", "[$1]", RegexOptions.IgnoreCase);
            return result;
        }

        public static Song ParseString(string rawContent, string fallbackTitle = "Nowa pieśń")
        {
            var normalized = rawContent.Replace("\r\n", "\n").Replace("\r", "\n").Trim();
            var lines = normalized.Split('\n').Select(l => l.Trim()).ToList();

            if (lines.Count == 0 || (lines.Count == 1 && string.IsNullOrEmpty(lines[0])))
                return new Song(fallbackTitle);

            string title = fallbackTitle;
            string author = "";
            string key = "";
            var tags = new List<string>();
            int lyricsStartIndex = 0;

            for (int i = 0; i < Math.Min(8, lines.Count); i++)
            {
                var line = lines[i];
                var low = line.ToLowerInvariant();

                if (low.StartsWith("tytuł:") || low.StartsWith("tytul:") || low.StartsWith("title:"))
                {
                    title = line.Substring(line.IndexOf(':') + 1).Trim();
                    lyricsStartIndex = Math.Max(lyricsStartIndex, i + 1);
                }
                else if (low.StartsWith("autor:") || low.StartsWith("author:"))
                {
                    author = line.Substring(line.IndexOf(':') + 1).Trim();
                    lyricsStartIndex = Math.Max(lyricsStartIndex, i + 1);
                }
                else if (low.StartsWith("tonacja:") || low.StartsWith("klucz:") || low.StartsWith("key:"))
                {
                    key = line.Substring(line.IndexOf(':') + 1).Trim();
                    lyricsStartIndex = Math.Max(lyricsStartIndex, i + 1);
                }
                else if (low.StartsWith("tagi:") || low.StartsWith("tags:") || low.StartsWith("kategoria:"))
                {
                    var tStr = line.Substring(line.IndexOf(':') + 1).Trim();
                    tags = tStr.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries).Select(s => s.Trim()).ToList();
                    lyricsStartIndex = Math.Max(lyricsStartIndex, i + 1);
                }
                else if (i == 0 && !line.StartsWith("[") && !low.StartsWith("1.") && !low.StartsWith("ref"))
                {
                    title = line;
                    lyricsStartIndex = 1;
                }
            }

            var lyricsLines = lines.Skip(lyricsStartIndex).ToList();
            var lyrics = string.Join("\n", lyricsLines).Trim();

            // Contextually restore Polish diacritics in title if missing
            var (restoredTitle, _) = PolishEncodingService.RestoreTitleDiacritics(title, lyrics);

            return new Song(restoredTitle, author, key, lyrics) { Tags = tags };
        }
    }
}
