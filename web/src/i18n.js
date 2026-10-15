// @ts-check
// Tłumaczenia: ten sam String Catalog co w macOS (web/i18n/Localizable.xcstrings, kopia z
// Sources/CantatePresenterCore/Resources). Kluczem jest polski tekst, wartości wstawiane jako {0}, {1}.

/** @type {Record<string, Record<string, string>>} */
let catalog = {};
let language = "pl";
/** @type {Set<() => void>} */
const listeners = new Set();

export const SOURCE_LANGUAGE = "pl";
export const LANGUAGES = Object.freeze([
  { code: "pl", name: "Polski", flag: "🇵🇱" },
  { code: "en", name: "English", flag: "🇬🇧" },
  { code: "de", name: "Deutsch", flag: "🇩🇪" },
  { code: "es", name: "Español", flag: "🇪🇸" },
  { code: "uk", name: "Українська", flag: "🇺🇦" },
]);

/** Wczytuje katalog: dla każdego języka mapa klucz → tłumaczenie. @param {URL | string} url */
export async function loadCatalog(url) {
  const data = await (await fetch(url)).json();
  /** @type {Record<string, Record<string, string>>} */
  const result = {};
  for (const [key, entry] of Object.entries(data.strings ?? {})) {
    for (const [lang, value] of Object.entries(/** @type {any} */ (entry).localizations ?? {})) {
      const text = /** @type {any} */ (value).stringUnit?.value;
      if (typeof text === "string") (result[lang] ??= {})[key] = text;
    }
  }
  catalog = result;
  listeners.forEach((listener) => listener());
}

/** @param {string} code */
export function setLanguage(code) {
  language = LANGUAGES.some((l) => l.code === code) ? code : SOURCE_LANGUAGE;
  document.documentElement.lang = language;
  listeners.forEach((listener) => listener());
}

export const currentLanguage = () => language;

/** @param {() => void} listener */
export function onLanguageChange(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/**
 * Tekst interfejsu w bieżącym języku; brak tłumaczenia → polski klucz.
 * @param {string} key @param {...unknown} args
 */
export function t(key, ...args) {
  const template = (language !== SOURCE_LANGUAGE && catalog[language]?.[key]) || key;
  return args.reduce((/** @type {string} */ text, value, index) => text.replaceAll(`{${index}}`, String(value)), template);
}
