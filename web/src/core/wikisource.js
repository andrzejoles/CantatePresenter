// @ts-check
// Wyszukiwanie pieśni w Wikiźródłach przez API MediaWiki: odpowiednik OnlineSearchService i WikisourceParser
// z wersji macOS (S9). Teksty w domenie publicznej albo na wolnej licencji; adres strony trafia do pieśni.
// Zgodność pilnują shared/fixtures/wikisource.json.

const SUPPORTED = new Set(["pl", "en", "de", "es", "uk", "fr", "it", "la"]);
const MAX_RESULTS = 12;

/** Wersja językowa Wikiźródeł; „wszystkie języki” szukają w polskiej. @param {string} language */
export const host = (language) => `${SUPPORTED.has(language) ? language : "pl"}.wikisource.org`;

/** @param {string} title @param {string} language */
export function pageURL(title, language) {
  // Jak addingPercentEncoding(.urlPathAllowed) w macOS: te znaki zostają niezakodowane.
  const path = encodeURIComponent(title.replace(/ /g, "_"))
    .replace(/%(24|26|2B|2C|3B|3D|3A|40|2F)/g, (_, code) => String.fromCharCode(parseInt(code, 16)));
  return `https://${host(language)}/wiki/${path}`;
}

/** @param {string} pattern @param {string} text */
const matches = (pattern, text) => [...text.matchAll(new RegExp(pattern, "gs"))].map((m) => m[1]);
/** @param {string} pattern @param {string} text @param {string} replacement */
const replacing = (pattern, text, replacement) => text.replace(new RegExp(pattern, "gsi"), replacement);
const trimSpaces = (/** @type {string} */ s) => s.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");

/** Encje HTML jak w macOS: nazwane, liczbowe, na końcu &amp;. @param {string} text */
export function decodeEntities(text) {
  if (!text.includes("&")) return text;
  let result = text;
  for (const [entity, value] of [["&nbsp;", " "], ["&quot;", "\""], ["&#39;", "'"], ["&apos;", "'"], ["&lt;", "<"], ["&gt;", ">"]]) {
    result = result.split(entity).join(value);
  }
  result = result.replace(/&#(x?)([0-9a-fA-F]+);/g, (whole, hex, digits) => {
    const code = parseInt(digits, hex ? 16 : 10);
    return Number.isFinite(code) && code <= 0x10ffff && (code < 0xd800 || code > 0xdfff) ? String.fromCodePoint(code) : whole;
  });
  return result.split("&amp;").join("&");
}

/**
 * Koniec bloku i początek następnego są jedną zwrotką, gdy obie części są krótsze od typowej zwrotki
 * i razem jej nie przekraczają. @param {string[][][]} blocks
 */
function mergeSplitStanzas(blocks) {
  /** @type {Map<number, number>} */
  const frequency = new Map();
  for (const block of blocks) for (const stanza of block) frequency.set(stanza.length, (frequency.get(stanza.length) ?? 0) + 1);
  let typical = 0, best = -1;
  for (const [count, times] of frequency) {
    if (times > best || (times === best && count > typical)) { typical = count; best = times; }
  }
  /** @type {string[][]} */
  const result = [];
  let carry = false;
  for (const block of blocks) {
    block.forEach((stanza, index) => {
      const last = result[result.length - 1];
      if (index === 0 && carry && last && last.length < typical && stanza.length < typical && last.length + stanza.length <= typical) {
        result[result.length - 1] = [...last, ...stanza];
      } else {
        result.push(stanza);
      }
    });
    carry = true;
  }
  return result;
}

/** Tekst pieśni z bloków `<div class="poem">`, bez numerów stron i przypisów. @param {string} html */
export function lyricsFromHTML(html) {
  /** @type {string[][][]} */
  const blocks = [];
  for (const body of matches(`<div class="poem"[^>]*>(.*?)</div>`, html)) {
    let text = replacing(`<span[^>]*ws-pagenum[^>]*>.*?</span>`, body, "");
    text = replacing(`<sup[^>]*>.*?</sup>`, text, "");
    text = text.split("\n").join("");
    text = replacing(`<br\\s*/?>`, text, "\n");
    text = replacing(`</p>`, text, "\n\n");
    text = decodeEntities(replacing(`<[^>]+>`, text, ""));
    /** @type {string[][]} */
    const stanzas = [];
    /** @type {string[]} */
    let current = [];
    for (const line of text.split("\n").map(trimSpaces)) {
      if (line) current.push(line);
      else if (current.length) { stanzas.push(current); current = []; }
    }
    if (current.length) stanzas.push(current);
    if (stanzas.length) blocks.push(stanzas);
  }
  return mergeSplitStanzas(blocks).map((s) => s.join("\n")).join("\n\n");
}

