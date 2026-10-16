// @ts-check
// Logowanie: hasło, potem kod z aplikacji uwierzytelniającej (TOTP) albo kod zapasowy.
// Przy pierwszym logowaniu konfiguracja aplikacji przez kod QR i jednorazowe pokazanie kodów zapasowych.

import { loadCatalog, setLanguage, t, LANGUAGES } from "./i18n.js";
import { qrSVG } from "./core/qr.js";

const root = /** @type {HTMLElement} */ (document.getElementById("login"));
const HEADERS = { "X-Cantate-Request": "1", "Content-Type": "application/json" };

/** @param {string} tag @param {Record<string, any>} [props] @param {...any} children */
function h(tag, props = {}, ...children) {
  const element = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key.startsWith("on")) element.addEventListener(key.slice(2), value);
    else if (key === "class") element.className = value;
    else element.setAttribute(key, value);
  }
  element.append(...children.flat().filter((c) => c !== null && c !== undefined));
  return element;
}

/** @param {string} path @param {unknown} body */
async function post(path, body) {
  const response = await fetch(path, { method: "POST", headers: HEADERS, body: JSON.stringify(body), credentials: "same-origin" });
  let data = null;
  try { data = await response.json(); } catch { /* bez treści */ }
  return { status: response.status, data };
}

/** @param {number} status */
function errorText(status) {
  if (status === 429) return t("Zbyt wiele nieudanych prób. Spróbuj ponownie za 15 minut.");
  if (status === 401) return t("Nieprawidłowe dane logowania.");
  return t("Błąd serwera ({0}). Spróbuj ponownie.", status);
}

function header() {
  return h("div", { class: "login-brand" }, h("span", { class: "brand-mark" }, "♫"), "CantatePresenter");
}

function showPassword(message = "") {
  const username = /** @type {HTMLInputElement} */ (h("input", { type: "text", name: "username", autocomplete: "username", required: "", autocapitalize: "off", spellcheck: "false" }));
  const password = /** @type {HTMLInputElement} */ (h("input", { type: "password", name: "password", autocomplete: "current-password", required: "" }));
  const error = h("div", { class: "login-error", role: "alert" }, message);
  const button = /** @type {HTMLButtonElement} */ (h("button", { class: "primary", type: "submit" }, t("Zaloguj")));
  const form = h("form", {
    onsubmit: async (/** @type {Event} */ event) => {
      event.preventDefault();
      button.disabled = true;
      const { status, data } = await post("/api/login", { username: username.value.trim(), password: password.value });
      button.disabled = false;
      if (status !== 200) { error.textContent = errorText(status); password.select(); return; }
      if (data.step === "enroll") showEnroll(data.secret, data.uri);
      else showCode();
    },
  },
  h("label", { class: "field" }, h("span", {}, t("Użytkownik")), username),
  h("label", { class: "field" }, h("span", {}, t("Hasło")), password),
  error, button);
  root.replaceChildren(header(), h("h1", {}, t("Logowanie")), form);
  username.focus();
}

function codeInput() {
  return /** @type {HTMLInputElement} */ (h("input", { type: "text", inputmode: "numeric", autocomplete: "one-time-code", required: "", maxlength: "12", class: "code-input", autocapitalize: "off", spellcheck: "false" }));
}

function showCode() {
  const code = codeInput();
  const error = h("div", { class: "login-error", role: "alert" });
  const form = h("form", {
    onsubmit: async (/** @type {Event} */ event) => {
      event.preventDefault();
      const { status } = await post("/api/login/totp", { code: code.value });
      if (status === 200) { location.href = "/"; return; }
      if (status === 401 && code.value) { error.textContent = t("Nieprawidłowy kod."); code.select(); }
      else showPassword(errorText(status));
    },
  },
  h("p", {}, t("Wpisz 6-cyfrowy kod z aplikacji uwierzytelniającej (np. Google Authenticator, Microsoft Authenticator, 1Password).")),
  h("label", { class: "field" }, h("span", {}, t("Kod")), code),
  h("p", { class: "hint-text" }, t("Nie masz dostępu do aplikacji? Wpisz jeden z kodów zapasowych.")),
  error, h("button", { class: "primary", type: "submit" }, t("Potwierdź")));
  root.replaceChildren(header(), h("h1", {}, t("Weryfikacja dwuetapowa")), form);
  code.focus();
}

/** @param {string} secret @param {string} uri */
function showEnroll(secret, uri) {
  const code = codeInput();
  const error = h("div", { class: "login-error", role: "alert" });
  const form = h("form", {
    onsubmit: async (/** @type {Event} */ event) => {
      event.preventDefault();
      const { status, data } = await post("/api/login/enroll", { code: code.value });
      if (status === 200) showBackupCodes(data.backupCodes);
      else if (status === 401 && code.value) { error.textContent = t("Nieprawidłowy kod. Sprawdź, czy czas w telefonie jest ustawiony automatycznie."); code.select(); }
      else showPassword(errorText(status));
    },
  },
  h("p", {}, t("To konto wymaga weryfikacji dwuetapowej. Zeskanuj kod QR aplikacją uwierzytelniającą (np. Google Authenticator, Microsoft Authenticator, 1Password).")),
  h("div", { class: "qr" }, qrSVG(uri, 220)),
  h("details", {}, h("summary", {}, t("Nie możesz zeskanować? Wpisz klucz ręcznie")), h("code", { class: "secret" }, secret.replace(/(.{4})/g, "$1 ").trim())),
  h("label", { class: "field" }, h("span", {}, t("Kod z aplikacji")), code),
  error, h("button", { class: "primary", type: "submit" }, t("Włącz weryfikację dwuetapową")));
  root.replaceChildren(header(), h("h1", {}, t("Konfiguracja weryfikacji dwuetapowej")), form);
  code.focus();
}

/** @param {string[]} codes */
function showBackupCodes(codes) {
  const confirmed = /** @type {HTMLInputElement} */ (h("input", { type: "checkbox" }));
  const next = /** @type {HTMLButtonElement} */ (h("button", { class: "primary", disabled: "", onclick: () => { location.href = "/"; } }, t("Przejdź do aplikacji")));
  confirmed.addEventListener("change", () => { next.disabled = !confirmed.checked; });
  const download = () => {
    const blob = new Blob([`CantatePresenter: ${t("kody zapasowe")}\n\n${codes.join("\n")}\n`], { type: "text/plain;charset=utf-8" });
    const link = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "cantate-kody-zapasowe.txt" });
    link.click();
  };
  root.replaceChildren(header(), h("h1", {}, t("Kody zapasowe")),
    h("p", {}, t("Zapisz te kody w bezpiecznym miejscu. Każdy działa raz, gdy nie masz dostępu do aplikacji uwierzytelniającej. Nie zostaną pokazane ponownie.")),
    h("ul", { class: "backup-codes" }, codes.map((c) => h("li", {}, h("code", {}, c)))),
    h("div", { class: "row" }, h("button", { type: "button", onclick: download }, t("Pobierz jako plik"))),
    h("label", {}, confirmed, " ", t("Zapisałem kody zapasowe")),
    next);
}

const preferred = navigator.languages.map((l) => l.slice(0, 2)).find((code) => LANGUAGES.some((l) => l.code === code)) ?? "pl";
await loadCatalog("/i18n/Localizable.xcstrings").catch(() => {});
setLanguage(preferred);
const session = await fetch("/api/session", { credentials: "same-origin" });
if (session.ok) location.href = "/";
else showPassword();
