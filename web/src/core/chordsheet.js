// @ts-check
// Dopasowanie arkusza chwytów do slajdu dla ekranu muzyków: odpowiednik ChordSheet z wersji macOS (wzorzec).
// Zgodność pilnują shared/fixtures/chordsheet.json.
//
// 1. Wiersze arkusza, których słowa są w slajdzie, to kandydaci; wybieramy najdłuższy ciągły fragment.
// 2. Fragment bez chwytów dostaje chwyty z pierwszej sekcji tego samego rodzaju (zwrotka / refren), wiersz po wierszu.
// 3. Gdy tekst slajdu nie pasuje do arkusza (inna wersja tekstu), slajd dostaje chwyty takiej sekcji wiersz po wierszu.
// Chwyty w nawiasie na końcu wiersza, także sklejone („(Afis)” = A fis), są przenoszone nad tekst.

import { searchFold } from "./text.js";
import { isChordLine, transpose } from "./chords.js";
import { splitChords } from "./songselect.js";

/** @typedef {{chords: string | null, text: string}} ChordLine */
/** @typedef {{header: string | null, lines: ChordLine[], isChorus: boolean}} Section */
/** @typedef {{lines: ChordLine[], borrowedFrom: string | null}} ChordSheetResult */

const HEADER_WORDS = new Set(["ref", "r", "refren", "chorus", "zwrotka", "z", "verse", "bridge", "coda", "koda"]);
const CHORD_AT_START = /^[A-Ha-h](?:is|es|s|#|b)?(?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*(?:\/[A-Ha-h](?:is|es|s|#|b)?)?/u;
const TRAILING_GROUP = /\s*\(([^()]+)\)\s*$/u;
const trimSpaces = (/** @type {string} */ s) => s.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
const tokens = (/** @type {string} */ s) => s.split(/[\s,]+/u).filter(Boolean);

/** Słowa do porównania: bez znaków diakrytycznych, interpunkcji i oznaczeń sekcji („Ref.”). @param {string} text */
export function words(text) {
  return searchFold(text).split(" ").filter((w) => w && !HEADER_WORDS.has(w) && !/^\p{N}+$/u.test(w));
}

/** @param {string} line */
function isHeader(line) {
  const trimmed = trimSpaces(line);
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) return true;
  return trimmed.endsWith(":") && Array.from(trimmed).length <= 30 && !isChordLine(trimmed.slice(0, -1));
}

/** „Afis” → ["A", "fis"]; null, gdy to nie same akordy. @param {string} token */
export function splitConcatenatedChords(token) {
  let rest = token;
  /** @type {string[]} */
  const chords = [];
  while (rest) {
    const match = CHORD_AT_START.exec(rest);
    if (!match || !match[0]) return null;
    chords.push(match[0]);
    rest = rest.slice(match[0].length);
  }
  return chords.length ? chords : null;
}

/** Akordy z grupy w nawiasie albo null. @param {string} group */
function chordsIn(group) {
  /** @type {string[]} */
  const chords = [];
  for (const token of tokens(group)) {
    const split = splitConcatenatedChords(token);
    if (!split) return null;
    chords.push(...split);
  }
  return chords.length ? chords : null;
}

/** Linia z samymi akordami w nawiasie: „(dgCF)” → „d g C F”. @param {string} line */
function parenthesizedChordLine(line) {
  if (!line.startsWith("(") || !line.endsWith(")") || Array.from(line).length <= 2) return null;
  return chordsIn(line.slice(1, -1))?.join(" ") ?? null;
}

/** „leczy wszystkie choroby (E)” → akordy „E” nad tekstem bez nawiasu. @param {string} line @returns {ChordLine | null} */
function trailingChords(line) {
  const match = TRAILING_GROUP.exec(line);
  if (!match) return null;
  const chords = chordsIn(match[1]);
  const text = trimSpaces(line.slice(0, match.index));
  return chords && text ? { chords: chords.join(" "), text } : null;
}

/** @param {string} sheet @returns {Section[]} */
export function sections(sheet) {
  /** @type {Section[]} */
  const result = [];
  /** @type {Section} */
  let current = { header: null, lines: [], isChorus: false };
  /** @type {string | null} */
  let pending = null;

  const finish = () => {
    if (pending !== null) {
      current.lines.push({ chords: pending, text: "" });
      pending = null;
    }
    if (current.lines.length) {
      const header = (current.header ?? "").toLowerCase();
      const firstText = searchFold(current.lines.find((l) => l.text)?.text ?? "");
      current.isChorus = header.includes("ref") || header.includes("chorus") || firstText.startsWith("ref ") || firstText.startsWith("r ");
      result.push(current);
    }
    current = { header: null, lines: [], isChorus: false };
  };

  for (const rawLine of sheet.replace(/\r\n/g, "\n").split("\n")) {
    const line = rawLine.replace(/\t/g, "    ");
    const trimmed = trimSpaces(line);
    const parenthesized = trimmed ? parenthesizedChordLine(trimmed) : null;
    const bracketed = trimmed.includes("[") ? splitChords(trimmed) : null;
    if (!trimmed) {
      finish();
    } else if (parenthesized !== null) {
      if (pending !== null) current.lines.push({ chords: pending, text: "" });
      pending = parenthesized;
    } else if (isChordLine(line)) {
      if (pending !== null) current.lines.push({ chords: pending, text: "" });
      pending = line.replace(/^[\n\r]+|[\n\r]+$/g, "");
    } else if (isHeader(trimmed)) {
      if (current.lines.length || pending !== null) finish();
      current.header = trimmed.replace(/^[[\]:]+|[[\]:]+$/g, "");
    } else if (bracketed?.chords) {
      current.lines.push({ chords: bracketed.chords, text: bracketed.lyrics });
    } else {
      const inline = trailingChords(trimmed);
      if (inline) {
        // Chwyty przy wierszu wygrywają; wcześniejsza linia samych akordów to wstęp.
        if (pending !== null) {
          current.lines.push({ chords: pending, text: "" });
          pending = null;
        }
        current.lines.push(inline);
      } else {
        current.lines.push({ chords: pending, text: trimmed });
        pending = null;
      }
    }
  }
  finish();
  return result;
}

