// @ts-check
// Pomocnik do budowania DOM bez frameworka. Tekst zawsze jako węzły tekstowe (bez innerHTML).

/**
 * @param {string} tag
 * @param {Record<string, any> | null} [props]
 * @param {...any} children
 * @returns {HTMLElement}
 */
export function h(tag, props, ...children) {
  const element = document.createElement(tag);
  for (const [key, value] of Object.entries(props ?? {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key.startsWith("on") && typeof value === "function") {
      element.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (key === "class") {
      element.className = value;
    } else if (key === "style" && typeof value === "object") {
      Object.assign(element.style, value);
    } else if (["value", "checked", "selected", "disabled", "hidden"].includes(key)) {
      /** @type {any} */ (element)[key] = value;
    } else if (key === "dataset") {
      Object.assign(element.dataset, value);
    } else {
      element.setAttribute(key, value === true ? "" : String(value));
    }
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    element.append(child instanceof Node ? child : String(child));
  }
  return element;
}

/** Ikona SF-like z zestawu w styles.css (span z klasą). @param {string} name */
export const icon = (name) => h("span", { class: `icon icon-${name}`, "aria-hidden": "true" });

/** @param {Element} element @param {...any} children */
export function replace(element, ...children) {
  element.replaceChildren(...children.flat(Infinity).filter((c) => c !== null && c !== undefined && c !== false));
}
