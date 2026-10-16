// @ts-check
// Modele danych w tym samym formacie JSON co wersja macOS (songs.json, plans.json, settings.json).
// Odczyt tolerancyjny jak w Swift (K1): brakujące pola dostają wartości domyślne, nieznane pola zostają.

import { parseLyrics, slideTypeFrom, trailingNumber, polishName } from "./lyrics.js";

/** Różnica między epoką Unix a datą odniesienia Foundation (2001-01-01), w sekundach. */
const REFERENCE_DATE_OFFSET = 978307200;

/** Identyfikator jak UUID w Swift (wielkie litery). */
export function uuid() {
  return crypto.randomUUID().toUpperCase();
}

/** Data w formacie zapisywanym przez wersję macOS (ISO 8601 bez milisekund). @param {Date} [date] */
export function isoDate(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * Data z JSON: tekst ISO 8601 (z ułamkami sekund lub bez) albo liczba sekund od 2001-01-01 (domyślne Codable).
 * @param {unknown} value
 * @param {string} [fallback]
 */
export function parseDate(value, fallback) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return isoDate(new Date((value + REFERENCE_DATE_OFFSET) * 1000));
  }
  if (typeof value === "string") {
    const time = Date.parse(value);
    if (!Number.isNaN(time)) return isoDate(new Date(time));
  }
  return fallback ?? isoDate();
}

const str = (/** @type {unknown} */ v, d = "") => (typeof v === "string" ? v : d);
const optStr = (/** @type {unknown} */ v) => (typeof v === "string" ? v : undefined);
const isUUID = (/** @type {unknown} */ v) => typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);

/**
 * @typedef {{id: string, type: string, label: string, text: string, number?: number}} Slide
 * @typedef {{id: string, title: string, author: string, key: string, tags: string[], rawLyrics: string,
 *   chords?: string, slides: Slide[], createdAt: string, updatedAt: string, source?: string,
 *   copyright?: string, ccliNumber?: string}} Song
 * @typedef {{id: string, songId: string, note: string}} PlanItem
 * @typedef {{id: string, name: string, items: PlanItem[], createdAt: string, updatedAt: string}} ServicePlan
 */

/** @param {any} raw @returns {Slide} */
export function normalizeSlide(raw) {
  const type = raw && raw.type !== undefined ? slideTypeFrom(raw.type) : "verse";
  const label = str(raw?.label, polishName[/** @type {keyof typeof polishName} */ (type)]);
  /** @type {Slide} */
  const slide = { id: isUUID(raw?.id) ? String(raw.id).toUpperCase() : uuid(), type, label, text: str(raw?.text) };
  const number = Number.isInteger(raw?.number) ? raw.number : trailingNumber(label);
  if (number !== null && number !== undefined) slide.number = number;
  return slide;
}

/** Slajdy z tekstu pieśni, z nowymi identyfikatorami. @param {string} rawLyrics @returns {Slide[]} */
export function slidesFromLyrics(rawLyrics) {
  return parseLyrics(rawLyrics).map((s) => {
    /** @type {Slide} */
    const slide = { id: uuid(), type: s.type, label: s.label, text: s.text };
    if (s.number !== null) slide.number = s.number;
    return slide;
  });
}

/** @param {any} raw @returns {Song} */
export function normalizeSong(raw) {
  const rawLyrics = str(raw?.rawLyrics);
  const slides = Array.isArray(raw?.slides) ? raw.slides.map(normalizeSlide) : [];
  const createdAt = parseDate(raw?.createdAt);
  /** @type {Song} */
  const song = {
    ...(raw && typeof raw === "object" ? raw : {}),
    id: isUUID(raw?.id) ? String(raw.id).toUpperCase() : uuid(),
    title: str(raw?.title),
    author: str(raw?.author),
    key: str(raw?.key),
    tags: Array.isArray(raw?.tags) ? raw.tags.filter((/** @type {unknown} */ t) => typeof t === "string") : [],
    rawLyrics,
    slides: slides.length === 0 && rawLyrics ? slidesFromLyrics(rawLyrics) : slides,
    createdAt,
    updatedAt: parseDate(raw?.updatedAt, createdAt),
  };
  for (const key of ["chords", "source", "copyright"]) {
    const value = optStr(raw?.[key]);
    if (value === undefined) delete /** @type {any} */ (song)[key];
    else /** @type {any} */ (song)[key] = value;
  }
  // Numer CCLI bywa liczbą (inne programy).
  const ccli = raw?.ccliNumber;
  if (typeof ccli === "string") song.ccliNumber = ccli;
  else if (Number.isInteger(ccli)) song.ccliNumber = String(ccli);
  else delete song.ccliNumber;
  return song;
}

/**
 * Nowa pieśń; slajdy z tekstu.
 * @param {{title: string, author?: string, key?: string, tags?: string[], rawLyrics?: string, chords?: string}} fields
 * @returns {Song}
 */
export function createSong(fields) {
  const now = isoDate();
  /** @type {Song} */
  const song = {
    id: uuid(), title: fields.title, author: fields.author ?? "", key: fields.key ?? "", tags: fields.tags ?? [],
    rawLyrics: fields.rawLyrics ?? "", slides: slidesFromLyrics(fields.rawLyrics ?? ""), createdAt: now, updatedAt: now,
  };
  if (fields.chords) song.chords = fields.chords;
  return song;
}

