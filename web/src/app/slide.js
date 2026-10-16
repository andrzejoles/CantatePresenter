// @ts-check
// Rysowanie slajdu: ten sam kod dla okna projekcji i podglądów (jak SlideTextView w macOS, N1).
// Podgląd to pomniejszony ekran docelowy, więc rozmiar czcionki liczony jest dla pełnego ekranu i skalowany.

import { optimalFontSize, cssFont } from "../core/autofit.js";
import { h } from "./dom.js";

/**
 * @typedef {{isLive: boolean, isBlackScreen: boolean, isClearText: boolean, text: string, notice: string | null,
 *   settings: import("../core/models.js").normalizeSettings extends (...a: any) => infer R ? R : never,
 *   standbyTitle: string, standbySubtitle: string, standbyLogo?: string, standbyReady?: string, standbyCredits?: string}} ScreenState
 */

const STANDBY_WIDTH = 960;

const clockText = () => new Date().toLocaleTimeString("pl-PL", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });
// Zegar na planszy: jeden licznik dla wszystkich plansz w oknie (podglądy i okno projekcji).
setInterval(() => { for (const clock of document.querySelectorAll(".standby .live-clock")) clock.textContent = clockText(); }, 1000);

/**
 * Wypełnia `container` obrazem ekranu projekcji. Slajd jest rysowany w pełnym rozmiarze ekranu docelowego
 * i pomniejszany (transform), więc wiersze łamią się w podglądzie dokładnie tak jak na projektorze.
 * @param {HTMLElement} container
 * @param {ScreenState} state
 * @param {{width: number, height: number}} target rozmiar ekranu docelowego (np. projektora)
 * @param {{dimmed?: boolean}} [options]
 */
export function renderScreen(container, state, target, options = {}) {
  const { settings } = state;
  const box = container.getBoundingClientRect();
  const scale = target.width > 0 && box.width > 0 ? box.width / target.width : 1;
  container.replaceChildren();
  container.classList.add("screen");
  container.style.background = state.isBlackScreen ? "#000" : settings.backgroundColorHex;
  if (state.isBlackScreen) return;

  const stage = h("div", {
    class: "stage",
    style: { width: `${target.width}px`, height: `${target.height}px`, transform: `scale(${scale})` },
  });
  container.append(stage);

  if (!state.isLive) {
    // Jak StandbyZoom w macOS: projekt planszy na 960 px szerokości, powiększony do szerokości ekranu.
    const zoom = target.width / STANDBY_WIDTH;
    stage.append(h("div", { class: "standby", style: { height: `${target.height / zoom}px`, transform: `scale(${zoom})` } },
      h("div", { class: "ambient-glow" }),
      h("div", { class: "container" },
        state.standbyLogo ? h("div", { class: "logo-wrapper" }, h("img", { src: state.standbyLogo, alt: "" })) : null,
        h("h1", { class: "app-title" }, state.standbyTitle),
        h("div", { class: "version-badge" }, h("span", { class: "dot" }), h("span", null, state.standbySubtitle))),
      h("div", { class: "footer-status" }, h("div", { class: "live-clock" }, clockText()), h("div", null, state.standbyReady ?? "")),
      state.standbyCredits ? h("div", { class: "credits" }, state.standbyCredits) : null));
    return;
  }
  if (state.isClearText || !state.text) return;

  const fontSize = optimalFontSize(state.text, {
    width: target.width, height: target.height, fontFamily: settings.fontFamily, isBold: settings.isBold,
    lineSpacingFactor: settings.lineSpacingFactor, marginPercent: settings.marginPercent,
  });
  const margin = settings.marginPercent;
  const shadow = settings.hasShadow ? `2px 2px 4px rgba(0,0,0,${options.dimmed ? 0.4 : 0.85})` : "none";
  const justify = { top: "flex-start", center: "center", bottom: "flex-end" }[settings.verticalAlignment] ?? "center";

  stage.append(h("div", {
    class: "slide-text",
    style: { justifyContent: justify, padding: `${target.height * margin}px ${target.width * margin}px`, textAlign: settings.textAlignment },
  }, h("div", {
    style: {
      font: cssFont(settings.fontFamily, fontSize, settings.isBold),
      lineHeight: `${1.2 + (settings.lineSpacingFactor - 1)}`,
      color: settings.textColorHex,
      opacity: options.dimmed ? "0.65" : "1",
      textShadow: shadow,
      whiteSpace: "pre-line",
      overflowWrap: "break-word",
    },
  }, state.text)));

  if (state.notice) {
    stage.append(h("div", {
      class: "slide-notice",
      style: { fontSize: `${target.height * 0.022}px`, color: settings.textColorHex, bottom: `${target.height * 0.012}px`, padding: `0 ${target.width * 0.04}px` },
    }, state.notice));
  }
}
