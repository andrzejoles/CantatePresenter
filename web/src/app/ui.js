// @ts-check
// Interfejs operatora: układ jak w macOS (górny pasek, biblioteka/plan, slajdy pieśni, ekran na żywo, skróty).

import { h, replace } from "./dom.js";
import { t, LANGUAGES } from "../i18n.js";
import { songMatches, matchingSnippet, SearchScope } from "../core/text.js";
import { shortBadge } from "../core/lyrics.js";
import { transpose } from "../core/chords.js";
import { keyName } from "../core/keyboard.js";
import { renderScreen } from "./slide.js";
import { slideLabel } from "./labels.js";
import { APP_VERSION } from "../version.js";

/**
 * @typedef {import("./store.js").Store} Store
 * @typedef {import("../core/models.js").Song} Song
 * @typedef {{
 *   openProjector: () => void, closeProjector: () => void, isProjectorOpen: () => boolean,
 *   targetSize: () => {width: number, height: number},
 *   importFiles: (files: FileList | File[]) => Promise<void>, exportBackup: () => Promise<void>,
 *   restoreBackup: (file: File) => Promise<void>, undoRestore: () => Promise<void>, canUndoRestore: () => boolean,
 *   exportSongText: (song: Song) => void, user: string, logout: () => void, openMusicians: () => void,
 *   exportCCLIReport: () => void,
 * }} Actions
 */

export { slideLabel };

/** Nazwa pieśni do listy; pusta → „Bez tytułu”. @param {Song} song */
const titleOf = (song) => song.title || t("Bez tytułu");

export class AppUI {
  /** @param {Store} store @param {Actions} actions */
  constructor(store, actions) {
    this.store = store;
    this.actions = actions;
    this.query = "";
    this.scope = SearchScope.all;
    this.leftTab = "library";
    this.showChords = false;
    this.transposeSteps = 0;
    /** @type {HTMLInputElement | null} */
    this.searchInput = null;
    /** @type {HTMLElement | null} */
    this.listElement = null;
    this.toolbar = h("header", { class: "toolbar" });
    this.left = h("section", { class: "panel" });
    this.middle = h("section", { class: "panel" });
    this.right = h("section", { class: "panel" });
    this.shortcutsBar = h("footer", { class: "shortcuts" });
  }

  /** @param {HTMLElement} root */
  mount(root) {
    replace(root, this.toolbar, h("main", null, this.left, this.middle, this.right), this.shortcutsBar);
    this.renderAll();
    this.store.subscribe((reason) => {
      if (reason === "live") {
        this.renderMiddle();
        this.renderRight();
        if (this.leftTab === "plan") this.renderLeft();
      } else if (reason === "selection") {
        this.renderList();
        this.renderMiddle();
      } else if (reason === "settings") {
        this.applyScale();
        this.renderAll();
      } else {
        this.renderAll();
      }
    });
    addEventListener("resize", () => this.renderRight());
  }

  applyScale() {
    document.documentElement.style.setProperty("--ui-scale", String(this.store.settings.uiScale));
  }

  renderAll() {
    this.applyScale();
    this.renderToolbar();
    this.renderLeft();
    this.renderMiddle();
    this.renderRight();
    this.renderShortcuts();
  }

  // MARK: - Toolbar

  renderToolbar() {
    const { store } = this;
    const scale = Math.round(store.settings.uiScale * 100);
    const zoom = (/** @type {number} */ delta) => store.updateSettings({ uiScale: Math.round((store.settings.uiScale + delta) * 100) / 100 });
    replace(this.toolbar,
      h("div", { class: "brand" }, h("span", { class: "brand-mark" }, "♫"), "CantatePresenter"),
      h("button", { onclick: () => this.openQuickText(), title: t("Szybki tekst") }, "⚡ ", t("Szybki tekst")),
      h("button", { onclick: () => this.openEditor(null), title: t("Nowa pieśń") }, "＋ ", t("Nowa pieśń")),
      h("button", { onclick: () => store.selectedSong && this.openEditor(store.selectedSong), disabled: !store.selectedSong || store.selectedSong === store.temporarySong, title: t("Edytuj") }, "✎ ", t("Edytuj")),
      h("button", { onclick: () => this.openImportExport(), title: t("Import/Eksport") }, "⇅ ", t("Import/Eksport")),
      h("button", { onclick: () => this.actions.openMusicians(), title: t("Ekran dla muzyków: chwyty nad tekstem. Na tabletach otwórz {0} i zaloguj się.", `${location.origin}/musicians.html`) }, "🎸 ", t("Muzycy")),
      h("div", { class: "spacer" }),
      h("span", { class: "zoom" }, t("Rozmiar UI"),
        h("button", { onclick: () => zoom(-0.05), title: "−" }, "A−"), `${scale}%`, h("button", { onclick: () => zoom(0.05), title: "+" }, "A+")),
      h("span", { class: "user-chip", title: t("Zalogowany użytkownik") }, `👤 ${this.actions.user}`),
      h("button", { onclick: () => this.actions.logout(), title: t("Wyloguj") }, t("Wyloguj")),
      h("button", { onclick: () => this.openSettings(), title: t("Ustawienia") }, "⚙"),
      h("button", { onclick: () => this.openAbout(), title: t("O programie") }, "?"));
  }