/** @param {any} raw @returns {ServicePlan | null} */
export function normalizePlan(raw) {
  if (!raw || typeof raw !== "object") return null;
  const createdAt = parseDate(raw.createdAt);
  return {
    ...raw,
    id: isUUID(raw.id) ? String(raw.id).toUpperCase() : uuid(),
    name: str(raw.name, "Nowy plan"),
    // Pozycja bez songId jest pomijana (w Swift jest to pole wymagane pozycji).
    items: (Array.isArray(raw.items) ? raw.items : [])
      .filter((/** @type {any} */ i) => isUUID(i?.songId))
      .map((/** @type {any} */ i) => ({ ...i, id: isUUID(i.id) ? String(i.id).toUpperCase() : uuid(), songId: String(i.songId).toUpperCase(), note: str(i.note) })),
    createdAt,
    updatedAt: parseDate(raw.updatedAt, createdAt),
  };
}

/** @param {string} name @returns {ServicePlan} */
export function createPlan(name) {
  const now = isoDate();
  return { id: uuid(), name, items: [], createdAt: now, updatedAt: now };
}

/** Domyślne skróty: kody klawiszy macOS, jak ShortcutSettings. */
export const DEFAULT_SHORTCUTS = Object.freeze({
  nextSlideKey: 49, prevSlideKey: 123, prevSongKey: 33, nextSongKey: 30,
  startPresentationKey: 36, stopPresentationKey: 53, blackScreenKey: 11, clearTextKey: 8,
});

/** Ustawienia wspólne z macOS (te same klucze i wartości domyślne co AppSettings). */
export const DEFAULT_SETTINGS = Object.freeze({
  fontFamily: "Helvetica Neue",
  isBold: true,
  textColorHex: "#FFFFFF",
  backgroundColorHex: "#000000",
  hasShadow: true,
  textAlignment: "center",
  verticalAlignment: "center",
  marginPercent: 0.07,
  lineSpacingFactor: 1.15,
  uiScale: 1.0,
  appLanguage: "pl",
  activeLogoId: "light_of_glory",
  ccliLicenseNumber: "",
  copyrightNoticePlacement: "firstSlide",
  shortcuts: DEFAULT_SHORTCUTS,
});

const HORIZONTAL = { left: "left", lewo: "left", right: "right", prawo: "right", center: "center" };
const VERTICAL = new Set(["top", "center", "bottom"]);
const PLACEMENTS = new Set(["none", "firstSlide", "lastSlide", "allSlides"]);

/**
 * Ustawienia z JSON; pola tylko z macOS (np. ekran, Dysk Google) zostają bez zmian, żeby kopia wróciła na Maca cała.
 * @param {any} raw
 */
export function normalizeSettings(raw) {
  const input = raw && typeof raw === "object" ? raw : {};
  const d = DEFAULT_SETTINGS;
  const num = (/** @type {unknown} */ v, /** @type {number} */ def, /** @type {number} */ min, /** @type {number} */ max) =>
    typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : def;
  const shortcuts = { ...DEFAULT_SHORTCUTS };
  for (const key of Object.keys(DEFAULT_SHORTCUTS)) {
    const value = input.shortcuts?.[key];
    if (Number.isInteger(value) && value >= 0 && value < 65536) /** @type {any} */ (shortcuts)[key] = value;
  }
  return {
    ...input,
    fontFamily: str(input.fontFamily, d.fontFamily),
    isBold: typeof input.isBold === "boolean" ? input.isBold : d.isBold,
    textColorHex: str(input.textColorHex, d.textColorHex),
    backgroundColorHex: str(input.backgroundColorHex, d.backgroundColorHex),
    hasShadow: typeof input.hasShadow === "boolean" ? input.hasShadow : d.hasShadow,
    textAlignment: HORIZONTAL[/** @type {keyof typeof HORIZONTAL} */ (String(input.textAlignment ?? "").toLowerCase())] ?? "center",
    verticalAlignment: VERTICAL.has(String(input.verticalAlignment ?? "").toLowerCase()) ? String(input.verticalAlignment).toLowerCase() : "center",
    marginPercent: num(input.marginPercent, d.marginPercent, 0, 0.3),
    lineSpacingFactor: num(input.lineSpacingFactor, d.lineSpacingFactor, 0.8, 2),
    uiScale: num(input.uiScale, d.uiScale, 0.7, 2),
    appLanguage: str(input.appLanguage, d.appLanguage),
    activeLogoId: str(input.activeLogoId, d.activeLogoId),
    ccliLicenseNumber: str(input.ccliLicenseNumber, d.ccliLicenseNumber),
    copyrightNoticePlacement: PLACEMENTS.has(input.copyrightNoticePlacement) ? input.copyrightNoticePlacement : d.copyrightNoticePlacement,
    shortcuts,
  };
}

/**
 * Informacja o prawach na slajdzie dla pieśni z numerem CCLI (jak CopyrightNotice w Swift).
 * @param {Song} song @param {number} slideIndex @param {ReturnType<typeof normalizeSettings>} settings
 * @param {(key: string, ...args: unknown[]) => string} t
 */
export function copyrightNotice(song, slideIndex, settings, t) {
  const ccli = (song.ccliNumber ?? "").trim();
  if (!ccli) return null;
  const placement = settings.copyrightNoticePlacement;
  const shown = placement === "allSlides" || (placement === "firstSlide" && slideIndex === 0) ||
    (placement === "lastSlide" && slideIndex === song.slides.length - 1);
  if (!shown) return null;
  const parts = [song.title];
  if (song.author.trim()) parts.push(song.author.trim());
  if ((song.copyright ?? "").trim()) parts.push(/** @type {string} */ (song.copyright).trim());
  parts.push(t("Pieśń CCLI nr {0}", ccli));
  if (settings.ccliLicenseNumber.trim()) parts.push(t("Licencja CCLI nr {0}", settings.ccliLicenseNumber.trim()));
  return parts.join(" · ");
}
