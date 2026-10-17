// @ts-check
// Dyktowanie głosem jak DictationButtonView w macOS, przez Web Speech API przeglądarki (Chrome, Edge, Safari).
// Bez obsługi w przeglądarce (np. Firefox) przycisk się nie pojawia. Język i „tylko na urządzeniu” z ustawień
// wspólnych z macOS (dictationLanguage, dictationOnDeviceOnly).
import { h } from "./dom.js";
import { t } from "../i18n.js";

/** Języki dyktowania jak LanguagePresets.dictationLanguages w macOS. */
export const DICTATION_LANGUAGES = /** @type {[string, string, string][]} */ ([
  ["pl-PL", "Polski (Polska)", "🇵🇱"], ["en-US", "English (United States)", "🇺🇸"], ["en-GB", "English (United Kingdom)", "🇬🇧"],
  ["de-DE", "Deutsch (Deutschland)", "🇩🇪"], ["es-ES", "Español (España)", "🇪🇸"], ["uk-UA", "Українська (Україна)", "🇺🇦"],
  ["it-IT", "Italiano (Italia)", "🇮🇹"], ["fr-FR", "Français (France)", "🇫🇷"],
]);

/** @returns {any} konstruktor SpeechRecognition albo undefined */
function recognitionClass() {
  const w = /** @type {any} */ (window);
  return w.SpeechRecognition ?? w.webkitSpeechRecognition;
}

export const dictationSupported = () => typeof recognitionClass() === "function";

/** Trwające dyktowanie (tylko jedno naraz, jak w macOS). @type {{ abort: () => void } | null} */
let active = null;

/** @param {string} code błąd Web Speech API */
function errorMessage(code) {
  switch (code) {
    case "not-allowed":
    case "service-not-allowed": return t("Odmówiono dostępu do mikrofonu. Zezwól na mikrofon dla tej strony w ustawieniach przeglądarki.");
    case "audio-capture": return t("Nie znaleziono mikrofonu.");
    case "network": return t("Brak połączenia z usługą rozpoznawania mowy.");
    case "language-not-supported": return t("Przeglądarka nie rozpoznaje mowy w wybranym języku.");
    default: return `${t("Problem z dyktowaniem")}: ${code}`;
  }
}

/**
 * Przycisk mikrofonu dla pola tekstowego; null, gdy przeglądarka nie obsługuje rozpoznawania mowy.
 * @param {HTMLInputElement | HTMLTextAreaElement} field
 * @param {"replace" | "append" | "appendNewline"} mode jak DictationTargetMode w macOS
 * @param {{ settings: () => any, onError: (message: string) => void, prompt?: string }} options
 * @returns {HTMLButtonElement | null}
 */
export function dictationButton(field, mode, options) {
  const Recognition = recognitionClass();
  if (typeof Recognition !== "function") return null;
  const languageName = () => {
    const code = options.settings().dictationLanguage ?? "pl-PL";
    return DICTATION_LANGUAGES.find(([c]) => c === code)?.[1] ?? code;
  };
  const button = /** @type {HTMLButtonElement} */ (h("button", { type: "button", class: "mic" }));
  /** @type {any} */ let recognition = null;
  const show = (/** @type {boolean} */ recording) => {
    button.classList.toggle("recording", recording);
    button.textContent = recording ? `● ${t("Dyktuję...")}` : "🎤";
    button.title = recording ? t("Kliknij, aby zakończyć dyktowanie") : options.prompt ?? t("Dyktuj głosowo ({0})", languageName());
  };
  show(false);

  /** @param {string} base @param {string} recognized */
  const apply = (base, recognized) => {
    const clean = recognized.replace(/\s+/g, " ").trim();
    if (!clean) return;
    if (mode === "replace" || !base.trim()) field.value = clean;
    else field.value = base + (mode === "appendNewline" ? "\n\n" : " ") + clean;
    field.dispatchEvent(new Event("input", { bubbles: true }));
  };

  button.addEventListener("click", () => {
    if (recognition) {
      recognition.stop();
      return;
    }
    active?.abort();
    const settings = options.settings();
    const session = new Recognition();
    session.lang = settings.dictationLanguage ?? "pl-PL";
    session.interimResults = true;
    session.continuous = true;
    if (settings.dictationOnDeviceOnly === true) {
      // Rozpoznawanie bez wysyłania nagrania (nowsze przeglądarki z pobranym modelem mowy).
      if (!("processLocally" in session)) {
        options.onError(t("Ta przeglądarka nie potrafi rozpoznawać mowy tylko na urządzeniu. Wyłącz tę opcję w Ustawieniach albo użyj nowszej przeglądarki."));
        return;
      }
      session.processLocally = true;
    }
    const base = field.value;
    session.onresult = (/** @type {any} */ event) => {
      apply(base, Array.from(/** @type {ArrayLike<any>} */ (event.results), (result) => result[0]?.transcript ?? "").join(" "));
    };
    session.onerror = (/** @type {any} */ event) => {
      if (event.error !== "aborted" && event.error !== "no-speech") options.onError(errorMessage(event.error));
    };
    session.onend = () => {
      if (recognition === session) recognition = null;
      if (active?.abort === abort) active = null;
      show(false);
    };
    const abort = () => session.abort();
    recognition = session;
    active = { abort };
    try {
      session.start();
      show(true);
    } catch (error) {
      recognition = null;
      active = null;
      options.onError(errorMessage(String(/** @type {Error} */ (error).message ?? error)));
    }
  });
  return button;
}
