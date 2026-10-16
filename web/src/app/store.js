// @ts-check
// Stan aplikacji: odpowiednik DataStore z macOS (biblioteka, plany, ustawienia, projekcja na żywo).
// Bez DOM; zapis przez wstrzyknięte `persist`, powiadomienia przez subscribe().

import { normalizeSettings, createSong, createPlan, isoDate, slidesFromLyrics, uuid, copyrightNotice } from "../core/models.js";
import { searchFold } from "../core/text.js";

/**
 * @typedef {import("../core/models.js").Song} Song
 * @typedef {import("../core/models.js").ServicePlan} ServicePlan
 * @typedef {ReturnType<typeof normalizeSettings>} Settings
 * @typedef {(kind: "songs" | "plans" | "settings", value: unknown) => void} Persist
 */

export class Store {
  /** @param {{songs?: Song[], plans?: ServicePlan[], settings?: Settings, persist?: Persist, translate?: (k: string, ...a: unknown[]) => string}} [initial] */
  constructor(initial = {}) {
    /** @type {Song[]} */
    this.songs = initial.songs ?? [];
    /** @type {ServicePlan[]} */
    this.plans = initial.plans ?? [];
    /** @type {Settings} */
    this.settings = initial.settings ?? normalizeSettings({});
    /** @type {string | null} */
    this.activePlanId = this.plans[0]?.id ?? null;
    /** @type {string | null} */
    this.selectedSongId = this.songs[0]?.id ?? null;
    /** @type {Song | null} */
    this.activeSong = null;
    this.activeSlideIndex = 0;
    this.isLive = false;
    this.isBlackScreen = false;
    this.isClearText = false;
    /** Pieśń z szybkiego tekstu: na ekranie, ale nie w bibliotece. @type {Song | null} */
    this.temporarySong = null;
    /** Ostatnia pieśń z planu; po szybkim tekście plan idzie dalej od niej (N11). @type {string | null} */
    this.lastPlanSongId = null;
    this.persist = initial.persist ?? (() => {});
    this.translate = initial.translate ?? ((/** @type {string} */ k) => k);
    /** @type {Set<(reason: string) => void>} */
    this.listeners = new Set();
  }

  /** @param {(reason: string) => void} listener */
  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** @param {string} reason */
  changed(reason) {
    this.listeners.forEach((listener) => listener(reason));
  }

  saveSongs() { this.persist("songs", this.songs); this.changed("songs"); }
  savePlans() { this.persist("plans", this.plans); this.changed("plans"); }
  saveSettings() { this.persist("settings", this.settings); this.changed("settings"); }

  // MARK: - Library

  get activePlan() { return this.plans.find((p) => p.id === this.activePlanId) ?? null; }
  get selectedSong() {
    return this.songs.find((s) => s.id === this.selectedSongId) ??
      (this.temporarySong?.id === this.selectedSongId ? this.temporarySong : null);
  }
  /** @param {string} id */
  song(id) { return this.songs.find((s) => s.id === id) ?? null; }

  /** @param {string | null} id */
  selectSong(id) { this.selectedSongId = id; this.changed("selection"); }

  /** @param {Parameters<typeof createSong>[0]} fields */
  addSong(fields) {
    const song = createSong(fields);
    this.songs.unshift(song);
    this.selectedSongId = song.id;
    this.saveSongs();
    return song;
  }

  /** Dodaje pieśni z importu; zajęte identyfikatory dostają nowe (W8). @param {Song[]} songs */
  addSongs(songs) {
    const used = new Set(this.songs.map((s) => s.id));
    for (const song of songs) {
      const copy = used.has(song.id) ? { ...song, id: uuid(), slides: song.slides.map((s) => ({ ...s, id: uuid() })) } : song;
      used.add(copy.id);
      this.songs.push(copy);
    }
    this.selectedSongId ??= songs[0]?.id ?? null;
    this.saveSongs();
  }

  /** @param {Song} song */
  updateSong(song) {
    const index = this.songs.findIndex((s) => s.id === song.id);
    if (index < 0) return;
    const updated = { ...song, slides: slidesFromLyrics(song.rawLyrics), updatedAt: isoDate() };
    this.songs[index] = updated;
    if (this.activeSong?.id === song.id) {
      this.activeSong = updated;
      this.activeSlideIndex = Math.min(this.activeSlideIndex, Math.max(0, updated.slides.length - 1));
    }
    this.saveSongs();
  }

