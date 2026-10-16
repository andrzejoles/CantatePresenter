// @ts-check
// Kopia zapasowa .cantatebackup zgodna z wersją macOS: ZIP z songs.json, plans.json, settings.json i manifest.json.

import { createZip, readZip } from "./zip.js";
import { normalizeSong, normalizePlan, normalizeSettings, isoDate, SCHEMA_VERSION } from "./models.js";
import { APP_VERSION } from "../version.js";
import { normalizeUsageEntry } from "./ccli.js";

/**
 * Pliki pomocnicze z wersji macOS (logo, szablony, raport CCLI) wracają do kopii bez zmian.
 * @typedef {{songs: import("./models.js").Song[], plans: import("./models.js").ServicePlan[],
 *   settings: ReturnType<typeof normalizeSettings>, ccliUsage?: import("./ccli.js").CCLIUsageEntry[],
 *   extraFiles?: Map<string, Uint8Array>}} BackupContent
 */

/** Nazwa pliku jak w macOS: CantatePresenter_Backup_RRRR-MM-DD_GG-MM-SS.cantatebackup. @param {Date} [date] */
export function backupFileName(date = new Date()) {
  const pad = (/** @type {number} */ n) => String(n).padStart(2, "0");
  const stamp = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}_${pad(date.getHours())}-${pad(date.getMinutes())}-${pad(date.getSeconds())}`;
  return `CantatePresenter_Backup_${stamp}.cantatebackup`;
}

/** JSON w układzie zbliżonym do JSONEncoder (.prettyPrinted). @param {unknown} value */
const pretty = (value) => JSON.stringify(value, null, 2);

/**
 * @param {BackupContent} content
 * @param {string} [comment]
 * @returns {Promise<Blob>}
 */
export async function createBackup(content, comment) {
  const included = ["songs.json", "plans.json", "settings.json"];
  /** @type {{path: string, data: Uint8Array | string}[]} */
  const files = [
    { path: "songs.json", data: pretty(content.songs) },
    { path: "plans.json", data: pretty(content.plans) },
    { path: "settings.json", data: pretty(content.settings) },
  ];
  if (content.ccliUsage?.length) {
    files.push({ path: "ccli_usage.json", data: pretty(content.ccliUsage) });
    included.push("ccli_usage.json");
  }
  for (const [path, data] of content.extraFiles ?? []) {
    if (path === "ccli_usage.json") continue;
    files.push({ path, data });
    included.push(path);
  }
  const manifest = {
    version: APP_VERSION,
    appName: "CantatePresenter",
    createdAt: isoDate(),
    deviceName: "Web",
    songsCount: content.songs.length,
    plansCount: content.plans.length,
    activeLogoId: content.settings.activeLogoId,
    appLanguage: content.settings.appLanguage,
    includedFiles: included,
    schemaVersion: SCHEMA_VERSION,
    ...(comment ? { comment } : {}),
  };
  files.push({ path: "manifest.json", data: JSON.stringify(manifest, Object.keys(manifest).sort(), 2) });
  return createZip(files);
}

/** Błąd kopii z kodem do przetłumaczenia w interfejsie. */
export class BackupError extends Error {
  /** @param {"notArchive" | "noSongs" | "unreadable" | "newerSchema"} code @param {string} [detail] */
  constructor(code, detail = "") {
    super(detail || code);
    this.code = code;
  }
}

/** Pliki z macOS przenoszone bez zmian (logo, szablony, własne języki). */
const PRESERVED = /^(logos\/|templates\/)|^(custom_languages\.json|standby\.html)$/;

/**
 * Odczytuje kopię .cantatebackup lub .zip; katalog z danymi może być zagnieżdżony w archiwum.
 * @param {Blob} blob
 * @returns {Promise<BackupContent & {manifest: any}>}
 */
export async function readBackup(blob) {
  let files;
  try {
    files = await readZip(blob);
  } catch (error) {
    throw new BackupError("notArchive", String(error));
  }
  const songsPath = [...files.keys()].filter((p) => p === "songs.json" || p.endsWith("/songs.json")).sort((a, b) => a.length - b.length)[0];
  if (!songsPath) throw new BackupError("noSongs");
  const root = songsPath.slice(0, songsPath.length - "songs.json".length);
  const decoder = new TextDecoder();
  /** @param {string} name */
  const json = (name) => {
    const data = files.get(root + name);
    if (!data) return undefined;
    try {
      return JSON.parse(decoder.decode(data));
    } catch (error) {
      throw new BackupError("unreadable", `${name}: ${error}`);
    }
  };
  // Kopia z nowszej wersji aplikacji: pola, których ta wersja nie zna, zginęłyby przy zapisie.
  for (const name of ["manifest.json", "settings.json"]) {
    const version = json(name)?.schemaVersion;
    if (Number.isInteger(version) && version > SCHEMA_VERSION) throw new BackupError("newerSchema", String(version));
  }
  const songs = json("songs.json");
  if (!Array.isArray(songs)) throw new BackupError("unreadable", "songs.json");
  const plans = json("plans.json");
  const usage = json("ccli_usage.json");
  /** @type {Map<string, Uint8Array>} */
  const extraFiles = new Map();
  for (const [path, data] of files) {
    if (!path.startsWith(root)) continue;
    const relative = path.slice(root.length);
    if (PRESERVED.test(relative)) extraFiles.set(relative, data);
  }
  return {
    songs: songs.map(normalizeSong),
    plans: (Array.isArray(plans) ? plans : []).map(normalizePlan).filter((p) => p !== null),
    settings: normalizeSettings(json("settings.json")),
    ccliUsage: Array.isArray(usage) ? usage.map(normalizeUsageEntry) : [],
    manifest: json("manifest.json") ?? null,
    extraFiles,
  };
}
