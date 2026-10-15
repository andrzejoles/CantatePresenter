// @ts-check
// Skróty klawiszowe: odpowiednik KeyboardRouter z wersji macOS. Ustawienia zapisują kody klawiszy macOS
// (ten sam settings.json), a przeglądarka zgłasza KeyboardEvent.code; MAC_KEY_CODES je łączy.

/** KeyboardEvent.code → kod klawisza macOS (kVK_*). */
export const MAC_KEY_CODES = Object.freeze({
  KeyA: 0, KeyS: 1, KeyD: 2, KeyF: 3, KeyH: 4, KeyG: 5, KeyZ: 6, KeyX: 7, KeyC: 8, KeyV: 9, KeyB: 11,
  KeyQ: 12, KeyW: 13, KeyE: 14, KeyR: 15, KeyY: 16, KeyT: 17, Digit1: 18, Digit2: 19, Digit3: 20, Digit4: 21,
  Digit6: 22, Digit5: 23, Equal: 24, Digit9: 25, Digit7: 26, Minus: 27, Digit8: 28, Digit0: 29,
  BracketRight: 30, KeyO: 31, KeyU: 32, BracketLeft: 33, KeyI: 34, KeyP: 35, Enter: 36, KeyL: 37, KeyJ: 38,
  Quote: 39, KeyK: 40, Semicolon: 41, Backslash: 42, Comma: 43, Slash: 44, KeyN: 45, KeyM: 46, Period: 47,
  Tab: 48, Space: 49, Backquote: 50, Backspace: 51, Escape: 53, NumpadEnter: 76,
  F5: 96, F6: 97, F7: 98, F3: 99, F8: 100, F9: 101, F11: 103, F10: 109, F12: 111,
  Home: 115, PageUp: 116, Delete: 117, F4: 118, End: 119, F2: 120, PageDown: 121, F1: 122,
  ArrowLeft: 123, ArrowRight: 124, ArrowDown: 125, ArrowUp: 126,
});

const KEY = { escape: 53, returnKey: 36, left: 123, right: 124, down: 125, up: 126, pageDown: 121, pageUp: 116, r: 15 };
const DIGITS = new Set([18, 19, 20, 21, 23, 22, 26, 28, 25]);
const NON_TYPING = new Set([116, 121, 115, 119, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]);

/** Nazwa klawisza do wyświetlenia w ustawieniach. @param {number} macCode */
export function keyName(macCode) {
  const entry = Object.entries(MAC_KEY_CODES).find(([, code]) => code === macCode);
  if (!entry) return `#${macCode}`;
  const names = /** @type {Record<string, string>} */ ({ Space: "Spacja", Enter: "Enter", Escape: "Esc", ArrowLeft: "←", ArrowRight: "→", ArrowUp: "↑", ArrowDown: "↓", BracketLeft: "[", BracketRight: "]", PageUp: "Page Up", PageDown: "Page Down" });
  return names[entry[0]] ?? entry[0].replace(/^Key|^Digit/, "");
}

/**
 * @typedef {{type: string, number?: number}} KeyboardAction
 * @typedef {"text" | "multilineText" | "list" | "other"} Focus
 * @typedef {{kind: "main", focus: Focus} | {kind: "presentation"}} KeyContext
 */

/**
 * Akcja dla klawisza; kolejność jak w macOS: skróty z ⌘/Ctrl, skróty z ustawień, potem stałe klawisze.
 * @param {{macCode: number | undefined, characters: string, command: boolean, shortcuts: Record<string, number>,
 *          context: KeyContext | null}} input
 * @returns {KeyboardAction | null}
 */
export function keyboardAction({ macCode, characters, command, shortcuts, context }) {
  if (!context || macCode === undefined) return null;
  const isMain = context.kind === "main";
  if (isMain && context.focus === "multilineText") return null;
  if (isMain && context.focus === "text") {
    if (macCode === KEY.escape && !command) return { type: "endTextEditing" };
    if (command || !NON_TYPING.has(macCode)) return null;
  }
  if (command) {
    if (!isMain) return null;
    switch (characters) {
      case "t": return { type: "quickText" };
      case "=": case "+": return { type: "zoomIn" };
      case "-": return { type: "zoomOut" };
      case "0": return { type: "zoomReset" };
      default: return null;
    }
  }
  const isPresentation = context.kind === "presentation";
  if (isMain && context.focus === "list" && (macCode === KEY.up || macCode === KEY.down)) return null;

  /** @type {[number | undefined, string][]} */
  const configured = [
    [shortcuts.nextSlideKey, "nextSlide"],
    [shortcuts.prevSlideKey, "prevSlide"],
    [shortcuts.nextSongKey, "nextSong"],
    [shortcuts.prevSongKey, "prevSong"],
    [shortcuts.stopPresentationKey, "stopPresentation"],
    [shortcuts.blackScreenKey, "blackScreen"],
    [shortcuts.clearTextKey, "clearText"],
    [isPresentation ? undefined : shortcuts.startPresentationKey, "startPresentation"],
  ];
  const match = configured.find(([code]) => code !== undefined && code === macCode);
  if (match) return { type: match[1] };

  if (macCode === KEY.right || macCode === KEY.down || macCode === KEY.pageDown) return { type: "nextSlide" };
  if (macCode === KEY.returnKey && isPresentation) return { type: "nextSlide" };
  if (macCode === KEY.left || macCode === KEY.up || macCode === KEY.pageUp) return { type: "prevSlide" };
  if (macCode === KEY.escape) return { type: "stopPresentation" };
  if (macCode === KEY.r) return { type: "chorus" };
  if (DIGITS.has(macCode)) {
    const number = Number.parseInt(characters, 10);
    return number >= 1 && number <= 9 ? { type: "verse", number } : null;
  }
  return null;
}