  // MARK: - Left panel

  renderLeft() {
    const tabs = h("div", { class: "tabs", role: "tablist" },
      h("button", { class: this.leftTab === "library" ? "selected" : "", onclick: () => { this.leftTab = "library"; this.renderLeft(); } }, t("Biblioteka pieśni")),
      h("button", { class: this.leftTab === "plan" ? "selected" : "", onclick: () => { this.leftTab = "plan"; this.renderLeft(); } }, t("Plan nabożeństwa")));
    if (this.leftTab === "library") this.renderLibrary(tabs);
    else this.renderPlan(tabs);
  }

  /** @param {HTMLElement} tabs */
  renderLibrary(tabs) {
    const searchBox = h("label", { class: "search" }, "🔍");
    const input = /** @type {HTMLInputElement} */ (h("input", {
      type: "search", id: "search", value: this.query, placeholder: t("Szukaj w tytule, autorze i tekście..."), autocomplete: "off",
      oninput: () => { this.query = input.value; this.renderList(); },
      onfocus: () => { searchBox.classList.add("active"); input.select(); },
      onblur: () => searchBox.classList.remove("active"),
    }));
    searchBox.append(input);
    this.searchInput = input;
    const scope = h("select", { onchange: (/** @type {Event} */ e) => { this.scope = /** @type {HTMLSelectElement} */ (e.target).value; this.renderList(); } },
      [[SearchScope.all, "Wszędzie"], [SearchScope.titleAndAuthor, "Tytuł i autor"], [SearchScope.titleOnly, "Tylko tytuł"], [SearchScope.authorOnly, "Tylko autor"]]
        .map(([value, label]) => h("option", { value, selected: this.scope === value }, t(label))));
    this.listMeta = h("div", { class: "list-meta" });
    this.listElement = h("ul", { class: "song-list", role: "listbox", tabindex: "0", "aria-label": t("Biblioteka pieśni") });
    this.libraryFooter = h("div", { class: "footer-meta" });
    replace(this.left, tabs, searchBox, h("div", { class: "search-row" }, scope), this.listMeta, h("div", { class: "scroll" }, this.listElement), this.libraryFooter);
    this.renderList();
  }

  visibleSongs() {
    return this.store.filteredSongs(this.query, (song) => songMatches(song, this.query, this.scope));
  }

  renderList() {
    if (this.leftTab !== "library" || !this.listElement) return;
    const songs = this.visibleSongs();
    const { store } = this;
    replace(/** @type {HTMLElement} */ (this.listMeta), h("span", null, `${songs.length} / ${store.songs.length}`), h("span", null, t("Tytuł (A-Z)")));
    replace(/** @type {HTMLElement} */ (this.libraryFooter), h("span", null, `${store.songs.length} `, t("pieśni w bibliotece")), h("span", null, t("Podwójny klik: edycja")));
    if (!songs.length) {
      replace(this.listElement, h("li", { class: "empty" }, store.songs.length ? t("Nie znaleziono pieśni") : t("Biblioteka jest pusta. Dodaj pieśń albo zaimportuj pliki.")));
      return;
    }
    replace(this.listElement, songs.map((song) => {
      const snippet = this.query ? matchingSnippet(song, this.query) : null;
      return h("li", {
        class: `song-row${song.id === store.selectedSongId ? " selected" : ""}`, role: "option", dataset: { id: song.id },
        "aria-selected": song.id === store.selectedSongId ? "true" : "false",
        onclick: () => store.selectSong(song.id),
        ondblclick: () => this.openEditor(song),
      },
      h("span", { class: "song-title" }, titleOf(song)),
      h("span", { class: "song-side" }, song.key ? h("span", { class: "key-badge" }, song.key) : null, h("span", { class: "muted" }, t("{0} sl.", song.slides.length))),
      h("span", { class: "song-sub muted" }, song.author || t("Autor nieznany")),
      snippet ? h("span", { class: "snippet" }, `„${snippet}”`) : null);
    }));
    this.listElement.querySelector(".selected")?.scrollIntoView({ block: "nearest" });
  }

