// @ts-check
// Okno projekcji: pokazuje stan z okna głównego i odsyła skróty klawiszowe (kontekst „okno projekcji”).

import { openChannel } from "./channel.js";
import { renderScreen } from "./slide.js";
import { keyboardAction, MAC_KEY_CODES } from "../core/keyboard.js";
import { loadCatalog, setLanguage, t } from "../i18n.js";

const channel = openChannel();
const screenElement = /** @type {HTMLElement} */ (document.getElementById("screen"));
const hint = /** @type {HTMLElement} */ (document.getElementById("hint"));
/** @type {any} */
let state = null;

function size() {
  return { width: window.innerWidth, height: window.innerHeight };
}

function draw() {
  if (state) renderScreen(screenElement, state, size());
}

channel.onmessage = (event) => {
  if (event.data?.type === "state") {
    const languageChanged = state?.settings.appLanguage !== event.data.state.settings.appLanguage;
    state = event.data.state;
    if (languageChanged) {
      setLanguage(state.settings.appLanguage);
      hint.textContent = t("Kliknij dwukrotnie albo naciśnij F, aby włączyć pełny ekran.");
    }
    draw();
  }
};

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen().catch(() => {});
}

document.addEventListener("dblclick", toggleFullscreen);
document.addEventListener("keydown", (event) => {
  if (event.code === "KeyF" && !event.metaKey && !event.ctrlKey) {
    toggleFullscreen();
    return;
  }
  const action = keyboardAction({
    macCode: MAC_KEY_CODES[/** @type {keyof typeof MAC_KEY_CODES} */ (event.code)],
    characters: event.key.length === 1 ? event.key.toLowerCase() : "",
    command: event.metaKey || event.ctrlKey,
    shortcuts: state?.settings.shortcuts ?? {},
    context: { kind: "presentation" },
  });
  if (action) {
    event.preventDefault();
    channel.postMessage({ type: "action", action });
  }
});

let hintTimer = setTimeout(() => hint.classList.add("hidden"), 4000);
document.addEventListener("mousemove", () => {
  document.body.classList.remove("no-cursor");
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => { hint.classList.add("hidden"); document.body.classList.add("no-cursor"); }, 2500);
});

window.addEventListener("resize", () => {
  draw();
  channel.postMessage({ type: "size", ...size() });
});

await loadCatalog(new URL("../../i18n/Localizable.xcstrings", import.meta.url)).catch(() => {});
hint.textContent = t("Kliknij dwukrotnie albo naciśnij F, aby włączyć pełny ekran.");
channel.postMessage({ type: "hello" });
channel.postMessage({ type: "size", ...size() });