/** @param {string} html @returns {"publicDomain" | "ccBySA" | "unknown"} */
export function licenseFromHTML(html) {
  const lower = html.toLowerCase();
  if (lower.includes("public domain") || lower.includes("własnością publiczną") || lower.includes("gemeinfrei")) return "publicDomain";
  if (lower.includes("creative commons")) return "ccBySA";
  return "unknown";
}

/** Autor z parametru `autor` szablonu „Dane tekstu” (albo `author`); odnośniki zamieniane na nazwę. @param {string} wikitext */
export function authorFromWikitext(wikitext) {
  const raw = matches(`\\|\\s*(?:autor|author)\\s*=((?:\\[\\[[^\\]]*\\]\\]|[^\\n|\\[])*)`, wikitext)[0];
  if (raw === undefined) return "";
  let value = replacing(`\\[\\[[^\\]|]*\\|([^\\]]*)\\]\\]`, raw, "$1");
  value = replacing(`\\[\\[(?:[^\\]:]*:)?([^\\]]*)\\]\\]`, value, "$1");
  return trimSpaces(value.split("''").join(""));
}

/** „Śpiewnik kościelny/Boże z twoich rąk żyjemy” → „Boże z twoich rąk żyjemy”; nawias z wydaniem odcięty. @param {string} title */
export function shortTitle(title) {
  const last = title.split("/").pop() ?? title;
  return last.replace(/\s*\([^)]*\)$/u, "");
}

/**
 * @typedef {{title: string, author: string, page: string, lyrics: string, url: string,
 *   license: "publicDomain" | "ccBySA" | "unknown"}} WikisourceResult
 */

/**
 * Wyniki tylko ze stron z tekstem pieśni lub wiersza (ujednoznacznienia i spisy pomijane).
 * Zapytania idą z przeglądarki prosto do Wikiźródeł (CORS z origin=*), jak w macOS z aplikacji.
 * @param {string} query @param {string} language @param {typeof fetch} [fetcher]
 * @returns {Promise<WikisourceResult[]>}
 */
export async function searchWikisource(query, language, fetcher = fetch) {
  const clean = query.trim();
  if (!clean) return [];
  /** @param {Record<string, string>} parameters */
  const api = async (parameters) => {
    const params = new URLSearchParams({ ...parameters, format: "json", formatversion: "2", origin: "*" });
    const response = await fetcher(`https://${host(language)}/w/api.php?${params}`, {
      headers: { "Api-User-Agent": "CantatePresenter-Web (https://github.com/andrzejoles/CantatePresenter)" },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  };
  const found = await api({ action: "query", list: "search", srsearch: clean, srnamespace: "0", srlimit: String(MAX_RESULTS) });
  /** @type {string[]} */
  const titles = (found?.query?.search ?? []).map((/** @type {any} */ hit) => hit.title).filter((/** @type {unknown} */ t) => typeof t === "string");
  const pages = await Promise.all(titles.map(async (page) => {
    try {
      const parsed = (await api({ action: "parse", page, prop: "text|wikitext", disablelimitreport: "1" }))?.parse;
      if (typeof parsed?.text !== "string") return null;
      const lyrics = lyricsFromHTML(parsed.text);
      if (!lyrics) return null;
      return {
        title: shortTitle(page), author: authorFromWikitext(typeof parsed.wikitext === "string" ? parsed.wikitext : ""),
        page, lyrics, url: pageURL(page, language), license: licenseFromHTML(parsed.text),
      };
    } catch {
      return null;
    }
  }));
  return /** @type {WikisourceResult[]} */ (pages.filter((p) => p !== null));
}