  /** Strzałki na liście zmieniają zaznaczenie (jak w macOS). @param {number} delta */
  moveSelection(delta) {
    const songs = this.visibleSongs();
    if (!songs.length) return;
    const index = songs.findIndex((s) => s.id === this.store.selectedSongId);
    const next = songs[Math.max(0, Math.min(songs.length - 1, index < 0 ? 0 : index + delta))];
    this.store.selectSong(next.id);
  }

  /** @param {HTMLElement} tabs */
  renderPlan(tabs) {
    const { store } = this;
    const plan = store.activePlan;
    const select = h("select", { onchange: (/** @type {Event} */ e) => store.setActivePlan(/** @type {HTMLSelectElement} */ (e.target).value) },
      store.plans.map((p) => h("option", { value: p.id, selected: p.id === store.activePlanId }, p.name)));
    const head = h("div", { class: "plan-head" }, select,
      h("button", { title: t("Nowy plan"), onclick: () => { const name = prompt(t("Nazwa planu"), t("Nowy plan")); if (name?.trim()) store.createPlan(name.trim()); } }, "＋"),
      h("button", { title: t("Zmień nazwę"), disabled: !plan, onclick: () => { const name = plan && prompt(t("Nazwa planu"), plan.name); if (plan && name) store.renamePlan(plan.id, name); } }, "✎"),
      h("button", { class: "danger", title: t("Usuń plan"), disabled: !plan, onclick: () => { if (plan && confirm(t("Usunąć plan „{0}”?", plan.name))) store.deletePlan(plan.id); } }, "🗑"));
    const current = plan ? store.currentPlanIndex(plan) : null;
    const items = !plan ? [h("div", { class: "empty" }, t("Utwórz plan przyciskiem +."))]
      : !plan.items.length ? [h("div", { class: "empty" }, t("Plan jest pusty. Wybierz pieśń w bibliotece i kliknij „Dodaj do planu”."))]
      : plan.items.map((item, index) => {
        const song = store.song(item.songId);
        return h("div", {
          class: `plan-item${store.isLive && current === index ? " current" : ""}`, draggable: "true",
          ondragstart: (/** @type {DragEvent} */ e) => e.dataTransfer?.setData("text/plain", String(index)),
          ondragover: (/** @type {DragEvent} */ e) => e.preventDefault(),
          ondrop: (/** @type {DragEvent} */ e) => { e.preventDefault(); store.movePlanItem(Number(e.dataTransfer?.getData("text/plain")), index); },
          onclick: () => song && store.selectSong(song.id),
          ondblclick: () => song && store.present(song),
        },
        h("span", { class: "num" }, `${index + 1}.`),
        h("span", { class: "song-title" }, song ? titleOf(song) : t("(usunięta pieśń)")),
        h("span", { class: "actions" },
          h("button", { title: t("Prezentuj"), disabled: !song, onclick: (/** @type {Event} */ e) => { e.stopPropagation(); if (song) store.present(song); } }, "▶"),
          h("button", { title: "↑", disabled: index === 0, onclick: (/** @type {Event} */ e) => { e.stopPropagation(); store.movePlanItem(index, index - 1); } }, "↑"),
          h("button", { title: "↓", disabled: index === plan.items.length - 1, onclick: (/** @type {Event} */ e) => { e.stopPropagation(); store.movePlanItem(index, index + 1); } }, "↓"),
          h("button", { class: "danger", title: t("Usuń z planu"), onclick: (/** @type {Event} */ e) => { e.stopPropagation(); store.removePlanItem(item.id); } }, "✕")));
      });
    replace(this.left, tabs, head, h("div", { class: "scroll" }, items),
      h("div", { class: "footer-meta" }, h("span", null, plan ? t("{0} pieśni w planie", plan.items.length) : ""), h("span", null, t("Przeciągnij, aby zmienić kolejność"))));
  }

  // MARK: - Middle panel

