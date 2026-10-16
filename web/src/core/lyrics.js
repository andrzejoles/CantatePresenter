// @ts-check
// Podział tekstu pieśni na slajdy: odpowiednik Song.parseLyrics z wersji macOS (wzorzec).
// Zgodność pilnują shared/fixtures/lyrics.json.

/** Kody typów slajdów zapisywane w JSON (jak SlideType w Swift). */
export const SlideType = Object.freeze({
  verse: "verse", chorus: "chorus", bridge: "bridge", preChorus: "preChorus", coda: "coda",
  interlude: "interlude", intro: "intro", outro: "outro", ending: "ending", tag: "tag",
  blank: "blank", custom: "custom",
});

/** Domyślne polskie nazwy typów (klucze tłumaczeń). */
export const polishName = Object.freeze({
  verse: "Zwrotka", chorus: "Refren", bridge: "Bridge", preChorus: "Pre-Chorus", coda: "Coda",
  interlude: "Przejście", intro: "Intro", outro: "Outro", ending: "Zakończenie", tag: "Tag",
  blank: "Pusty", custom: "Własny",
});

export const shortBadge = Object.freeze({
  verse: "Z", chorus: "R", bridge: "B", preChorus: "PC", coda: "CODA", interlude: "PRZ",
  intro: "IN", outro: "OUT", ending: "ZAK", tag: "TAG", blank: "—", custom: "•",
});

/** Polskie nazwy typów zapisywane przez dawne wersje aplikacji. */
const LEGACY_NAMES = Object.freeze({
  "Zwrotka": "verse", "Refren": "chorus", "Bridge": "bridge", "Pre-Chorus": "preChorus", "Coda": "coda",
  "Przejście": "interlude", "Intro": "intro", "Outro": "outro", "Zakończenie": "ending", "Tag": "tag",
  "Pusty": "blank", "Własny": "custom",
});

/**
 * Kod typu z JSON: kod, stara polska nazwa albo `custom` dla nieznanych.
 * @param {unknown} value
 */
export function slideTypeFrom(value) {
  const text = String(value ?? "");
  if (Object.hasOwn(SlideType, text)) return text;
  return LEGACY_NAMES[/** @type {keyof typeof LEGACY_NAMES} */ (text)] ?? SlideType.custom;
}

/**
 * Liczba na końcu etykiety („Zwrotka 2” → 2).
 * @param {string} label
 * @returns {number | null}
 */
export function trailingNumber(label) {
  const match = /(\d+)$/.exec(label);
  return match ? Number(match[1]) : null;
}

const PRE_CHORUS = ["pre-chorus", "prechorus", "pre chorus", "przed-refren", "przedrefren", "przed refren"];
const HEADER = /^\[([^\]]+)\]$|^([0-9]+)\.?$|^(pre[- ]?chorus|przed[- ]?refren|ref(ren)?|chorus|bridge|most(ek)?|coda|koda|interlude|przej[sś]cie|solo|intro|wst[eę]p|outro|zako[nń]czenie|ending|tag|zwrotka|z)(\s*[0-9]*)?:?$/i;
const NUMBERED = new Set(["verse", "chorus", "bridge", "coda", "interlude", "ending"]);
const NEWLINES = /[\n\u000B\u000C\r\u0085\u2028\u2029]/;

/** Przycięcie jak `.whitespaces` w Swift (spacje i tabulatory, bez znaków nowej linii). */
const trimSpaces = (/** @type {string} */ s) => s.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
/** Przycięcie jak `.whitespacesAndNewlines`. */
const trimAll = (/** @type {string} */ s) => s.replace(/^[\s\u0085]+|[\s\u0085]+$/g, "");
/** Przycięcie wybranych znaków z obu końców. */
const trimChars = (/** @type {string} */ s, /** @type {string} */ chars) => {
  let start = 0, end = s.length;
  while (start < end && chars.includes(s[start])) start++;
  while (end > start && chars.includes(s[end - 1])) end--;
  return s.slice(start, end);
};
/** Tekst za nagłówkiem w tej samej linii, bez dwukropka i spacji na początku; null, gdy pusty. */
const textAfterHeader = (/** @type {string} */ rest) => {
  const text = trimSpaces(rest.replace(/^[: \t]+/, ""));
  return text ? text : null;
};
/** Tekst po pierwszym dwukropku, przycięty. */
const afterColon = (/** @type {string} */ s) => trimSpaces(s.slice(s.indexOf(":") + 1));

/**
 * @typedef {{type: string, label: string, text: string, number: number | null}} ParsedSlide
 */

/**
 * Dzieli tekst na slajdy: bloki rozdzielone pustą linią, nagłówki `[Zwrotka 1]`, `[Refren]`, `Ref:`, `R:` itd.
 * @param {string} raw
 * @returns {ParsedSlide[]}
 */
