// @ts-check
// Import plików z CCLI SongSelect: odpowiednik SongSelectImporter z macOS (.txt, .usr, ChordPro).

export const CHORDPRO_EXTENSIONS = new Set(["pro", "cho", "chopro", "chordpro", "crd"]);

/** @param {string} number */
export const songURL = (number) => `https://songselect.ccli.com/songs/${number}`;
/** @param {string} query */
export const searchURL = (query) => `https://songselect.ccli.com/search/results?search=${encodeURIComponent(query)}`;

const SECTION = /^(verse|chorus|refrain|pre-chorus|pre chorus|prechorus|bridge|tag|ending|outro|intro|interlude|instrumental|vamp|misc|strophe|coro|verso|puente)(\s+\d+)?:?$/i;

/** „Verse 2” → „[Zwrotka 2]”, „Chorus” → „[Refren]”; null, gdy to nie nagłówek. @param {string} line */
export function sectionMarker(line) {
  const trimmed = line.trim();
  const m = SECTION.exec(trimmed);
  if (!m) return null;
  const number = m[2] ? ` ${m[2].trim()}` : "";
  switch (m[1].toLowerCase()) {
    case "verse": case "strophe": case "verso": return `[Zwrotka${number}]`;
    case "chorus": case "refrain": case "coro": return "[Refren]";
    case "pre-chorus": case "pre chorus": case "prechorus": return "[Pre-Chorus]";
    case "bridge": case "puente": return "[Bridge]";
    case "tag": return "[Tag]";
    case "ending": return "[Zakończenie]";
    case "outro": return "[Outro]";
    case "intro": return "[Intro]";
    case "interlude": case "instrumental": return "[Przejście]";
    default: return `[${m[1]}${number}]`;
  }
}

/** @param {string} text */
const lines = (text) => text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/﻿/g, "").split("\n");
/** @param {string} text */
const digits = (text) => /\d+/.exec(text)?.[0] ?? "";
/** @param {string} line */
const authors = (line) => line.split("|").map((a) => a.trim()).filter(Boolean).join(", ");
/** @param {string[]} input */
function collapse(input) {
  /** @type {string[]} */
  const out = [];
  for (const line of input) {
    if (line === "" && (out.length === 0 || out[out.length - 1] === "")) continue;
    out.push(line);
  }
  return out.join("\n").trim();
}

/**
 * @typedef {{title: string, author: string, key: string, tags: string[], rawLyrics: string, chords?: string,
 *   copyright?: string, ccliNumber?: string, source?: string}} ImportedSong
 */

/** @param {Omit<ImportedSong, "tags" | "source">} song @returns {ImportedSong} */
function make(song) {
  /** @type {ImportedSong} */
  const result = { ...song, tags: ["SongSelect"] };
  if (!result.copyright) delete result.copyright;
  if (!result.chords) delete result.chords;
  if (song.ccliNumber) result.source = songURL(song.ccliNumber);
  else delete result.ccliNumber;
  return result;
}