  renderMiddle() {
    const { store } = this;
    const song = store.selectedSong;
    if (!song) {
      replace(this.middle, h("div", { class: "placeholder" }, h("div", { class: "big" }, "♫"), t("Wybierz pieśń z biblioteki")));
      return;
    }
    const isActive = store.isLive && store.activeSong?.id === song.id;
    const isTemporary = song === store.temporarySong;
    const head = h("div", { class: "song-head" },
      h("div", null,
        h("h1", null, h("span", { class: "title" }, titleOf(song)), song.key ? h("span", { class: "key-badge" }, song.key) : null),
        h("div", { class: "muted" }, song.author || t("Autor nieznany"))),
      h("div", { class: "actions" },
        h("button", { class: "primary", title: t("Prezentuj"), onclick: () => store.present(song) }, "▶ ", t("Prezentuj")),
        h("button", { title: t("Dodaj do planu"), disabled: isTemporary || !store.activePlan, onclick: () => { store.addSongToPlan(song.id); this.toast(t("Dodano do planu „{0}”", store.activePlan?.name ?? "")); } }, "＋ ", t("Plan")),
        h("button", { class: this.showChords ? "on" : "", title: t("Chwyty"), onclick: () => { this.showChords = !this.showChords; this.transposeSteps = 0; this.renderMiddle(); } }, "🎸 ", t("Chwyty")),
        h("button", { title: t("Edytuj"), disabled: isTemporary, onclick: () => this.openEditor(song) }, "✎")),
      song.tags.length ? h("div", { class: "tags" }, song.tags.map((tag) => h("span", { class: "tag" }, tag))) : null,
      song.copyright || song.ccliNumber ? h("div", { class: "hint-text", style: { gridColumn: "1 / -1" } },
        [song.copyright, song.ccliNumber ? `CCLI ${song.ccliNumber}` : null].filter(Boolean).join(" · ")) : null);

    if (this.showChords) {
      const sheet = song.chords ? transpose(song.chords, this.transposeSteps) : "";
      replace(this.middle, head, h("div", { class: "scroll chords" },
        h("div", { class: "row", style: { alignItems: "center", marginBottom: "10px" } },
          h("button", { onclick: () => { this.transposeSteps--; this.renderMiddle(); } }, "−1"),
          h("span", null, t("Transpozycja: {0}", this.transposeSteps > 0 ? `+${this.transposeSteps}` : this.transposeSteps)),
          h("button", { onclick: () => { this.transposeSteps++; this.renderMiddle(); } }, "+1")),
        sheet ? h("pre", null, sheet) : h("div", { class: "empty" }, t("Ta pieśń nie ma chwytów. Dodaj je w edytorze."))));
      return;
    }

    let verse = 0;
    const cards = song.slides.map((slide, index) => {
      const hint = slide.type === "verse" ? `[${slide.number ?? ++verse}]` : slide.type === "chorus" ? "[R]" : "";
      return h("button", {
        class: `slide-card${isActive && store.activeSlideIndex === index ? " live" : ""}`,
        onclick: () => (store.activeSong?.id === song.id && store.isLive ? store.jumpToSlide(index) : store.present(song, index)),
      },
      h("header", null, h("span", { class: `badge ${slide.type}` }, shortBadge[/** @type {keyof typeof shortBadge} */ (slide.type)] ?? "•"), slideLabel(slide), h("span", { class: "hint" }, hint)),
      h("div", { class: "text" }, slide.text));
    });
    replace(this.middle, head, h("div", { class: "scroll" }, h("div", { class: "slides" }, cards)));
    this.middle.querySelector(".slide-card.live")?.scrollIntoView({ block: "nearest" });
  }

  // MARK: - Right panel

  screenState() {
    const { store } = this;
    return {
      isLive: store.isLive, isBlackScreen: store.isBlackScreen, isClearText: store.isClearText,
      text: store.currentLiveSlide?.text ?? "", notice: store.currentCopyrightNotice, settings: store.settings,
      standbyTitle: "CantatePresenter", standbySubtitle: t("Wersja {0}", APP_VERSION),
    };
  }