const hasChords = (/** @type {Section} */ s) => s.lines.some((l) => l.chords !== null);
const lyricLines = (/** @type {Section} */ s) => s.lines.filter((l) => l.text);

/** Część słów slajdu obecnych we wskazanych wierszach (każde słowo liczone raz). @param {string[]} slideWords @param {string[]} lines */
function coverage(slideWords, lines) {
  if (!slideWords.length) return 0;
  /** @type {Map<string, number>} */
  const available = new Map();
  for (const word of words(lines.join(" "))) available.set(word, (available.get(word) ?? 0) + 1);
  let found = 0;
  for (const word of slideWords) {
    const count = available.get(word) ?? 0;
    if (count > 0) {
      available.set(word, count - 1);
      found++;
    }
  }
  return found / slideWords.length;
}

/**
 * Wiersze slajdu z chwytami, transponowanymi o `semitones` względem pierwszego akordu całej pieśni.
 * Bez arkusza albo bez chwytów: sam tekst slajdu.
 * @param {{text: string, type: string}} slide @param {string | null | undefined} sheet @param {number} [semitones]
 * @returns {ChordSheetResult}
 */
export function linesForSlide(slide, sheet, semitones = 0) {
  const slideLines = slide.text.split("\n");
  /** @type {ChordSheetResult} */
  const plain = { lines: slideLines.map((text) => ({ chords: null, text })), borrowedFrom: null };
  if (!sheet || !sheet.trim()) return plain;
  const all = sections(sheet);
  if (!all.some(hasChords)) return plain;
  const slideWords = words(slide.text);
  const slideSet = new Set(slideWords);
  const isChorus = slide.type === "chorus";

  /** @type {{section: number, position: number, line: ChordLine}[]} */
  const flat = [];
  all.forEach((section, sectionIndex) => lyricLines(section).forEach((line, position) => flat.push({ section: sectionIndex, position, line })));
  const candidate = flat.map((entry) => {
    const lineWords = words(entry.line.text);
    return lineWords.length > 0 && lineWords.filter((w) => slideSet.has(w)).length / lineWords.length >= 0.6;
  });
  /** @type {[number, number] | null} */
  let best = null;
  /** @type {number | null} */
  let start = null;
  for (let index = 0; index <= flat.length; index++) {
    if (index < flat.length && candidate[index]) {
      start ??= index;
    } else if (start !== null) {
      if (index - start > (best ? best[1] - best[0] : 0)) best = [start, index];
      start = null;
    }
  }

  /** @type {ChordSheetResult} */
  let result;
  const run = best ? flat.slice(best[0], best[1]) : [];
  if (best && coverage(slideWords, run.map((e) => e.line.text)) >= 0.5) {
    const lines = run.map((e) => ({ ...e.line }));
    /** @type {string | null} */
    let borrowedFrom = null;
    const runIsChorus = all[run[0].section].isChorus;
    const donor = lines.some((l) => l.chords !== null) ? undefined : all.find((s) => hasChords(s) && s.isChorus === runIsChorus);
    if (donor) {
      const donorLines = lyricLines(donor);
      run.forEach((entry, offset) => {
        if (entry.position < donorLines.length) lines[offset].chords = donorLines[entry.position].chords;
      });
      borrowedFrom = donor.header ?? donorLines[0]?.text ?? null;
    }
    result = { lines, borrowedFrom };
  } else {
    const donor = all.find((s) => hasChords(s) && s.isChorus === isChorus) ?? all.find(hasChords);
    if (!donor) return plain;
    // Inna wersja tekstu niż w arkuszu: chwyty pierwszej sekcji tego rodzaju, wiersz po wierszu.
    const donorLines = lyricLines(donor);
    result = {
      lines: slideLines.map((text, index) => ({ chords: index < donorLines.length ? donorLines[index].chords : null, text })),
      borrowedFrom: donor.header ?? donorLines[0]?.text ?? null,
    };
  }

  if (semitones % 12 !== 0) {
    // Wszystkie linie chwytów razem z pierwszym akordem pieśni: ta sama tonacja i zapis (♯/♭) na każdym slajdzie.
    const reference = all.flatMap((s) => s.lines).find((l) => l.chords !== null)?.chords ?? "";
    const indices = result.lines.map((l, i) => (l.chords !== null ? i : -1)).filter((i) => i >= 0);
    const joined = [reference, ...indices.map((i) => /** @type {string} */ (result.lines[i].chords))].join("\n");
    const transposed = transpose(joined, semitones).split("\n").slice(1);
    indices.forEach((lineIndex, k) => { result.lines[lineIndex].chords = transposed[k]; });
  }
  return result;
}
