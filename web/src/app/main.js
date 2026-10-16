// @ts-check
// Start wersji webowej: dane z IndexedDB, interfejs, klawiatura, okno projekcji, import i kopie zapasowe.

import * as api from "../api.js";
import { Store } from "./store.js";
import { AppUI } from "./ui.js";
import { SAMPLE_SONGS } from "./samples.js";
import { openChannel } from "./channel.js";
import { loadCatalog, setLanguage, t } from "../i18n.js";
import { normalizeSong, normalizePlan, normalizeSettings, createSong, SCHEMA_VERSION } from "../core/models.js";
import { keyboardAction, MAC_KEY_CODES } from "../core/keyboard.js";
import { decodeText, parseTextSong } from "../core/importText.js";
import { isSongSelectText, parseText, parseUSR, parseChordPro, CHORDPRO_EXTENSIONS } from "../core/songselect.js";
import { createBackup, readBackup, backupFileName, BackupError } from "../core/backup.js";
import { stageSource } from "../core/stage.js";

await loadCatalog(new URL("../../i18n/Localizable.xcstrings", import.meta.url)).catch((error) => console.error("Tłumaczenia:", error));

// MARK: - Dane (prywatny serwer)

/** @type {Awaited<ReturnType<typeof api.fetchData>>} */
let snapshot;
/** @type {{user: string}} */
let session;
try {
  [snapshot, session] = await Promise.all([api.fetchData(), api.fetchSession()]);
} catch (error) {
  if (error instanceof api.UnauthorizedError) api.goToLogin();
  throw error;
}

const saver = api.createSaver(snapshot.revisions, {
  onConflict: () => {
    if (confirm(t("Dane zmieniono na innym urządzeniu. Wczytać najnowszą wersję? Ostatnia zmiana na tym komputerze nie zostanie zapisana."))) location.reload();
  },
  onError: (kind) => ui?.toast(t("Nie udało się zapisać danych ({0}). Sprawdź połączenie z serwerem.", kind)),
});

const stored = snapshot.data;
const firstRun = !Array.isArray(stored.songs);
const settings = normalizeSettings(stored.settings);
setLanguage(settings.appLanguage);

const songs = firstRun
  ? SAMPLE_SONGS.map((sample) => Object.assign(createSong(sample), { copyright: sample.copyright }))
  : stored.songs.map(normalizeSong);
const plans = Array.isArray(stored.plans)
  ? stored.plans.map(normalizePlan).filter((p) => p !== null)
  : [Object.assign(normalizePlan({ name: t("Niedziela - Zestaw pieśni") }) ?? {}, { items: songs.slice(0, 4).map((s) => ({ id: crypto.randomUUID().toUpperCase(), songId: s.id, note: "" })) })];

/** Pliki z kopii macOS (logo, raport CCLI), przenoszone do następnej kopii bez zmian. @param {Record<string, string> | null | undefined} encoded */
const decodeExtra = (encoded) => new Map(Object.entries(encoded ?? {}).map(([path, base64]) => [path, Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))]));
/** @param {Map<string, Uint8Array>} files */
const encodeExtra = (files) => Object.fromEntries([...files].map(([path, bytes]) => [path, btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join(""))]));
let extraFiles = decodeExtra(stored.extraFiles);
let undoAvailable = snapshot.canUndoRestore;

const store = new Store({
  songs, plans: /** @type {any} */ (plans), settings,
  persist: (kind, value) => saver.schedule(kind, value),
  translate: t,
});
if (firstRun) { store.saveSongs(); store.savePlans(); store.saveSettings(); }
if (snapshot.newerSchema) {
  setTimeout(() => alert(t("Bibliotekę zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Pieśni i plany można wyświetlać, ale zmiany nie będą zapisywane, żeby nie uszkodzić danych. Zaktualizuj aplikację.", snapshot.newerSchema, SCHEMA_VERSION)), 0);
} else if (snapshot.locked.length) {
  setTimeout(() => alert(t("Na serwerze są nieczytelne pliki danych ({0}). Zapis do nich jest zablokowany; kopia uszkodzonego pliku jest w katalogu danych.", snapshot.locked.join(", "))), 0);
}

// MARK: - Okno projekcji

const channel = openChannel();
/** @type {Window | null} */
let projector = null;
let targetSize = { width: 1920, height: 1080 };

function broadcast() {
  if (!ui) return;
  channel.postMessage({ type: "state", state: ui.screenState() });
  publishStage();
}

// MARK: - Ekran dla muzyków

let lastStage = "";
/** @type {ReturnType<typeof setTimeout> | undefined} */
let stageTimer;
/** Stan dla muzyków: od razu do okien na tym komputerze, z krótkim opóźnieniem na serwer (tablety). */
function publishStage(force = false) {
  const source = stageSource(store);
  const signature = JSON.stringify({ ...source, updatedAt: 0 });
  if (!force && signature === lastStage) return;
  lastStage = signature;
  channel.postMessage({ type: "stage", source });
  clearTimeout(stageTimer);
  stageTimer = setTimeout(() => {
    api.request("/api/live", { method: "POST", body: JSON.stringify(source) }).catch(() => { /* tablety odświeżą się przy następnej zmianie */ });
  }, 150);
}