  renderRight() {
    const { store } = this;
    const target = this.actions.targetSize();
    const ratio = `${target.width} / ${target.height}`;
    const live = h("div", { class: `preview${store.isLive ? " live" : ""}`, style: { aspectRatio: ratio } });
    const nextSlide = store.isLive ? store.nextSlidePreview : null;
    const next = h("div", { class: "preview next", style: { aspectRatio: ratio } });
    const projectorOpen = this.actions.isProjectorOpen();
    replace(this.right,
      h("div", { class: "live-head" }, "🖥 ", t("Ekran na żywo"), h("span", { class: `pill${store.isLive ? " on" : ""}` }, store.isLive ? t("NA ŻYWO") : t("OFF AIR"))),
      live,
      h("div", { class: "controls" },
        h("button", { disabled: !store.isLive, onclick: () => store.prevSlide() }, "← ", t("Poprzedni")),
        h("button", { disabled: !store.isLive, onclick: () => store.nextSlide() }, t("Następny"), " →"),
        h("button", { class: store.isBlackScreen ? "on" : "", disabled: !store.isLive, onclick: () => store.toggleBlackScreen() }, t("Czarny (B)")),
        h("button", { class: store.isClearText ? "on" : "", disabled: !store.isLive, onclick: () => store.toggleClearText() }, t("Czysty (C)")),
        h("button", { class: "wide danger", disabled: !store.isLive, onclick: () => store.stopLive() }, "■ ", t("Zakończ projekcję")),
        h("button", { class: `wide${projectorOpen ? "" : " primary"}`, onclick: () => (projectorOpen ? this.actions.closeProjector() : this.actions.openProjector()) },
          projectorOpen ? t("Zamknij okno projekcji") : t("Otwórz okno projekcji"))),
      h("div", { class: "section-title" }, "⇥ ", t("Podgląd następnego slajdu"), h("span", { class: "pill" }, nextSlide ? slideLabel(nextSlide) : t("KONIEC"))),
      next);
    requestAnimationFrame(() => {
      renderScreen(live, this.screenState(), target);
      if (nextSlide) renderScreen(next, { ...this.screenState(), text: nextSlide.text, isBlackScreen: false, isClearText: false, notice: null }, target, { dimmed: true });
      else replace(next, h("div", { class: "placeholder" }, store.isLive ? t("Koniec planu") : t("Brak aktywnej prezentacji")));
    });
  }

  // MARK: - Shortcuts bar

  renderShortcuts() {
    const s = this.store.settings.shortcuts;
    /** @param {string} key @param {string} label */
    const item = (key, label) => h("div", { class: "shortcut" }, h("kbd", null, key), t(label));
    replace(this.shortcutsBar, h("span", { class: "label" }, t("SKRÓTY:")),
      item(keyName(s.prevSlideKey), "Poprzedni"), item(keyName(s.nextSlideKey), "Następny"), item("R", "Refren"), item("1–9", "Zwrotka"),
      item(keyName(s.blackScreenKey), "Czarny"), item(keyName(s.clearTextKey), "Czysty"), item(keyName(s.prevSongKey), "Poprz. pieśń"),
      item(keyName(s.nextSongKey), "Nast. pieśń"), item(keyName(s.startPresentationKey), "Prezentuj"), item("Ctrl/⌘ T", "Szybki tekst"));
  }

  // MARK: - Dialogs

  /**
   * @param {string} title @param {HTMLElement[]} body @param {HTMLElement[]} buttons
   * @returns {HTMLDialogElement}
   */
  dialog(title, body, buttons) {
    const dialog = /** @type {HTMLDialogElement} */ (h("dialog", null,
      h("div", { class: "dialog-head" }, title, h("span", { class: "spacer" }), h("button", { onclick: () => dialog.close(), title: t("Zamknij") }, "✕")),
      h("div", { class: "dialog-body" }, body),
      buttons.length ? h("div", { class: "dialog-foot" }, buttons) : null));
    dialog.addEventListener("close", () => dialog.remove());
    document.body.append(dialog);
    dialog.showModal();
    return dialog;
  }

  /** @param {string} message */
  toast(message) {
    const element = h("div", { class: "toast", role: "status" }, message);
    document.body.append(element);
    setTimeout(() => element.remove(), 3000);
  }

  openQuickText() {
    const title = /** @type {HTMLInputElement} */ (h("input", { type: "text", placeholder: t("Szybki tekst") }));
    const text = /** @type {HTMLTextAreaElement} */ (h("textarea", { rows: 8, placeholder: t("Wpisz tekst ogłoszenia lub modlitwy. Pusta linia oddziela slajdy.") }));
    const show = () => { this.store.presentQuickText(text.value, title.value); dialog.close(); };
    const dialog = this.dialog(t("Szybki tekst"), [
      h("label", { class: "field" }, h("span", null, t("Tytuł (opcjonalnie)")), title),
      h("label", { class: "field" }, h("span", null, t("Tekst")), text),
      h("div", { class: "hint-text" }, t("Tekst nie trafia do biblioteki."))],
    [h("button", { onclick: () => dialog.close() }, t("Anuluj")), h("button", { class: "primary", onclick: show }, t("Pokaż na ekranie"))]);
    text.focus();
  }