  /** @param {string} id */
  deleteSong(id) {
    this.songs = this.songs.filter((s) => s.id !== id);
    if (this.selectedSongId === id) this.selectedSongId = this.songs[0]?.id ?? null;
    if (this.activeSong?.id === id) this.stopLive();
    for (const plan of this.plans) plan.items = plan.items.filter((i) => i.songId !== id);
    this.saveSongs();
    this.savePlans();
  }

  /**
   * Biblioteka po wyszukiwaniu, posortowana po tytule (polskie zasady sortowania).
   * @param {string} query @param {(song: Song) => boolean} matcher
   */
  filteredSongs(query, matcher) {
    const list = searchFold(query) ? this.songs.filter(matcher) : [...this.songs];
    return list.sort((a, b) => a.title.localeCompare(b.title, "pl", { sensitivity: "base" }));
  }

  // MARK: - Plans

  /** @param {string} name */
  createPlan(name) {
    const plan = createPlan(name);
    this.plans.push(plan);
    this.activePlanId = plan.id;
    this.savePlans();
    return plan;
  }

  /** @param {string} id */
  deletePlan(id) {
    this.plans = this.plans.filter((p) => p.id !== id);
    if (this.activePlanId === id) this.activePlanId = this.plans[0]?.id ?? null;
    this.savePlans();
  }

  /** @param {string} id @param {string} name */
  renamePlan(id, name) {
    const plan = this.plans.find((p) => p.id === id);
    if (!plan || !name.trim()) return;
    plan.name = name.trim();
    plan.updatedAt = isoDate();
    this.savePlans();
  }

  /** @param {string | null} id */
  setActivePlan(id) { this.activePlanId = id; this.changed("plans"); }

  /** @param {string} songId */
  addSongToPlan(songId) {
    const plan = this.activePlan;
    if (!plan) return;
    plan.items.push({ id: uuid(), songId, note: "" });
    plan.updatedAt = isoDate();
    this.savePlans();
  }

  /** @param {string} itemId */
  removePlanItem(itemId) {
    const plan = this.activePlan;
    if (!plan) return;
    plan.items = plan.items.filter((i) => i.id !== itemId);
    plan.updatedAt = isoDate();
    this.savePlans();
  }

  /** @param {number} from @param {number} to */
  movePlanItem(from, to) {
    const plan = this.activePlan;
    if (!plan || from === to || from < 0 || from >= plan.items.length) return;
    const [item] = plan.items.splice(from, 1);
    plan.items.splice(Math.max(0, Math.min(to, plan.items.length)), 0, item);
    plan.updatedAt = isoDate();
    this.savePlans();
  }

  // MARK: - Presentation

  get currentLiveSlide() {
    const song = this.activeSong;
    if (!song || this.activeSlideIndex < 0 || this.activeSlideIndex >= song.slides.length) return null;
    return song.slides[this.activeSlideIndex];
  }

  get currentCopyrightNotice() {
    return this.activeSong ? copyrightNotice(this.activeSong, this.activeSlideIndex, this.settings, this.translate) : null;
  }

  /** @param {Song} song @param {number} [slideIndex] */
  present(song, slideIndex = 0) {
    if (this.activePlan?.items.some((i) => i.songId === song.id)) this.lastPlanSongId = song.id;
    this.activeSong = song;
    this.activeSlideIndex = Math.min(Math.max(0, slideIndex), Math.max(0, song.slides.length - 1));
    this.isLive = true;
    this.isBlackScreen = false;
    this.isClearText = false;
    this.changed("live");
  }

  /** Tekst na ekran bez zapisywania w bibliotece. @param {string} text @param {string} [title] */
  presentQuickText(text, title) {
    const trimmed = text.trim();
    if (!trimmed) return;
    const name = (title ?? "").trim() || this.translate("Szybki tekst");
    const song = createSong({ title: name, author: "Tymczasowy", tags: [this.translate("Szybki tekst")], rawLyrics: trimmed });
    this.temporarySong = song;
    this.selectedSongId = song.id;
    this.present(song);
  }

  nextSlide() {
    const song = this.activeSong;
    if (!song) return;
    if (this.activeSlideIndex < song.slides.length - 1) {
      this.activeSlideIndex++;
      this.isClearText = false;
      this.isBlackScreen = false;
      this.changed("live");
    } else {
      this.nextSongInPlan();
    }
  }

