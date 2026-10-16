// @ts-check
// Wyszukiwanie: odpowiednik Song.foldString / Song.searchFold / Song.matches z wersji macOS.
// Wzorcem jest Swift; zgodność pilnują shared/fixtures/search.json.

/** Pełne zwijanie wielkości liter jak w Foundation (ß → ss, ligatury), poza tym toLowerCase. */
const CASE_FOLD = { "ß": "ss", "ẞ": "ss", "ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl" };

/**
 * Tekst bez polskich znaków diakrytycznych i bez wielkich liter, przycięty.
 * @param {string} value
 */
export function foldString(value) {
  return String(value ?? "")
    .replace(/[łŁ]/g, "l")
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/[ßẞﬁﬂﬀﬃﬄ]/g, (c) => CASE_FOLD[/** @type {keyof typeof CASE_FOLD} */ (c)])
    .toLowerCase()
    .replace(/^\s+|\s+$/g, "");
}

/**
 * Jak foldString, a do tego interpunkcja zamieniona na spacje i spacje zwinięte.
 * @param {string} value
 */
export function searchFold(value) {
  return foldString(value)
    .replace(/[^\p{L}\p{M}\p{N}]+/gu, " ")
    .trim();
}

/** Zakresy wyszukiwania; wartości zgodne z kodami w wersji macOS. */
export const SearchScope = Object.freeze({
  all: "all",
  titleAndAuthor: "titleAndAuthor",
  titleOnly: "titleOnly",
  authorOnly: "authorOnly",
});

/**
 * @param {{title?: string, author?: string, tags?: string[], rawLyrics?: string}} song
 * @param {string} query
 * @param {string} [scope]
 */
export function songMatches(song, query, scope = SearchScope.all) {
  const q = searchFold(query);
  if (!q) return true;
  const title = searchFold(song.title ?? "");
  const author = searchFold(song.author ?? "");
  switch (scope) {
    case SearchScope.titleAndAuthor:
      return title.includes(q) || author.includes(q);
    case SearchScope.titleOnly:
      return title.includes(q);
    case SearchScope.authorOnly:
      return author.includes(q);
    default:
      return (
        title.includes(q) ||
        author.includes(q) ||
        (song.tags ?? []).some((tag) => searchFold(tag).includes(q)) ||
        searchFold(song.rawLyrics ?? "").includes(q)
      );
  }
}

/**
 * Wers z tekstu pasujący do zapytania (gdy nie pasuje tytuł), skrócony do 70 znaków.
 * @param {{title?: string, rawLyrics?: string}} song
 * @param {string} query
 * @returns {string | null}
 */
export function matchingSnippet(song, query) {
  const q = searchFold(query);
  if (!q || searchFold(song.title ?? "").includes(q)) return null;
  for (const line of String(song.rawLyrics ?? "").split(/[\n\r\u2028\u2029]/)) {
    if (searchFold(line).includes(q)) {
      const trimmed = line.trim();
      const chars = Array.from(trimmed);
      return chars.length > 70 ? chars.slice(0, 67).join("") + "..." : trimmed;
    }
  }
  return null;
}