function openMusicians() {
  window.open(new URL("../../musicians.html", import.meta.url), "cantate-musicians", "popup,width=1100,height=760");
}

channel.onmessage = (event) => {
  const message = event.data;
  if (message?.type === "hello") broadcast();
  else if (message?.type === "stage-hello") publishStage(true);
  else if (message?.type === "size" && message.width > 100 && message.height > 100) {
    targetSize = { width: message.width, height: message.height };
    ui.renderRight();
  } else if (message?.type === "action") perform(message.action, "presentation");
};

async function openProjector() {
  let features = "popup,width=1280,height=720";
  // Window Management API (Chrome): okno od razu na drugim ekranie, jeśli jest.
  try {
    if ("getScreenDetails" in window) {
      const details = await /** @type {any} */ (window).getScreenDetails();
      const other = details.screens.find((/** @type {any} */ s) => s !== details.currentScreen);
      if (other) features = `popup,left=${other.availLeft},top=${other.availTop},width=${other.availWidth},height=${other.availHeight}`;
    }
  } catch {
    // Brak zgody albo jednego ekranu: zwykłe okno.
  }
  projector = window.open(new URL("../../projector.html", import.meta.url), "cantate-projector", features);
  if (!projector) ui.toast(t("Przeglądarka zablokowała okno projekcji. Zezwól na wyskakujące okna dla tej strony."));
  const watch = setInterval(() => {
    if (!projector || projector.closed) { clearInterval(watch); projector = null; ui.renderRight(); }
  }, 1000);
  ui.renderRight();
}

// MARK: - Import i kopie