  prevSlide() {
    if (!this.activeSong || this.activeSlideIndex === 0) return;
    this.activeSlideIndex--;
    this.isClearText = false;
    this.isBlackScreen = false;
    this.changed("live");
  }

  /** @param {number} index */
  jumpToSlide(index) {
    const song = this.activeSong;
    if (!song || index < 0 || index >= song.slides.length) return;
    this.activeSlideIndex = index;
    this.isClearText = false;
    this.isBlackScreen = false;
    this.changed("live");
  }

  /** Po numerze zwrotki, nie po etykiecie (S10). @param {number} number */
  jumpToVerse(number) {
    const song = this.activeSong;
    if (!song) return;
    const index = song.slides.findIndex((s) => s.type === "verse" && s.number === number);
    if (index >= 0) this.jumpToSlide(index);
    else if (number - 1 < song.slides.length) this.jumpToSlide(number - 1);
  }

  jumpToChorus() {
    const index = this.activeSong?.slides.findIndex((s) => s.type === "chorus") ?? -1;
    if (index >= 0) this.jumpToSlide(index);
  }

  toggleBlackScreen() { this.isBlackScreen = !this.isBlackScreen; this.changed("live"); }
  toggleClearText() { this.isClearText = !this.isClearText; this.changed("live"); }

  stopLive() {
    this.isLive = false;
    this.isBlackScreen = false;
    this.isClearText = false;
    this.changed("live");
  }

  /** Pozycja w planie: bieżąca pieśń albo (po szybkim tekście) ostatnia pieśń z planu. @param {ServicePlan} plan */
  currentPlanIndex(plan) {
    const song = this.activeSong;
    const anchor = song && plan.items.some((i) => i.songId === song.id) ? song.id : this.lastPlanSongId;
    const index = anchor ? plan.items.findIndex((i) => i.songId === anchor) : -1;
    return index >= 0 ? index : null;
  }

  nextSongInPlan() {
    const plan = this.activePlan;
    if (!plan || !plan.items.length) return;
    const current = this.currentPlanIndex(plan);
    const nextIndex = current === null ? 0 : current + 1;
    const next = plan.items[nextIndex] && this.song(plan.items[nextIndex].songId);
    if (next) {
      this.present(next);
      this.selectedSongId = next.id;
    }
  }

  prevSongInPlan() {
    const plan = this.activePlan;
    if (!plan || !plan.items.length) return;
    const current = this.currentPlanIndex(plan);
    if (current === null || current === 0) return;
    const previous = this.song(plan.items[current - 1].songId);
    if (previous) {
      this.present(previous);
      this.selectedSongId = previous.id;
    }
  }

  /** Następny slajd do podglądu: kolejny w pieśni albo pierwszy następnej pieśni z planu. */
  get nextSlidePreview() {
    const song = this.activeSong;
    if (!song) return null;
    if (this.activeSlideIndex + 1 < song.slides.length) return song.slides[this.activeSlideIndex + 1];
    const plan = this.activePlan;
    const current = plan ? this.currentPlanIndex(plan) : null;
    const nextId = plan && current !== null ? plan.items[current + 1]?.songId : null;
    return nextId ? this.song(nextId)?.slides[0] ?? null : null;
  }

  // MARK: - Settings

  /** @param {Partial<Settings>} changes */
  updateSettings(changes) {
    this.settings = normalizeSettings({ ...this.settings, ...changes });
    this.saveSettings();
  }

  /**
   * Podmienia wszystkie dane (przywrócenie kopii). Bez `persist`, gdy serwer zapisał je już sam.
   * @param {{songs: Song[], plans: ServicePlan[], settings: Settings}} data @param {{persist?: boolean}} [options]
   */
  replaceAll(data, options = {}) {
    this.stopLive();
    this.songs = data.songs;
    this.plans = data.plans;
    this.settings = data.settings;
    this.activePlanId = this.plans[0]?.id ?? null;
    this.selectedSongId = this.songs[0]?.id ?? null;
    this.activeSong = null;
    this.temporarySong = null;
    if (options.persist !== false) {
      this.persist("songs", this.songs);
      this.persist("plans", this.plans);
      this.persist("settings", this.settings);
    }
    this.changed("all");
  }
}
