// @ts-check
// Transpozycja arkusza akordów: odpowiednik ChordTransposer z wersji macOS (wzorzec).
// Notacja polska/niemiecka: H = H, B = B♭; krzyżyki i bemole jako #/b albo is/es.
// Zgodność pilnują shared/fixtures/transpose.json.

const NATURAL = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 10, H: 11 };
const SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"];
const FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "B", "H"];
const GERMAN_SHARP = ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "Ais", "H"];
const GERMAN_FLAT = ["C", "Des", "D", "Es", "E", "F", "Ges", "G", "As", "A", "B", "H"];
/** Tonacje zapisywane z bemolami: F, B, Es, As, Des dur oraz d, g, c, f, b moll. */
const FLAT_MAJOR = new Set([5, 10, 3, 8, 1]);
const FLAT_MINOR = new Set([2, 7, 0, 5, 10]);

const CHORD = /^([A-Ha-h])(is|es|s|#|b)?((?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*)(?:\/([A-Ha-h])(is|es|s|#|b)?)?$/u;
const REPEAT = /^x?\d+x?$/;
const isSpace = (/** @type {string} */ c) => /\s/u.test(c);
const length = (/** @type {string} */ s) => Array.from(s).length;

/**
 * @typedef {{root: number, isLowercase: boolean, suffix: string, bass: number | null,
 *            bassIsLowercase: boolean, german: boolean}} Chord
 */

/** @param {string} letter @param {string | undefined} accidental */
function pitch(letter, accidental) {
  const upper = letter.toUpperCase();
  const natural = NATURAL[/** @type {keyof typeof NATURAL} */ (upper)];
  if (natural === undefined) return null;
  let offset = 0;
  if (accidental === "#" || accidental === "is") offset = 1;
  else if (accidental === "b" && upper === "B") offset = 0;
  else if (accidental === "b" || accidental === "es" || accidental === "s") offset = -1;
  return (natural + offset + 12) % 12;
}

/** @param {string} token @returns {Chord | null} */
export function parseChord(token) {
  const m = CHORD.exec(token);
  if (!m) return null;
  const root = pitch(m[1], m[2]);
  if (root === null) return null;
  let bass = null;
  let bassIsLowercase = false;
  if (m[4] !== undefined) {
    bass = pitch(m[4], m[5]);
    if (bass === null) return null;
    bassIsLowercase = m[4] === m[4].toLowerCase();
  }
  return {
    root,
    isLowercase: m[1] === m[1].toLowerCase(),
    suffix: m[3] ?? "",
    bass,
    bassIsLowercase,
    german: [m[2], m[5]].some((a) => a === "is" || a === "es" || a === "s"),
  };
}

/** @param {Chord} chord */
const isMinor = (chord) =>
  chord.isLowercase || (chord.suffix.startsWith("m") && !chord.suffix.startsWith("maj")) || chord.suffix.startsWith("min");

/** @param {string} s */
const stripBrackets = (s) => s.replace(/^[()[\]]+|[()[\]]+$/g, "");

/** Wyraz dopuszczalny w linii akordowej, ale niebędący akordem (`|`, `-`, `x2`, `(x2)`). @param {string} token */
function isNeutral(token) {
  const stripped = stripBrackets(token);
  if (!stripped || Array.from(stripped).every((c) => !/[\p{L}\p{N}]/u.test(c))) return true;
  return REPEAT.test(stripped);
}

/** @param {string} line */
const words = (line) => line.split(/\s+/u).filter(Boolean);

/** Linia złożona wyłącznie z akordów (i znaków pomocniczych). @param {string} line */
export function isChordLine(line) {
  let chords = 0;
  for (const token of words(line)) {
    if (parseChord(stripBrackets(token))) chords++;
    else if (!isNeutral(token)) return false;
  }
  return chords > 0;
}

/**
 * Grupy `[...]` i `(...)` złożone z samych akordów, np. `[C]`, `(D A)`; `[Refren]` się nie liczy.
 * @param {string} line
 */
function inlineGroups(line) {
  const chars = Array.from(line);
  /** @type {{start: number, end: number, content: string, open: string, close: string}[]} */
  const groups = [];
  let i = 0;
  while (i < chars.length) {
    const c = chars[i];
    const close = c === "[" ? "]" : c === "(" ? ")" : null;
    const end = close ? chars.indexOf(close, i + 1) : -1;
    if (close && end >= 0) {
      const content = chars.slice(i + 1, end).join("");
      const tokens = words(content);
      if (tokens.length && tokens.every((t) => parseChord(t))) {
        groups.push({ start: i, end: end + 1, content, open: c, close });
      }
      i = end + 1;
    } else {
      i++;
    }
  }
  return groups;
}

/** @param {string} line @returns {Chord[]} */
function chordsIn(line) {
  if (isChordLine(line)) {
    return words(line).map((t) => parseChord(stripBrackets(t))).filter((c) => c !== null);
  }
  return inlineGroups(line).flatMap((g) => words(g.content).map(parseChord).filter((c) => c !== null));
}

/**
 * Transponuje arkusz o podaną liczbę półtonów. Zmienia linie akordowe oraz akordy w `[ ]` i `( )` w tekście.
 * @param {string} sheet
 * @param {number} semitones
 */
export function transpose(sheet, semitones) {
  const shift = ((semitones % 12) + 12) % 12;
  if (shift === 0) return sheet;
  const lines = sheet.split("\n");
  const all = lines.flatMap(chordsIn);
  if (!all.length) return sheet;

  const first = all[0];
  const target = (first.root + shift) % 12;
  const useFlats = isMinor(first) ? FLAT_MINOR.has(target) : FLAT_MAJOR.has(target);
  const german = all.some((c) => c.german);
  const names = german ? (useFlats ? GERMAN_FLAT : GERMAN_SHARP) : useFlats ? FLAT : SHARP;

  /** @param {Chord} chord */
  const render = (chord) => {
    let result = names[(chord.root + shift) % 12];
    if (chord.isLowercase) result = result.toLowerCase();
    result += chord.suffix;
    if (chord.bass !== null) {
      const bass = names[(chord.bass + shift) % 12];
      result += "/" + (chord.bassIsLowercase ? bass.toLowerCase() : bass);
    }
    return result;
  };

  return lines.map((line) => (isChordLine(line) ? transposeChordLine(line, render) : transposeInline(line, render))).join("\n");
}

/** Akordy na swoich kolumnach; gdy poprzedni się wydłużył, jedna spacja odstępu. */
function transposeChordLine(/** @type {string} */ line, /** @type {(c: Chord) => string} */ render) {
  const chars = Array.from(line);
  let result = "";
  let column = 0;
  let i = 0;
  while (i < chars.length) {
    if (isSpace(chars[i])) { i++; column++; continue; }
    let end = i;
    while (end < chars.length && !isSpace(chars[end])) end++;
    const token = chars.slice(i, end).join("");
    const core = stripBrackets(token);
    let replacement = token;
    const chord = parseChord(core);
    if (chord && token.includes(core)) replacement = token.replace(core, render(chord));
    const padding = result === "" ? column : Math.max(column - length(result), 1);
    result += " ".repeat(padding) + replacement;
    column += length(token);
    i = end;
  }
  return result;
}

function transposeInline(/** @type {string} */ line, /** @type {(c: Chord) => string} */ render) {
  const chars = Array.from(line);
  let result = "";
  let cursor = 0;
  for (const g of inlineGroups(line)) {
    const transposed = g.content.split(" ").map((t) => { const c = parseChord(t); return c ? render(c) : t; }).join(" ");
    result += chars.slice(cursor, g.start).join("") + g.open + transposed + g.close;
    cursor = g.end;
  }
  return result + chars.slice(cursor).join("");
}