/** @param {Blob} blob @param {string} name */
function download(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = Object.assign(document.createElement("a"), { href: url, download: name });
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/** @param {FileList | File[]} files */
async function importFiles(files) {
  /** @type {import("../core/models.js").Song[]} */
  const imported = [];
  let skipped = 0;
  for (const file of Array.from(files)) {
    const extension = file.name.split(".").pop()?.toLowerCase() ?? "";
    const baseName = file.name.replace(/\.[^.]+$/, "");
    const text = decodeText(new Uint8Array(await file.arrayBuffer()));
    try {
      if (extension === "json") {
        const data = JSON.parse(text);
        const list = Array.isArray(data) ? data : Array.isArray(data?.songs) ? data.songs : [data];
        imported.push(...list.filter((x) => x && typeof x === "object" && typeof x.title === "string").map(normalizeSong));
      } else if (extension === "usr") {
        const song = parseUSR(text);
        if (song) imported.push(Object.assign(createSong(song), song)); else skipped++;
      } else if (CHORDPRO_EXTENSIONS.has(extension)) {
        const song = parseChordPro(text, baseName);
        imported.push(Object.assign(createSong(song), song));
      } else if (isSongSelectText(text)) {
        const song = parseText(text);
        if (song) imported.push(Object.assign(createSong(song), song)); else skipped++;
      } else {
        imported.push(createSong(parseTextSong(text, baseName)));
      }
    } catch (error) {
      console.error(file.name, error);
      skipped++;
    }
  }
  if (imported.length) store.addSongs(imported);
  ui.toast(skipped ? t("Zaimportowano {0} pieśni, pominięto {1} plików.", imported.length, skipped) : t("Zaimportowano {0} pieśni.", imported.length));
}

async function exportBackup() {
  await saver.flushAll();
  const blob = await createBackup({ songs: store.songs, plans: store.plans, settings: store.settings, extraFiles });
  download(blob, backupFileName());
}

/** @param {File} file */
async function restoreBackup(file) {
  try {
    const backup = await readBackup(file);
    if (!confirm(t("Przywrócić kopię? Obecna biblioteka ({0} pieśni) zostanie zastąpiona przez {1} pieśni z kopii. Poprzedni stan można przywrócić przyciskiem „Cofnij ostatnie przywrócenie”.", store.songs.length, backup.songs.length))) return;
    await saver.flushAll();
    const files = backup.extraFiles ?? new Map();
    const result = await api.restoreOnServer({ songs: backup.songs, plans: backup.plans, settings: backup.settings, extraFiles: encodeExtra(files) });
    Object.assign(snapshot.revisions, result.revisions);
    extraFiles = files;
    undoAvailable = true;
    store.replaceAll(backup, { persist: false });
    setLanguage(store.settings.appLanguage);
    ui.renderAll();
    ui.toast(t("Przywrócono kopię: {0} pieśni, {1} planów.", backup.songs.length, backup.plans.length));
  } catch (error) {
    if (error instanceof api.UnauthorizedError) return api.goToLogin();
    const messages = { notArchive: "To nie jest plik kopii zapasowej (.cantatebackup lub .zip).", noSongs: "Kopia zapasowa nie zawiera pliku songs.json.", unreadable: "Kopia zapasowa jest uszkodzona: {0}",
      newerSchema: "Kopię zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Zaktualizuj aplikację przed przywróceniem." };
    const code = error instanceof BackupError ? error.code : "unreadable";
    ui.toast(t(messages[code], error instanceof Error ? error.message : String(error), SCHEMA_VERSION));
  }
}

async function undoRestore() {
  await saver.flushAll();
  if (await api.undoRestoreOnServer()) location.reload();
}

/** @param {import("../core/models.js").Song} song */
function exportSongText(song) {
  const header = [`Tytuł: ${song.title}`, song.author ? `Autor: ${song.author}` : "", song.key ? `Tonacja: ${song.key}` : "", song.tags.length ? `Tagi: ${song.tags.join(", ")}` : ""].filter(Boolean);
  download(new Blob([`${header.join("\n")}\n\n${song.rawLyrics}\n`], { type: "text/plain;charset=utf-8" }), `${song.title.replace(/[\\/:*?"<>|]/g, "_") || "piesn"}.txt`);
}

// MARK: - Interfejs

/** @type {AppUI} */
var ui = new AppUI(store, {
  openProjector,
  closeProjector: () => { projector?.close(); projector = null; ui.renderRight(); },
  isProjectorOpen: () => Boolean(projector && !projector.closed),
  targetSize: () => targetSize,
  importFiles, exportBackup, restoreBackup, undoRestore, exportSongText, openMusicians,
  canUndoRestore: () => undoAvailable,
  user: session.user,
  logout: async () => { await saver.flushAll(); api.logout(); },
});
ui.mount(/** @type {HTMLElement} */ (document.getElementById("app")));
store.subscribe((reason) => {
  if (["live", "settings", "songs", "all"].includes(reason)) broadcast();
  else if (reason === "plans") publishStage();
  if (reason === "settings") setLanguage(store.settings.appLanguage);
});
broadcast();

// MARK: - Klawiatura

/**
 * @param {import("../core/keyboard.js").KeyboardAction} action
 * @param {"main" | "presentation"} source
 */
function perform(action, source) {
  switch (action.type) {
    case "nextSlide": store.nextSlide(); break;
    case "prevSlide": store.prevSlide(); break;
    case "nextSong": store.nextSongInPlan(); break;
    case "prevSong": store.prevSongInPlan(); break;
    case "blackScreen": store.toggleBlackScreen(); break;
    case "clearText": store.toggleClearText(); break;
    case "chorus": store.jumpToChorus(); break;
    case "verse": store.jumpToVerse(action.number ?? 1); break;
    case "quickText": ui.openQuickText(); break;
    case "zoomIn": store.updateSettings({ uiScale: store.settings.uiScale + 0.05 }); break;
    case "zoomOut": store.updateSettings({ uiScale: store.settings.uiScale - 0.05 }); break;
    case "zoomReset": store.updateSettings({ uiScale: 1 }); break;
    case "endTextEditing": /** @type {HTMLElement} */ (document.activeElement)?.blur(); break;
    case "startPresentation": if (store.selectedSong) store.present(store.selectedSong); break;
    case "stopPresentation": store.stopLive(); if (source === "presentation") projector?.focus(); break;
  }
}

/** Fokus jak w macOS: pole jednowierszowe, wielowierszowe, lista albo inne. @returns {import("../core/keyboard.js").Focus} */
function focusKind() {
  const element = document.activeElement;
  if (element instanceof HTMLTextAreaElement) return "multilineText";
  if (element instanceof HTMLInputElement && ["text", "search", "number", ""].includes(element.type)) return "text";
  if (element instanceof HTMLSelectElement) return "multilineText";
  if (element?.getAttribute("role") === "listbox") return "list";
  return "other";
}

document.addEventListener("keydown", (event) => {
  // Otwarte okno dialogowe działa jak arkusz w macOS: skróty prezentacji są wyłączone.
  if (document.querySelector("dialog[open]")) return;
  const focus = focusKind();
  if (focus === "list" && (event.code === "ArrowUp" || event.code === "ArrowDown")) {
    event.preventDefault();
    ui.moveSelection(event.code === "ArrowUp" ? -1 : 1);
    return;
  }
  if ((event.metaKey || event.ctrlKey) && event.code === "KeyF") {
    event.preventDefault();
    ui.leftTab = "library";
    ui.renderLeft();
    ui.searchInput?.focus();
    return;
  }
  const action = keyboardAction({
    macCode: MAC_KEY_CODES[/** @type {keyof typeof MAC_KEY_CODES} */ (event.code)],
    characters: event.key.length === 1 ? event.key.toLowerCase() : "",
    command: event.metaKey || event.ctrlKey,
    shortcuts: store.settings.shortcuts,
    context: { kind: "main", focus },
  });
  if (!action) return;
  event.preventDefault();
  perform(action, "main");
});

addEventListener("beforeunload", (event) => {
  saver.flushAll();
  projector?.close();
  if (saver.hasPending()) event.preventDefault();
});
