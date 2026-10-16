// @ts-check
// Ekran dla muzyków: bieżący i następny slajd z chwytami nad tekstem (jak okno „Muzycy” i tablety w macOS).
// Stan przychodzi z okna głównego na tym samym komputerze (BroadcastChannel) albo z serwera (/api/live)
// na innych urządzeniach po zalogowaniu. Transpozycję i czcionkę każde urządzenie pamięta osobno.

import { openChannel } from "./channel.js";
import { loadCatalog, setLanguage, t } from "../i18n.js";
import { makeStage } from "../core/stage.js";
import { slideLabel } from "./labels.js";

const $ = (/** @type {string} */ id) => /** @type {HTMLElement} */ (document.getElementById(id));
const saved = {
  /** @param {string} key @param {number} fallback */
  get(key, fallback) { try { const v = localStorage.getItem(`cantate-${key}`); return v === null ? fallback : Number(v) || fallback; } catch { return fallback; } },
  /** @param {string} key @param {number} value */
  set(key, value) { try { localStorage.setItem(`cantate-${key}`, String(value)); } catch { /* tryb prywatny */ } },
};
let semitones = saved.get("transpose", 0) % 12;
let fontSize = saved.get("font", 30);
/** @type {import("../core/stage.js").StageSource | null} */
let source = null;
let online = true;

/** @param {string} tag @param {string} [className] @param {string} [text] */
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

/** @param {import("../core/stage.js").MusicianSlide} slide */
const rows = (slide) => slide.lines.reduce((n, l) => n + (l.chords ? 1 : 0) + (l.text ? 1 : 0), 0) + 0.6 + (slide.borrowedFrom ? 0.5 : 0);

/** Czcionka dopasowana do ekranu bez przewijania (jak strona dla tabletów w macOS). @param {import("../core/stage.js").MusicianStage} stage */
function fittedSize(stage) {
  const main = $("main").getBoundingClientRect();
  const slides = [stage.current, stage.next].filter((s) => s !== null);
  const longest = Math.max(1, ...slides.flatMap((s) => s.lines.flatMap((l) => [Array.from(l.chords ?? "").length, Array.from(l.text).length])));
  const widthFit = main.width / (longest * 0.61);
  const total = rows(/** @type {any} */ (stage.current)) * 1.3 + (stage.next ? rows(stage.next) * 0.7 * 1.3 + 1.6 : 0);
  const heightFit = (main.height - 12) / Math.max(total, 1);
  return Math.max(10, Math.min(fontSize, widthFit, heightFit));
}

/** @param {import("../core/stage.js").MusicianSlide} slide @param {number} size */
function slideBlock(slide, size) {
  const block = el("div");
  const label = el("div", "label", slide.label);
  label.style.fontSize = `${Math.max(11, size * 0.45)}px`;
  block.append(label);
  for (const line of slide.lines) {
    for (const [text, className] of [[line.chords, "row chords"], [line.text, "row"]]) {
      if (!text) continue;
      const row = el("div", /** @type {string} */ (className), text);
      row.style.fontSize = `${size}px`;
      block.append(row);
    }
  }
  if (slide.borrowedFrom) block.append(el("div", "note", t("Chwyty jak w: {0}", slide.borrowedFrom)));
  return block;
}

function render() {
  document.title = t("Ekran dla muzyków");
  $("transposeLabel").textContent = t("Transpozycja");
  $("fontLabel").textContent = t("Czcionka");
  $("tValue").textContent = `${semitones > 0 ? "+" : ""}${semitones}`;
  $("banner").textContent = t("Brak połączenia z serwerem. Ekran pokaże zmiany po ponownym połączeniu.");
  $("banner").classList.toggle("show", !online);
  const main = $("main");
  main.replaceChildren();
  if (!source) {
    $("song").textContent = t("Ekran dla muzyków");
    $("meta").replaceChildren();
    main.append(el("div", "empty", t("Brak aktywnej prezentacji")));
    return;
  }
  const stage = makeStage(source, semitones, slideLabel);
  $("song").textContent = stage.songTitle || t("Ekran dla muzyków");
  const meta = $("meta");
  meta.replaceChildren();
  if (stage.key) meta.append(el("span", "key", t("Tonacja: {0}", stage.key)));
  if (stage.current) meta.append(el("span", "", `${stage.current.label} · ${stage.position}`));
  if (stage.isBlackScreen) meta.append(el("span", "alert", t("CZARNY EKRAN")));
  else if (stage.isClearText) meta.append(el("span", "alert", t("TEKST UKRYTY")));
  if (stage.current && !stage.hasChords) meta.append(el("span", "alert", t("Brak chwytów dla tej pieśni")));
  if (!stage.current) {
    main.append(el("div", "empty", t("Brak aktywnej prezentacji")));
    if (stage.nextSongTitle) main.append(el("div", "empty", t("Następnie: {0}", stage.nextSongTitle)));
    return;
  }
  const size = fittedSize(stage);
  main.append(slideBlock(stage.current, size));
  if (stage.next) {
    const next = el("div", "next");
    next.append(el("div", "next-title", stage.nextSongTitle ? t("Następnie: {0}", stage.nextSongTitle) : t("Następny slajd")));
    next.append(slideBlock(stage.next, size * 0.7));
    main.append(next);
  }
}

/** Nowszy stan wygrywa, skądkolwiek przyszedł. @param {any} incoming */
function accept(incoming) {
  if (!incoming || typeof incoming !== "object" || (source && incoming.updatedAt < source.updatedAt)) return;
  if (incoming.language && incoming.language !== source?.language) setLanguage(incoming.language);
  source = incoming;
  render();
}

const channel = openChannel();
channel.onmessage = (event) => { if (event.data?.type === "stage") accept(event.data.source); };

async function poll() {
  try {
    const response = await fetch("/api/live", { credentials: "same-origin", cache: "no-store" });
    if (response.status === 401) { location.href = "/login.html"; return; }
    if (!response.ok) throw new Error(String(response.status));
    accept((await response.json()).source);
    if (!online) { online = true; render(); }
  } catch {
    if (online) { online = false; render(); }
  }
}

$("tDown").onclick = () => { semitones = (semitones - 1) % 12; saved.set("transpose", semitones); render(); };
$("tUp").onclick = () => { semitones = (semitones + 1) % 12; saved.set("transpose", semitones); render(); };
$("fDown").onclick = () => { fontSize = Math.max(12, fontSize - 3); saved.set("font", fontSize); render(); };
$("fUp").onclick = () => { fontSize = Math.min(90, fontSize + 3); saved.set("font", fontSize); render(); };
addEventListener("resize", render);
document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });

await loadCatalog(new URL("../../i18n/Localizable.xcstrings", import.meta.url)).catch(() => {});
render();
channel.postMessage({ type: "stage-hello" });
setInterval(() => { if (!document.hidden) poll(); }, 1500);
poll();