  /** @param {Song | null} song */
  openEditor(song) {
    const field = (/** @type {string} */ label, /** @type {HTMLElement} */ input) => h("label", { class: "field" }, h("span", null, label), input);
    const input = (/** @type {string} */ value, /** @type {string} */ placeholder = "") => /** @type {HTMLInputElement} */ (h("input", { type: "text", value, placeholder }));
    const title = input(song?.title ?? "", t("Wpisz tytuł..."));
    const author = input(song?.author ?? "");
    const key = input(song?.key ?? "", t("np. D, G, Am"));
    const tags = input(song?.tags.join(", ") ?? "");
    const copyright = input(song?.copyright ?? "", t("np. © 2024 Wydawnictwo, domena publiczna"));
    const ccli = input(song?.ccliNumber ?? "", "1234567");
    const lyrics = /** @type {HTMLTextAreaElement} */ (h("textarea", { rows: 14, value: song?.rawLyrics ?? "" }));
    const chords = /** @type {HTMLTextAreaElement} */ (h("textarea", { rows: 6, value: song?.chords ?? "" }));
    const save = () => {
      if (!title.value.trim()) { title.focus(); return; }
      const fields = {
        title: title.value.trim(), author: author.value.trim(), key: key.value.trim(),
        tags: tags.value.split(/[,;]/).map((x) => x.trim()).filter(Boolean), rawLyrics: lyrics.value,
      };
      /** @type {Song} */
      let saved;
      if (song) {
        saved = { ...song, ...fields };
        if (chords.value.trim()) saved.chords = chords.value; else delete saved.chords;
      } else {
        saved = this.store.addSong({ ...fields, chords: chords.value.trim() ? chords.value : undefined });
      }
      if (copyright.value.trim()) saved.copyright = copyright.value.trim(); else delete saved.copyright;
      if (ccli.value.trim()) saved.ccliNumber = ccli.value.trim(); else delete saved.ccliNumber;
      this.store.updateSong(saved);
      dialog.close();
    };
    const buttons = [h("button", { onclick: () => dialog.close() }, t("Anuluj")), h("button", { class: "primary", onclick: save }, t("Zapisz"))];
    if (song) buttons.unshift(h("button", { class: "danger", style: { marginRight: "auto" }, onclick: () => {
      if (confirm(t("Czy na pewno usunąć pieśń „{0}”?", song.title))) { this.store.deleteSong(song.id); dialog.close(); }
    } }, t("Usuń")));
    const dialog = this.dialog(song ? t("Edycja pieśni") : t("Nowa pieśń"), [
      h("div", { class: "row" }, field(t("Tytuł pieśni *"), title), field(t("Autor / Źródło"), author), h("label", { class: "field", style: { flex: "0 0 90px", minWidth: "90px" } }, h("span", null, t("Tonacja (Key)")), key)),
      h("div", { class: "row" }, field(t("Prawa autorskie (©)"), copyright), h("label", { class: "field", style: { flex: "0 0 130px", minWidth: "130px" } }, h("span", null, t("Numer CCLI")), ccli)),
      field(t("Tagi / Kategorie (rozdzielone przecinkami)"), tags),
      field(t("Tekst pieśni (pusta linia oddziela slajdy; nagłówki np. [Refren], [Zwrotka 2])"), lyrics),
      field(t("Chwyty"), chords)],
    buttons);
    title.focus();
  }

