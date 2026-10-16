// @ts-check
// Etykiety slajdów w języku interfejsu (wspólne dla okna głównego i ekranu muzyków).

import { t } from "../i18n.js";
import { polishName } from "../core/lyrics.js";

/** Domyślne („Zwrotka 2”) tłumaczone, własne bez zmian. @param {{type: string, label: string, number?: number | null}} slide */
export function slideLabel(slide) {
  const base = polishName[/** @type {keyof typeof polishName} */ (slide.type)] ?? slide.label;
  if (slide.label === base) return t(base);
  if (slide.number !== undefined && slide.number !== null && slide.label === `${base} ${slide.number}`) return `${t(base)} ${slide.number}`;
  return slide.label;
}