export function parseLyrics(raw) {
  raw = String(raw ?? "");
  const normalized = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const blocks = normalized.split("\n\n").map(trimAll).filter((b) => b.length > 0);
  if (blocks.length === 0) {
    return [{ type: "verse", label: "Zwrotka 1", text: trimAll(raw), number: null }];
  }

  /** @type {ParsedSlide[]} */
  const slides = [];
  let verse = 1, chorus = 1, bridge = 1, coda = 1, interlude = 1, ending = 1;

  for (const block of blocks) {
    const lines = block.split(NEWLINES).map(trimSpaces);
    if (lines.length === 0) continue;
    let type = "verse";
    let label = "";
    const first = lines[0];
    const lower = first.toLowerCase();
    const prefixed = ["[", "ref:", "refren:", "chorus:", "coda:", "koda:", "przejście:", "przejscie:", "zakończenie:"].some((p) => lower.startsWith(p));

    const isHeader = HEADER.test(first);
    if (isHeader || prefixed) {
      // Tekst w tej samej linii co nagłówek („Ref: Chwała Panu”, „[Refren] Chwała”) zostaje w slajdzie.
      let header;
      let inline = null;
      const close = first.indexOf("]");
      if (lower.startsWith("[") && close >= 0) {
        header = trimChars(first.slice(1, close), "[]: \t");
        inline = textAfterHeader(first.slice(close + 1));
      } else if (!isHeader && first.includes(":")) {
        const colon = first.indexOf(":");
        header = trimChars(first.slice(0, colon), "[]: \t");
        inline = textAfterHeader(first.slice(colon + 1));
      } else {
        header = trimChars(first, "[]: \t");
      }
      const h = header.toLowerCase();
      if (PRE_CHORUS.some((k) => h.includes(k))) {
        type = "preChorus"; label = "Pre-Chorus";
      } else if (h.includes("coda") || h.includes("koda")) {
        type = "coda"; label = coda > 1 ? `Coda ${coda}` : "Coda"; coda++;
      } else if (h.includes("interlude") || h.includes("przejscie") || h.includes("przejście") || h.includes("solo")) {
        type = "interlude"; label = interlude > 1 ? `Przejście ${interlude}` : "Przejście"; interlude++;
      } else if (h.includes("zakonczenie") || h.includes("zakończenie") || h.includes("ending")) {
        type = "ending"; label = ending > 1 ? `Zakończenie ${ending}` : "Zakończenie"; ending++;
      } else if (h.includes("outro")) {
        type = "outro"; label = "Outro";
      } else if (h.includes("intro") || h.includes("wstep") || h.includes("wstęp")) {
        type = "intro"; label = "Intro";
      } else if (h.includes("ref") || h.includes("chorus") || h === "r") {
        type = "chorus"; label = chorus > 1 ? `Refren ${chorus}` : "Refren"; chorus++;
      } else if (h.includes("bridge") || h === "b" || h.includes("most")) {
        type = "bridge"; label = bridge > 1 ? `Bridge ${bridge}` : "Bridge"; bridge++;
      } else if (h.includes("pre")) {
        type = "preChorus"; label = "Pre-Chorus";
      } else if (h.includes("tag")) {
        type = "tag"; label = "Tag";
      } else {
        type = "verse"; label = header;
      }
      if (inline !== null) lines[0] = inline;
      else lines.shift();
    } else if (lower.startsWith("ref:") || lower.startsWith("refren:")) {
      type = "chorus"; label = chorus > 1 ? `Refren ${chorus}` : "Refren"; chorus++;
      lines[0] = afterColon(lines[0]);
    } else if (lower.startsWith("r:")) {
      type = "chorus"; label = chorus > 1 ? `Refren ${chorus}` : "Refren"; chorus++;
      lines[0] = trimSpaces(lines[0].slice(2));
    } else if (lower.startsWith("coda:") || lower.startsWith("koda:")) {
      type = "coda"; label = coda > 1 ? `Coda ${coda}` : "Coda"; coda++;
      lines[0] = afterColon(lines[0]);
    } else if (lower.startsWith("przejście:") || lower.startsWith("przejscie:") || lower.startsWith("interlude:")) {
      type = "interlude"; label = interlude > 1 ? `Przejście ${interlude}` : "Przejście"; interlude++;
      lines[0] = afterColon(lines[0]);
    } else if (lower.startsWith("zakończenie:") || lower.startsWith("zakonczenie:") || lower.startsWith("ending:")) {
      type = "ending"; label = ending > 1 ? `Zakończenie ${ending}` : "Zakończenie"; ending++;
      lines[0] = afterColon(lines[0]);
    } else {
      type = "verse"; label = `Zwrotka ${verse}`; verse++;
    }

    const text = trimAll(lines.join("\n"));
    if (text) {
      const number = trailingNumber(label) ?? (NUMBERED.has(type) ? 1 : null);
      slides.push({ type, label, text, number });
    }
  }
  return slides.length ? slides : [{ type: "verse", label: "Zwrotka 1", text: raw, number: null }];
}