  openSettings() {
    const { store } = this;
    const s = store.settings;
    const update = (/** @type {Partial<typeof s>} */ changes) => store.updateSettings(changes);
    const select = (/** @type {string} */ value, /** @type {[string, string][]} */ options, /** @type {(v: string) => void} */ onChange) =>
      h("select", { onchange: (/** @type {Event} */ e) => onChange(/** @type {HTMLSelectElement} */ (e.target).value) },
        options.map(([v, label]) => h("option", { value: v, selected: v === value }, label)));
    const range = (/** @type {number} */ value, /** @type {number} */ min, /** @type {number} */ max, /** @type {number} */ step, /** @type {(v: number) => void} */ onChange) =>
      h("input", { type: "range", min, max, step, value, oninput: (/** @type {Event} */ e) => onChange(Number(/** @type {HTMLInputElement} */ (e.target).value)) });
    const field = (/** @type {string} */ label, /** @type {HTMLElement} */ control) => h("label", { class: "field" }, h("span", null, label), control);
    const marginLabel = h("span", null, t("Margines ekranu: {0}%", Math.round(s.marginPercent * 100)));
    const spacingLabel = h("span", null, t("Interlinia: {0}x", s.lineSpacingFactor.toFixed(2)));
    const fonts = ["Helvetica Neue", "Arial", "Georgia", "Times New Roman", "Verdana", "Trebuchet MS", "Palatino", "Gill Sans"];
    const shortcutRows = /** @type {[string, string][]} */ ([["nextSlideKey", "Następny slajd"], ["prevSlideKey", "Poprzedni slajd"], ["nextSongKey", "Następna pieśń"], ["prevSongKey", "Poprzednia pieśń"], ["blackScreenKey", "Czarny ekran"], ["clearTextKey", "Ukryj tekst"], ["startPresentationKey", "Prezentuj"], ["stopPresentationKey", "Zakończ projekcję"]]);
    const dialog = this.dialog(t("Ustawienia"), [
      h("div", { class: "group" }, h("h3", null, t("Język interfejsu")),
        select(s.appLanguage, LANGUAGES.map((l) => [l.code, `${l.flag}  ${l.name}`]), (v) => { update({ appLanguage: v }); dialog.close(); this.openSettings(); })),
      h("div", { class: "group" }, h("h3", null, t("Typografia ekranu prezentacji")),
        h("div", { class: "row" },
          field(t("Czcionka"), select(fonts.includes(s.fontFamily) ? s.fontFamily : fonts[0], fonts.map((f) => [f, f]), (v) => update({ fontFamily: v }))),
          field(t("Wyrównanie poziome"), select(s.textAlignment, [["left", t("Do lewej")], ["center", t("Do środka")], ["right", t("Do prawej")]], (v) => update({ textAlignment: v }))),
          field(t("Wyrównanie pionowe"), select(s.verticalAlignment, [["top", t("Góra")], ["center", t("Środek")], ["bottom", t("Dół")]], (v) => update({ verticalAlignment: v })))),
        h("div", { class: "row" },
          h("label", null, h("input", { type: "checkbox", checked: s.isBold, onchange: (/** @type {Event} */ e) => update({ isBold: /** @type {HTMLInputElement} */ (e.target).checked }) }), " ", t("Pogrubienie")),
          h("label", null, h("input", { type: "checkbox", checked: s.hasShadow, onchange: (/** @type {Event} */ e) => update({ hasShadow: /** @type {HTMLInputElement} */ (e.target).checked }) }), " ", t("Cień tekstu")))),
      h("div", { class: "group" }, h("h3", null, t("Kolory ekranu")),
        h("div", { class: "row" },
          field(t("Kolor tekstu"), h("input", { type: "color", value: s.textColorHex, onchange: (/** @type {Event} */ e) => update({ textColorHex: /** @type {HTMLInputElement} */ (e.target).value.toUpperCase() }) })),
          field(t("Kolor tła"), h("input", { type: "color", value: s.backgroundColorHex, onchange: (/** @type {Event} */ e) => update({ backgroundColorHex: /** @type {HTMLInputElement} */ (e.target).value.toUpperCase() }) })))),
      h("div", { class: "group" }, h("h3", null, t("Marginesy i interlinia")),
        h("label", { class: "field" }, marginLabel, range(s.marginPercent, 0.03, 0.18, 0.01, (v) => { marginLabel.textContent = t("Margines ekranu: {0}%", Math.round(v * 100)); update({ marginPercent: v }); })),
        h("label", { class: "field" }, spacingLabel, range(s.lineSpacingFactor, 1, 1.5, 0.05, (v) => { spacingLabel.textContent = t("Interlinia: {0}x", v.toFixed(2)); update({ lineSpacingFactor: v }); }))),
      h("div", { class: "group" }, h("h3", null, t("Licencja CCLI i prawa autorskie")),
        h("div", { class: "row" },
          field(t("Numer licencji CCLI parafii:"), h("input", { type: "text", value: s.ccliLicenseNumber, placeholder: "1234567", onchange: (/** @type {Event} */ e) => update({ ccliLicenseNumber: /** @type {HTMLInputElement} */ (e.target).value.trim() }) })),
          field(t("Informacja o prawach na slajdzie:"), select(s.copyrightNoticePlacement, [["firstSlide", t("Na pierwszym slajdzie")], ["lastSlide", t("Na ostatnim slajdzie")], ["allSlides", t("Na każdym slajdzie")], ["none", t("Nie pokazuj")]], (v) => update({ copyrightNoticePlacement: v })))),
        h("div", { class: "hint-text" }, t("Dotyczy pieśni z numerem CCLI (np. zaimportowanych z SongSelect). Licencja CCLI wymaga pokazania tytułu, autorów, praw autorskich i numeru licencji przy wyświetlaniu tekstu.")),
        h("div", { class: "row", style: { alignItems: "center" } },
          h("span", { class: "ccli-count" }, t("Raport użycia: zapisane wyświetlenia: {0}", store.ccliUsage.length)),
          h("button", { class: "ccli-export", disabled: !store.ccliUsage.length, onclick: () => this.actions.exportCCLIReport() }, t("Eksportuj raport CCLI (CSV)..."))),
        h("div", { class: "hint-text" }, t("Każda pieśń z numerem CCLI jest zapisywana raz dziennie, gdy trafi na ekran. Plik CSV pomoże zgłosić użycie na stronie CCLI."))),
      h("div", { class: "group" }, h("h3", null, t("Skróty klawiszowe sterowania prezentacją")),
        h("div", { class: "hint-text" }, t("Skróty są wspólne z wersją macOS (zapisywane w kopii zapasowej). Stałe klawisze: strzałki, Page Up/Down, Esc, R (refren), 1–9 (zwrotka).")),
        h("div", { class: "row" }, shortcutRows.map(([k, label]) => h("div", { class: "shortcut" }, h("kbd", null, keyName(/** @type {any} */ (s.shortcuts)[k])), t(label)))))],
    [h("button", { class: "primary", onclick: () => dialog.close() }, t("Gotowe"))]);
  }

