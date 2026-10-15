// @ts-check
// Import plików tekstowych: odpowiednik TextImporter z macOS (kodowanie, metadane w pierwszych liniach).

const POLISH = new Set(Array.from("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"));
const SUSPICIOUS = new Set(Array.from("±¶¼¦¬ˇ˘˝˙¤§¨®°µ·¸ŠšŤťŽľĽĹĺŕŔřŘůŮ∂∑∏√∞≈≠≤≥◊ﬁﬂ"));
/** Kodowania jednobajtowe próbowane, gdy plik nie jest poprawnym UTF-8; kolejność rozstrzyga remisy. */
const SINGLE_BYTE = ["windows-1250", "iso-8859-2", "macintosh"];

/** @param {string} text */
function score(text) {
  let result = 0;
  for (const c of text) {
    if (POLISH.has(c)) result += 2;
    else if (SUSPICIOUS.has(c)) result -= 3;
    else if (/\p{Cc}/u.test(c) && !"\n\r\t".includes(c)) result -= 5;
  }
  return result;
}

/**
 * UTF-8, a jeśli to niemożliwe, kodowanie jednobajtowe z najlepszym wynikiem (najwięcej polskich liter).
 * @param {Uint8Array} bytes
 */
export function decodeText(bytes) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes).replace(/^﻿/, "");
  } catch {
    let best = "";
    let bestScore = -Infinity;
    for (const encoding of SINGLE_BYTE) {
      const text = new TextDecoder(encoding).decode(bytes);
      const value = score(text);
      if (value > bestScore) { best = text; bestScore = value; }
    }
    return best;
  }
}

/**
 * Pieśń z tekstu: pierwsze linie mogą zawierać Tytuł:/Autor:/Tonacja:/Tagi:, a pierwsza linia bez znacznika to tytuł.
 * @param {string} rawContent @param {string} fallbackTitle
 */
export function parseTextSong(rawContent, fallbackTitle) {
  const normalized = rawContent.replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
  const lines = normalized.split("\n");
  let title = fallbackTitle, author = "", key = "";
  /** @type {string[]} */
  let tags = [];
  let start = 0;
  const value = (/** @type {string} */ line) => line.slice(line.indexOf(":") + 1).trim();
  lines.slice(0, 8).forEach((rawLine, i) => {
    const line = rawLine.trim();
    const lower = line.toLowerCase();
    if (/^(tytuł|tytul|title):/.test(lower)) { title = value(line); start = Math.max(start, i + 1); }
    else if (/^(autor|author):/.test(lower)) { author = value(line); start = Math.max(start, i + 1); }
    else if (/^(tonacja|klucz|key):/.test(lower)) { key = value(line); start = Math.max(start, i + 1); }
    else if (/^(tagi|kategoria|tags):/.test(lower)) {
      tags = value(line).split(/[,;]/).map((t) => t.trim()).filter(Boolean);
      start = Math.max(start, i + 1);
    } else if (i === 0 && !line.startsWith("[") && !lower.startsWith("1.") && !lower.startsWith("ref")) {
      title = line;
      start = 1;
    }
  });
  return { title: title || fallbackTitle, author, key, tags, rawLyrics: lines.slice(start).join("\n").trim() };
}
