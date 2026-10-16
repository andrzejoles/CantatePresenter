// @ts-check
// Ekran dla muzyków: odpowiednik MusicianStage z wersji macOS.
// Okno główne wysyła „źródło” (bieżąca pieśń, slajd, następna pieśń z planu), a każdy ekran muzyków
// sam liczy z niego chwyty ze swoją transpozycją, jak tablety w macOS.

import { linesForSlide } from "./chordsheet.js";
import { transpose } from "./chords.js";

/**
 * @typedef {{type: string, label: string, number?: number | null, text: string}} StageSlide
 * @typedef {{id: string, title: string, author: string, key: string, chords: string | null, slides: StageSlide[]}} StageSong
 * @typedef {{updatedAt: number, language: string, isLive: boolean, isBlackScreen: boolean, isClearText: boolean,
 *   song: StageSong | null, slideIndex: number, upcoming: StageSong | null}} StageSource
 * @typedef {{label: string, lines: import("./chordsheet.js").ChordLine[], borrowedFrom: string | null}} MusicianSlide
 * @typedef {{isLive: boolean, isBlackScreen: boolean, isClearText: boolean, songTitle: string, author: string,
 *   key: string, semitones: number, position: string, current: MusicianSlide | null, next: MusicianSlide | null,
 *   nextSongTitle: string | null, hasChords: boolean}} MusicianStage
 */

/** @param {any} song @returns {StageSong} */
const stageSong = (song) => ({
  id: song.id, title: song.title, author: song.author ?? "", key: song.key ?? "", chords: song.chords ?? null,
  slides: song.slides.map((/** @type {any} */ s) => ({ type: s.type, label: s.label, number: s.number ?? null, text: s.text })),
});

/**
 * Źródło z okna głównego. Następna pieśń: jak DataStore.upcomingSongInPlan (tylko jej pierwszy slajd).
 * @param {import("../app/store.js").Store} store @returns {StageSource}
 */
export function stageSource(store) {
  const song = store.isLive ? store.activeSong : null;
  const plan = store.activePlan;
  let upcoming = null;
  if (plan && plan.items.length) {
    const current = store.currentPlanIndex(plan);
    const nextIndex = current === null ? 0 : current + 1;
    const next = nextIndex < plan.items.length ? store.song(plan.items[nextIndex].songId) : null;
    if (next) upcoming = { ...stageSong(next), slides: stageSong(next).slides.slice(0, 1) };
  }
  return {
    updatedAt: Date.now(), language: store.settings.appLanguage,
    isLive: store.isLive, isBlackScreen: store.isBlackScreen, isClearText: store.isClearText,
    song: song ? stageSong(song) : null, slideIndex: store.activeSlideIndex, upcoming,
  };
}

/**
 * Stan ekranu muzyków z transpozycją `semitones` (np. +2 albo −3 pod capo).
 * @param {StageSource} source @param {number} semitones @param {(slide: StageSlide) => string} label
 * @returns {MusicianStage}
 */
export function makeStage(source, semitones, label) {
  const song = source.isLive ? source.song : null;
  const shift = semitones % 12;
  /** @param {StageSlide} slide @param {StageSong} owner @returns {MusicianSlide} */
  const slide = (slide, owner) => {
    const result = linesForSlide(slide, owner.chords, shift);
    return { label: label(slide), lines: result.lines, borrowedFrom: result.borrowedFrom };
  };
  let current = null, next = null, position = "";
  const index = source.slideIndex;
  if (song && index >= 0 && index < song.slides.length) {
    current = slide(song.slides[index], song);
    position = `${index + 1}/${song.slides.length}`;
    if (index + 1 < song.slides.length) next = slide(song.slides[index + 1], song);
  }
  const upcoming = source.upcoming;
  if (!next && upcoming && upcoming.slides[0] && upcoming.id !== song?.id) next = slide(upcoming.slides[0], upcoming);
  const atEnd = !song || !next || index + 1 >= song.slides.length;
  return {
    isLive: source.isLive, isBlackScreen: source.isBlackScreen, isClearText: source.isClearText,
    songTitle: song?.title ?? "", author: song?.author ?? "",
    key: song?.key ? transpose(song.key, shift) : "",
    semitones: shift, position, current, next,
    nextSongTitle: atEnd ? upcoming?.title ?? null : null,
    hasChords: Boolean(song?.chords?.trim()),
  };
}
