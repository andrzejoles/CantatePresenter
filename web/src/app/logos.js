// @ts-check
// Logo planszy startowej: te same wzory co w macOS (web/logos.json, eksport z LogoCatalog).

/** @typedef {{id: string, name: string, svg: string}} Logo */

/** @type {Logo[]} */
let logos = [];

export async function loadLogos() {
  const response = await fetch(new URL("../../logos.json", import.meta.url), { credentials: "same-origin" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  logos = await response.json();
  return logos;
}

export const allLogos = () => logos;

/** Logo o danym id albo pierwsze (jak LogoCatalog.getById). @param {string} id */
export const logoById = (id) => logos.find((logo) => logo.id === id) ?? logos[0] ?? null;

/** SVG jako obrazek (bez wstawiania znaczników do strony). @param {string} svg */
export const svgDataURL = (svg) => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