  openImportExport() {
    const files = /** @type {HTMLInputElement} */ (h("input", { type: "file", multiple: true, accept: ".txt,.json,.pro,.cho,.chopro,.chordpro,.usr", hidden: true,
      onchange: async () => { if (files.files?.length) { await this.actions.importFiles(files.files); dialog.close(); } } }));
    const backup = /** @type {HTMLInputElement} */ (h("input", { type: "file", accept: ".cantatebackup,.zip", hidden: true,
      onchange: async () => { const file = backup.files?.[0]; if (file) { await this.actions.restoreBackup(file); dialog.close(); } } }));
    const song = this.store.selectedSong;
    const dialog = this.dialog(t("Import/Eksport"), [
      h("div", { class: "group" }, h("h3", null, t("Import pieśni")),
        h("div", { class: "hint-text" }, t("Pliki tekstowe (.txt, dowolne kodowanie), JSON z wersji macOS oraz pliki z CCLI SongSelect (.txt, .usr, ChordPro .pro). Bazy Holyrics importuj w wersji macOS.")),
        h("div", null, h("button", { class: "primary", onclick: () => files.click() }, t("Wybierz pliki...")), files)),
      h("div", { class: "group" }, h("h3", null, t("Kopia zapasowa")),
        h("div", { class: "hint-text" }, t("Plik .cantatebackup działa tak samo w wersji macOS i webowej: zawiera bibliotekę, plany i ustawienia.")),
        h("div", { class: "row" },
          h("button", { class: "primary", onclick: () => this.actions.exportBackup() }, t("Utwórz kopię zapasową")),
          h("button", { onclick: () => backup.click() }, t("Przywróć z kopii...")), backup,
          h("button", { disabled: !this.actions.canUndoRestore(), onclick: async () => { await this.actions.undoRestore(); dialog.close(); } }, t("Cofnij ostatnie przywrócenie")))),
      h("div", { class: "group" }, h("h3", null, t("Eksport")),
        h("button", { disabled: !song || song === this.store.temporarySong, onclick: () => song && this.actions.exportSongText(song) }, t("Zapisz wybraną pieśń jako .txt")))],
    [h("button", { onclick: () => dialog.close() }, t("Zamknij"))]);
  }

  openAbout() {
    const dialog = this.dialog(t("O programie"), [
      h("div", { style: { fontSize: "1.4em", fontWeight: "700" } }, "♫ CantatePresenter"),
      h("div", null, t("Wersja {0}", APP_VERSION), " · Web"),
      h("div", null, "© 2026 Andrzej Oles. ", t("Opracowano we współpracy z Claude (Anthropic).")),
      h("div", { class: "hint-text" }, t("Dane są przechowywane na prywatnym serwerze; dostęp wymaga hasła i kodu z aplikacji uwierzytelniającej."))],
    [h("button", { class: "primary", onclick: () => dialog.close() }, t("Zamknij"))]);
  }
}
