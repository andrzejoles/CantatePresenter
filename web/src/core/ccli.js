// @ts-check
// Raport użycia pieśni z numerem CCLI (ccli_usage.json): odpowiednik CCLIUsageReport z wersji macOS.
// Bez klucza partnera API raport zgłasza się ręcznie na stronie CCLI (plik CSV).

import { isoDate, parseDate, uuid } from "./models.js";

/** @typedef {{id: string, date: string, title: string, author: string, ccliNumber: string, copyright?: string}} CCLIUsageEntry */

/** Wpis z JSON (tolerancyjnie, jak dekoder w macOS). @param {any} raw @returns {CCLIUsageEntry} */
export function normalizeUsageEntry(raw) {
  const input = raw && typeof raw === "object" ? raw : {};
  const entry = {
    ...input,
    id: typeof input.id === "string" && input.id ? input.id.toUpperCase() : uuid(),
    date: parseDate(input.date),
    title: typeof input.title === "string" ? input.title : "",
    author: typeof input.author === "string" ? input.author : "",
    ccliNumber: typeof input.ccliNumber === "string" ? input.ccliNumber : typeof input.ccliNumber === "number" ? String(input.ccliNumber) : "",
  };
  if (typeof input.copyright !== "string") delete entry.copyright;
  return entry;
}

/** Ten sam dzień w lokalnej strefie czasowej. @param {Date} a @param {Date} b */
const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/**
 * Nowy wpis dla pieśni z numerem CCLI, najwyżej jeden na pieśń dziennie (jedno nabożeństwo = jedno użycie).
 * @param {{title: string, author: string, ccliNumber?: string, copyright?: string}} song
 * @param {Date} date @param {CCLIUsageEntry[]} existing @returns {CCLIUsageEntry | null}
 */
export function usageEntry(song, date, existing) {
  const number = (song.ccliNumber ?? "").trim();
  if (!number) return null;
  if (existing.some((e) => e.ccliNumber === number && sameDay(new Date(e.date), date))) return null;
  /** @type {CCLIUsageEntry} */
  const entry = { id: uuid(), date: isoDate(date), title: song.title, author: song.author, ccliNumber: number };
  if (song.copyright) entry.copyright = song.copyright;
  return entry;
}

/** @param {string} field */
const escape = (field) => (/[,"\n\r]/.test(field) ? `"${field.replace(/"/g, '""')}"` : field);
/** @param {Date} date */
const day = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;

/** CSV jak w macOS: nagłówki po angielsku (format danych), wiersze po dacie, CRLF. @param {CCLIUsageEntry[]} entries */
export function usageCSV(entries) {
  const lines = ["Date,Title,Authors,CCLI Song Number,Copyright"];
  for (const entry of [...entries].sort((a, b) => Date.parse(a.date) - Date.parse(b.date))) {
    lines.push([day(new Date(entry.date)), entry.title, entry.author, entry.ccliNumber, entry.copyright ?? ""].map(escape).join(","));
  }
  return `${lines.join("\r\n")}\r\n`;
}
