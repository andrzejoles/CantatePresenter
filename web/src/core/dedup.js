// @ts-check
// Wykrywanie duplikatów przy imporcie: odpowiednik SongDeduplicationService z wersji macOS (bez wzbogacania
// metadanych z wbudowanego katalogu). Wzorcem jest Swift; zgodność pilnuje shared/fixtures/dedup.json.
import { foldString } from "./text.js";

/** @typedef {import("./models.js").Song} Song */
/**
 * @typedef {object} DuplicateRecord
 * @property {string} id
 * @property {Song} primarySong
 * @property {Song} duplicateSong
 * @property {string} reason
 * @property {number} similarityScore 0–100
 * @property {boolean} shouldSkipDuplicate
 */
/**
 * @typedef {object} ImportReport
 * @property {number} totalScanned
 * @property {Song[]} uniqueSongs
 * @property {DuplicateRecord[]} duplicateRecords duplikaty wewnątrz importu
 * @property {DuplicateRecord[]} existingCollisions pieśni o tym samym tytule już w bibliotece
 */

/** Autor pusty albo zastępczy („nieznany”, „brak”, „NN”…). @param {string} author */
export function isUnknownAuthor(author) {
  const clean = foldString(author);
  return ["", "autor nieznany", "nieznany", "brak", "tradycyjna", "nn", "various", "-"].includes(clean);
}

/** Słowa tekstu (co najmniej 3 znaki) jako zbiór. @param {string} foldedLyrics */
export function lyricsTokens(foldedLyrics) {
  return new Set(foldedLyrics.split(/[^\p{L}\p{M}\p{N}]+/u).filter((word) => [...word].length >= 3));
}

/** Podobieństwo zbiorów słów (Jaccard) w procentach, zaokrąglone w dół. @param {Set<string>} a @param {Set<string>} b */
export function tokenSimilarity(a, b) {
  if (a.size === 0 && b.size === 0) return 100;
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const word of a) if (b.has(word)) intersection++;
  const union = a.size + b.size - intersection;
  return union > 0 ? Math.floor((intersection / union) * 100) : 0;
}

/** Pierwsze 6 słów tekstu (po zwinięciu), klucz szybkiego porównania początku. @param {string} foldedLyrics */
function prefixKey(foldedLyrics) {
  return foldedLyrics.split(/\s+/).filter(Boolean).slice(0, 6).join(" ");
}

let nextRecordId = 0;

/**
 * Dzieli import na pieśni unikalne, duplikaty wewnątrz importu i kolizje z biblioteką (jak macOS).
 * @param {Song[]} incoming @param {Song[]} existingLibrary
 * @param {(key: string, ...args: any[]) => string} t tłumaczenie powodów
 * @returns {ImportReport}
 */
