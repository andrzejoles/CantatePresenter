// @ts-check
// Pilot ze smartfona po stronie karty operatora (jak RemoteControlBridge w macOS): stan dla telefonu i wykonanie
// poleceń. Telefon (zalogowany tym samym kontem) otwiera /remote; serwer przekazuje polecenia tej karcie przez
// długie odpytywanie /api/remote/commands, a karta publikuje stan w /api/remote/state.
import { t } from "../i18n.js";
import { slideLabel } from "./labels.js";
import { request, UnauthorizedError } from "../api.js";

/** @typedef {import("./store.js").Store} Store */

/** Teksty strony telefonu w języku interfejsu (te same klucze co w macOS i Windows). */
export function remoteLabels() {
  return {
    next: t("Dalej"), previous: t("Wstecz"), nextSong: t("Następna pieśń"), previousSong: t("Poprzednia pieśń"),
    black: t("Czarny ekran"), clearText: t("Ukryj tekst"), stop: t("Zakończ projekcję"), slides: t("Slajdy"), plan: t("Plan"),
    notLive: t("Projekcja nie jest uruchomiona. Wybierz pieśń z planu lub wyszukaj ją."), start: t("Rozpocznij projekcję"),
    resume: t("Wznów projekcję"), search: t("Szukaj pieśni"), searchPlaceholder: t("Tytuł, autor lub fragment tekstu"),
    noResults: t("Nie znaleziono pieśni"), offline: t("Brak połączenia z aplikacją. Sprawdź, czy pilot jest włączony na komputerze prowadzącym projekcję."),
    title: t("Pilot CantatePresenter"),
  };
}

const firstLine = (/** @type {string} */ text) => text.split("\n")[0] ?? "";

/** Stan dla telefonu (pola jak RemoteState w macOS). @param {Store} store */
export function remoteState(store) {
  const song = store.activeSong;
  const plan = store.activePlan;
  const candidate = store.startCandidate;
  return {
    isLive: store.isLive,
    isBlackScreen: store.isBlackScreen,
    isClearText: store.isClearText,
    songTitle: song?.title ?? "",
    slideIndex: store.activeSlideIndex,
    slideText: store.currentLiveSlide?.text ?? "",
    slides: (song?.slides ?? []).map((slide) => ({ label: slideLabel(slide), preview: firstLine(slide.text) })),
    planName: plan?.name ?? "",
    plan: (plan?.items ?? []).map((item) => ({ title: store.song(item.songId)?.title ?? "?", isCurrent: item.songId === song?.id })),
    labels: remoteLabels(),
    canStart: !store.isLive && candidate !== null,
    startTitle: store.isLive ? "" : candidate?.title ?? "",
  };
}

/**
 * Polecenie z telefonu (jak RemoteControlBridge.perform w macOS).
 * @param {{command: string, index?: number, id?: string}} command @param {Store} store
 */
export function performRemote(command, store) {
  switch (command.command) {
    case "next": store.nextSlide(); break;
    case "previous": store.prevSlide(); break;
    case "nextSong": store.nextSongInPlan(); break;
    case "previousSong": store.prevSongInPlan(); break;
    case "black": store.toggleBlackScreen(); break;
    case "clearText": store.toggleClearText(); break;
    case "stop": store.stopLive(); break;
    case "start": store.startOrResume(); break;
    case "slide": {
      const index = command.index ?? -1;
      if (!store.isLive && store.activeSong && index < store.activeSong.slides.length) store.present(store.activeSong, index);
      else store.jumpToSlide(index);
      break;
    }
    case "song": {
      const song = store.songs.find((s) => s.id.toLowerCase() === String(command.id).toLowerCase());
      if (song) { store.present(song); store.selectSong(song.id); }
      break;
    }
    case "planItem": {
      const item = store.activePlan?.items[command.index ?? -1];
      const song = item ? store.song(item.songId) : null;
      if (song) { store.present(song); store.selectSong(song.id); }
      break;
    }
  }
}

/** Włączanie pilota w tej karcie; pamiętane w przeglądarce (localStorage), żeby przeładowanie go nie wyłączało. */
export class RemoteController {
  /** @param {Store} store @param {() => void} onStatus */
  constructor(store, onStatus) {
    this.store = store;
    this.onStatus = onStatus;
    this.enabled = false;
    this.phones = 0;
    this.handled = 0;
    /** @type {string | null} */ this.error = null;
    this.lastState = "";
    /** @type {(() => void) | null} */ this.unsubscribe = null;
    /** @type {ReturnType<typeof setInterval> | undefined} */ this.heartbeat = undefined;
    this.loopSerial = 0;
  }

  static remembered() {
    try { return localStorage.getItem("cantate.remote") === "on"; } catch { return false; }
  }

  /** @param {boolean} on */
  setEnabled(on) {
    if (on === this.enabled) return;
    this.enabled = on;
    try { localStorage.setItem("cantate.remote", on ? "on" : "off"); } catch { /* tylko wygoda */ }
    if (on) {
      this.lastState = "";
      this.publish();
      this.unsubscribe = this.store.subscribe(() => this.publish());
      // Co kilka sekund: serwer wie, że karta żyje, nawet gdy nic się nie zmienia.
      this.heartbeat = setInterval(() => this.publish(true), 10_000);
      this.loop(++this.loopSerial);
    } else {
      this.loopSerial++;
      this.unsubscribe?.();
      this.unsubscribe = null;
      clearInterval(this.heartbeat);
      this.phones = 0;
      request("/api/remote/stop", { method: "POST", body: "{}" }).catch(() => {});
    }
    this.onStatus();
  }

  publish(force = false) {
    if (!this.enabled) return;
    const snapshot = remoteState(this.store);
    const state = JSON.stringify(snapshot);
    if (!force && state === this.lastState) return;
    this.lastState = state;
    // „handled”: numer ostatniego wykonanego polecenia; serwer oddaje telefonowi stan dopiero po jego poleceniu.
    request("/api/remote/state", { method: "POST", body: JSON.stringify({ ...snapshot, handled: this.handled }) })
      .then((response) => response.ok ? response.json() : null)
      .then((result) => { if (result && result.phones !== this.phones) { this.phones = result.phones; this.onStatus(); } })
      .catch(() => {});
  }

  /** Długie odpytywanie o polecenia; po błędzie krótka przerwa. @param {number} serial */
  async loop(serial) {
    while (this.enabled && serial === this.loopSerial) {
      try {
        const response = await request("/api/remote/commands?wait=25");
        if (!response.ok) throw new Error(String(response.status));
        const { commands, handled, phones } = await response.json();
        if (serial !== this.loopSerial) return;
        for (const command of commands) performRemote(command, this.store);
        const answered = Number.isInteger(handled) && handled !== this.handled;
        if (answered) this.handled = handled;
        this.publish(commands.length > 0 || answered);
        const error = this.error;
        this.error = null;
        if (phones !== this.phones || error) { this.phones = phones; this.onStatus(); }
      } catch (error) {
        if (error instanceof UnauthorizedError) { this.setEnabled(false); return; }
        this.error = t("Brak połączenia z serwerem.");
        this.onStatus();
        await new Promise((resolve) => setTimeout(resolve, 3000));
      }
    }
  }
}