/** @param {string} text */
export const isSongSelectText = (text) => /^\s*CCLI Song (#|No\.?)\s*\d+/m.test(text);

/** @param {string} text @returns {ImportedSong | null} */
export function parseText(text) {
  const all = lines(text);
  const titleIndex = all.findIndex((l) => l.trim());
  const footerIndex = all.findIndex((l) => /^\s*CCLI Song (#|No\.?)/.test(l));
  if (titleIndex < 0 || footerIndex <= titleIndex) return null;
  let author = "";
  /** @type {string | undefined} */
  let copyright;
  for (const line of all.slice(footerIndex + 1)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("For use solely") || trimmed.startsWith("Note:") || /^CCLI Licen[cs]e/.test(trimmed)) continue;
    if (trimmed.startsWith("©") || trimmed.toLowerCase().startsWith("copyright")) copyright = trimmed;
    else if (!author) author = authors(trimmed);
  }
  /** @type {string[]} */
  const body = [];
  for (const line of all.slice(titleIndex + 1, footerIndex)) {
    const trimmed = line.trim();
    const marker = sectionMarker(trimmed);
    if (marker) {
      if (body.length && body[body.length - 1] !== "") body.push("");
      body.push(marker);
    } else {
      body.push(trimmed);
    }
  }
  return make({ title: all[titleIndex].trim(), author, key: "", rawLyrics: collapse(body), copyright, ccliNumber: digits(all[footerIndex]) });
}

/** @param {string} text @returns {ImportedSong | null} */
export function parseUSR(text) {
  /** @type {Record<string, string>} */
  const values = {};
  let ccliNumber = "";
  for (const line of lines(text)) {
    const trimmed = line.trim();
    if (trimmed.startsWith("[S ")) ccliNumber = digits(trimmed);
    else if (trimmed.includes("=")) {
      const index = trimmed.indexOf("=");
      values[trimmed.slice(0, index).toLowerCase()] = trimmed.slice(index + 1);
    }
  }
  if (!values.title) return null;
  const fields = (values.fields ?? "").split("/t");
  const blocks = (values.words ?? "").split("/t").map((section, index) => {
    const body = section.replaceAll("/n", "\n").trim();
    if (!body) return null;
    const marker = index < fields.length ? sectionMarker(fields[index]) : null;
    return [marker, body].filter(Boolean).join("\n");
  }).filter(Boolean);
  let copyright = values.copyright ? (values.copyright.startsWith("©") ? values.copyright : `© ${values.copyright}`) : undefined;
  if (values.admin && copyright) copyright = `${copyright} (Admin. by ${values.admin})`;
  return make({ title: values.title, author: authors(values.author ?? ""), key: (values.keys ?? "").split("/t")[0] ?? "",
    rawLyrics: blocks.join("\n\n"), copyright, ccliNumber });
}

/** „A[G]mazing [C]grace” → akordy nad tekstem. @param {string} line @returns {{chords: string | null, lyrics: string}} */
export function splitChords(line) {
  if (!line.includes("[")) return { chords: null, lyrics: line };
  let lyrics = "", chords = "", lyricCount = 0, found = false;
  const chars = Array.from(line);
  for (let i = 0; i < chars.length;) {
    const close = chars[i] === "[" ? chars.indexOf("]", i) : -1;
    if (close > i) {
      const chord = chars.slice(i + 1, close).join("");
      let chordCount = Array.from(chords).length;
      if (chordCount > lyricCount) { chords += " "; chordCount++; }
      chords += " ".repeat(Math.max(0, lyricCount - chordCount)) + chord;
      found = true;
      i = close + 1;
    } else {
      lyrics += chars[i];
      lyricCount++;
      i++;
    }
  }
  return found ? { chords, lyrics: lyrics.replace(/\s{2,}/g, " ").trim() } : { chords: null, lyrics: line };
}

/** @param {string} text @param {string} fallbackTitle @returns {ImportedSong} */
export function parseChordPro(text, fallbackTitle) {
  let title = "", key = "", ccliNumber = "", hasChords = false;
  /** @type {string | undefined} */
  let copyright;
  /** @type {string[]} */
  const authorsList = [], lyricLines = [], sheetLines = [];
  const addSection = (/** @type {string} */ marker, /** @type {string} */ label) => {
    if (lyricLines.length && lyricLines[lyricLines.length - 1] !== "") lyricLines.push("");
    if (sheetLines.length && sheetLines[sheetLines.length - 1] !== "") sheetLines.push("");
    lyricLines.push(marker);
    sheetLines.push(`${label}:`);
  };
  for (const line of lines(text)) {
    const trimmed = line.trim();
    if (trimmed.startsWith("#")) continue;
    if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
      const inner = trimmed.slice(1, -1);
      const colon = inner.indexOf(":");
      const name = (colon < 0 ? inner : inner.slice(0, colon)).trim().toLowerCase();
      const value = colon < 0 ? "" : inner.slice(colon + 1).trim();
      switch (name) {
        case "title": case "t": title = value; break;
        case "artist": case "author": case "composer": case "lyricist": case "subtitle": case "st":
          if (value) authorsList.push(...value.split("|").map((a) => a.trim())); break;
        case "key": key = value; break;
        case "copyright": copyright = value.startsWith("©") ? value : `© ${value}`; break;
        case "ccli": ccliNumber = digits(value); break;
        case "comment": case "c": case "comment_italic": case "ci": case "comment_box": case "cb": {
          const marker = sectionMarker(value);
          if (marker) addSection(marker, value);
          break;
        }
        case "start_of_chorus": case "soc": addSection("[Refren]", value || "Chorus"); break;
        case "start_of_bridge": case "sob": addSection("[Bridge]", value || "Bridge"); break;
        case "start_of_verse": case "sov": addSection(value ? sectionMarker(value) ?? `[${value}]` : "[Zwrotka]", value || "Verse"); break;
        default: break;
      }
      continue;
    }
    const marker = sectionMarker(trimmed);
    if (marker) { addSection(marker, trimmed.replace(/^:+|:+$/g, "")); continue; }
    const split = splitChords(trimmed);
    if (split.chords !== null) { hasChords = true; sheetLines.push(split.chords); }
    lyricLines.push(split.lyrics);
    sheetLines.push(split.lyrics);
  }
  return make({ title: title || fallbackTitle, author: authorsList.join(", "), key, rawLyrics: collapse(lyricLines),
    chords: hasChords ? collapse(sheetLines) : undefined, copyright, ccliNumber });
}