export function processAndDeduplicate(incoming, existingLibrary, t) {
  /** @type {Song[]} */ const unique = [];
  /** @type {Set<string>[]} */ const uniqueTokens = [];
  /** @type {DuplicateRecord[]} */ const duplicates = [];
  /** @type {Map<string, number[]>} */ const byTitle = new Map();
  /** @type {Map<string, number[]>} */ const byPrefix = new Map();
  /** @type {Map<string, number[]>} */ const byLyrics = new Map();
  /** @param {Map<string, number[]>} index @param {string} key @param {number} position */
  const addIndex = (index, key, position) => {
    if (!key) return;
    const list = index.get(key) ?? [];
    if (!list.includes(position)) list.push(position);
    index.set(key, list);
  };
  /** @returns {DuplicateRecord} */
  const record = (/** @type {Song} */ primarySong, /** @type {Song} */ duplicateSong, /** @type {string} */ reason, /** @type {number} */ similarityScore, shouldSkipDuplicate = true) =>
    ({ id: `dup-${++nextRecordId}`, primarySong, duplicateSong, reason, similarityScore, shouldSkipDuplicate });

  for (const candidate of incoming) {
    const title = foldString(candidate.title);
    const lyrics = foldString(candidate.rawLyrics);
    const tokens = lyricsTokens(lyrics);
    const prefix = prefixKey(lyrics);
    /** @type {number | null} */ let match = null;
    let score = 0;
    let reason = "";

    // 1. Identyczny tekst.
    const sameLyrics = lyrics ? byLyrics.get(lyrics) : undefined;
    if (sameLyrics?.length) {
      match = sameLyrics[0];
      score = 100;
      reason = t("Identyczny tekst utworu (100% zgodności)");
    } else {
      // 2. Ten sam tytuł i wystarczająco podobny tekst.
      for (const position of byTitle.get(title) ?? []) {
        const similarity = tokenSimilarity(tokens, uniqueTokens[position]);
        if (similarity >= 35 || tokens.size === 0) {
          match = position;
          score = Math.max(score, similarity);
          reason = t("Ten sam tytuł i zgodność tekstu ({0}%)", similarity);
          break;
        }
      }
    }
    // 3. Ten sam początek (6 słów) i bardzo podobny tekst.
    if (match === null && prefix) {
      for (const position of byPrefix.get(prefix) ?? []) {
        const similarity = tokenSimilarity(tokens, uniqueTokens[position]);
        if (similarity >= 70) {
          match = position;
          score = similarity;
          reason = t("Identyczny początek i bardzo wysokie podobieństwo tekstu ({0}%)", similarity);
          break;
        }
      }
    }

    if (match !== null) {
      const primary = unique[match];
      if (!isUnknownAuthor(candidate.author) && isUnknownAuthor(primary.author)) {
        // Nowa pieśń ma autora, a dotychczasowa główna nie: zamiana; nowa główna trafia do indeksów (N8).
        unique[match] = candidate;
        uniqueTokens[match] = tokens;
        addIndex(byTitle, title, match);
        addIndex(byPrefix, prefix, match);
        addIndex(byLyrics, lyrics, match);
        duplicates.push(record(candidate, primary, reason, score));
      } else {
        duplicates.push(record(primary, candidate, reason, score));
      }
    } else {
      const position = unique.length;
      unique.push(candidate);
      uniqueTokens.push(tokens);
      addIndex(byTitle, title, position);
      addIndex(byPrefix, prefix, position);
      addIndex(byLyrics, lyrics, position);
    }
  }

  // Kolizje z biblioteką: wszystkie pieśni o danym tytule, wygrywa najbardziej podobna.
  /** @type {DuplicateRecord[]} */ const collisions = [];
  if (existingLibrary.length) {
    /** @type {Map<string, Song[]>} */ const libraryByTitle = new Map();
    for (const song of existingLibrary) {
      const key = foldString(song.title);
      libraryByTitle.set(key, [...(libraryByTitle.get(key) ?? []), song]);
    }
    unique.forEach((song, index) => {
      let best = null;
      let bestScore = -1;
      for (const librarySong of libraryByTitle.get(foldString(song.title)) ?? []) {
        const similarity = tokenSimilarity(uniqueTokens[index], lyricsTokens(foldString(librarySong.rawLyrics)));
        if (similarity > bestScore) { best = librarySong; bestScore = similarity; }
      }
      if (best) {
        // Prawie identyczne pieśni (np. ponowny import własnego eksportu) domyślnie pomijane.
        collisions.push(record(best, song, t("Utwór o tym tytule istnieje już w bibliotece ({0}% zgodności)", bestScore), bestScore, bestScore >= 90));
      }
    });
  }

  return { totalScanned: incoming.length, uniqueSongs: unique, duplicateRecords: duplicates, existingCollisions: collisions };
}

/**
 * Pieśni do dodania po przeglądzie: unikalne bez pominiętych kolizji oraz duplikaty, których nie pominięto
 * (jako „(wersja alternatywna)”). Brak decyzji w mapie = wartość domyślna rekordu.
 * @param {ImportReport} report @param {Map<string, boolean>} duplicateSkips @param {Map<string, boolean>} collisionSkips
 * @returns {Song[]}
 */
export function songsToCommit(report, duplicateSkips = new Map(), collisionSkips = new Map()) {
  const skipped = new Set(report.existingCollisions
    .filter((r) => collisionSkips.get(r.id) ?? r.shouldSkipDuplicate)
    .map((r) => r.duplicateSong));
  const result = report.uniqueSongs.filter((song) => !skipped.has(song));
  for (const r of report.duplicateRecords) {
    if (!(duplicateSkips.get(r.id) ?? r.shouldSkipDuplicate)) {
      result.push({ ...r.duplicateSong, title: `${r.duplicateSong.title} (wersja alternatywna)` });
    }
  }
  return result;
}
