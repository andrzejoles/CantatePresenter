using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public class PolishEncodingService
    {
        private static readonly HashSet<char> PolishDiacritics = new("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ");

        private static readonly (string Mojibake, string Correct)[] MojibakeReplacements = new[]
        {
            ("Ã³", "ó"), ("Ã“", "Ó"),
            ("Å‚", "ł"), ("Å\u0081", "Ł"), ("Å\u009A", "Ś"),
            ("Å›", "ś"), ("Åš", "Ś"),
            ("Å¼", "ż"), ("Å»", "Ż"),
            ("Åº", "ź"), ("Å¹", "Ź"),
            ("Ä™", "ę"), ("Ä\u0098", "Ę"), ("Ä˜", "Ę"),
            ("Ä…", "ą"), ("Ä„", "Ą"),
            ("Ä‡", "ć"), ("Ä†", "Ć"),
            ("Å„", "ń"), ("Åƒ", "Ń"),
            ("\u00B9", "ą"), ("\u00A5", "Ą"),
            ("\u00E6", "ć"), ("\u00C6", "Ć"),
            ("\u00EA", "ę"), ("\u00CA", "Ę"),
            ("\u00B3", "ł"), ("\u00A3", "Ł"),
            ("\u00F1", "ń"), ("\u00D1", "Ń"),
            ("\u00F3", "ó"), ("\u00D3", "Ó"),
            ("\u009C", "ś"), ("\u008C", "Ś"),
            ("\u009F", "ź"), ("\u008F", "Ź"),
            ("\u00BF", "ż"), ("\u00AF", "Ż"),
            ("\u0096", "–"), ("\u0097", "—"),
            ("\u0091", "‘"), ("\u0092", "’"),
            ("\u0093", "“"), ("\u0094", "”"),
            ("â€ž", "„"), ("â€\u009D", "”"), ("â€“", "–"), ("â€”", "—")
        };

        private static readonly Dictionary<string, string> KnownReligiousWords = new(StringComparer.OrdinalIgnoreCase)
        {
            { "badz", "Bądź" }, { "bog", "Bóg" }, { "boga", "Boga" }, { "bogu", "Bogu" },
            { "bogiem", "Bogiem" }, { "boze", "Boże" }, { "blogoslaw", "Błogosław" },
            { "blogoslawcie", "Błogosławcie" }, { "blogoslawiony", "Błogosławiony" },
            { "blogoslawieni", "Błogosławieni" }, { "milosierni", "miłosierni" },
            { "milosierdzia", "miłosierdzia" }, { "milosierdzie", "miłosierdzie" },
            { "milosc", "miłość" }, { "milosci", "miłości" }, { "krolowa", "Królowa" },
            { "krolowo", "Królowo" }, { "krol", "Król" }, { "krola", "Króla" },
            { "swiety", "Święty" }, { "swieta", "Święta" }, { "swiete", "Święte" },
            { "swieci", "Święci" }, { "spiewaj", "Śpiewaj" }, { "spiewajcie", "Śpiewajcie" },
            { "spiew", "Śpiew" }, { "piesn", "Pieśń" }, { "piesni", "Pieśni" },
            { "tys", "Tyś" }, { "jestes", "Jesteś" }, { "moj", "mój" },
            { "twoj", "Twój" }, { "twoja", "Twoja" }, { "twoje", "Twoje" },
            { "wsrod", "wśród" }, { "coz", "Cóż" }, { "zycie", "życie" },
            { "zyje", "żyje" }, { "zrodlo", "źródło" }, { "wez", "weź" },
            { "pojdz", "pójdź", }, { "przyjdz", "przyjdź" }, { "wstan", "wstań" },
            { "krzyz", "krzyż" }, { "pokoj", "pokój" }, { "zwyciezca", "zwycięzca" },
            { "smierc", "śmierć" }, { "zmiluj", "zmiłuj" }, { "ufnosc", "ufność" },
            { "otworz", "otwórz" }, { "slonce", "słońce" }, { "aniol", "Anioł" }
        };

        public static string RepairMojibake(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            var repaired = text;
            foreach (var (mojibake, correct) in MojibakeReplacements)
            {
                if (repaired.Contains(mojibake))
                    repaired = repaired.Replace(mojibake, correct);
            }
            return repaired;
        }

        public static bool HasPolishDiacritics(string text)
        {
            if (string.IsNullOrEmpty(text)) return false;
            return text.Any(c => PolishDiacritics.Contains(c));
        }

        public static (string Title, bool WasRestored) RestoreTitleDiacritics(string title, string lyrics)
        {
            var fixedTitle = RepairMojibake(title.Trim());
            if (HasPolishDiacritics(fixedTitle))
                return (fixedTitle, fixedTitle != title);

            var lyricsRepaired = RepairMojibake(lyrics);
            var lyricsWords = lyricsRepaired.Split(new[] { ' ', '\n', '\r', '\t', ',', '.', ';', '!', '?' }, StringSplitOptions.RemoveEmptyEntries);
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var lw in lyricsWords)
            {
                if (HasPolishDiacritics(lw) && lw.Length >= 2)
                {
                    var folded = Song.FoldString(lw);
                    if (!map.ContainsKey(folded))
                        map[folded] = lw;
                }
            }

            var words = fixedTitle.Split(' ');
            bool changed = false;

            for (int i = 0; i < words.Length; i++)
            {
                var w = words[i];
                var letters = new string(w.Where(char.IsLetter).ToArray());
                var punct = new string(w.Where(c => !char.IsLetter).ToArray());
                if (string.IsNullOrEmpty(letters)) continue;

                var folded = Song.FoldString(letters);
                string? repl = null;

                if (map.TryGetValue(folded, out var fromLyrics))
                    repl = fromLyrics;
                else if (KnownReligiousWords.TryGetValue(folded, out var fromDict))
                    repl = fromDict;

                if (repl != null)
                {
                    string styled;
                    if (letters == letters.ToUpper())
                        styled = repl.ToUpper();
                    else if (char.IsUpper(letters[0]))
                        styled = char.ToUpper(repl[0]) + (repl.Length > 1 ? repl[1..].ToLower() : "");
                    else
                        styled = repl.ToLower();

                    var finalWord = styled + punct;
                    if (finalWord != w)
                    {
                        words[i] = finalWord;
                        changed = true;
                    }
                }
            }

            var res = string.Join(" ", words);
            return (res, changed || res != title);
        }

        public static string CleanLyrics(string lyrics)
        {
            if (string.IsNullOrEmpty(lyrics)) return "";
            var cleaned = RepairMojibake(lyrics);
            return cleaned.Replace("\r\n", "\n").Replace("\r", "\n");
        }
    }
}
