// @ts-check
// Auto-Fit: największa czcionka, przy której tekst slajdu mieści się na ekranie (jak AutoFitEngine w macOS):
// wyszukiwanie binarne, 12 kroków, każde słowo musi się zmieścić w szerokości, a cały akapit w wysokości.

/** @type {CanvasRenderingContext2D | null} */
let context = null;
const cache = new Map();
const CACHE_LIMIT = 512;

/** @param {string} family @param {number} size @param {boolean} bold */
export function cssFont(family, size, bold) {
  return `${bold ? "bold " : ""}${size}px "${family}", "Helvetica Neue", Helvetica, Arial, sans-serif`;
}

/** @param {string} font */
function measurer(font) {
  context ??= document.createElement("canvas").getContext("2d");
  if (!context) throw new Error("canvas unavailable");
  context.font = font;
  return context;
}

/**
 * Wysokość tekstu po zawinięciu słów w szerokości `width` (wiersze jawne z \n zachowane).
 * @param {string} text @param {(text: string) => number} measure @param {number} size @param {number} width @param {number} lineSpacingFactor
 */
function wrappedHeight(text, measure, size, width, lineSpacingFactor) {
  let lines = 0;
  for (const paragraph of text.split("\n")) {
    const words = paragraph.split(/\s+/).filter(Boolean);
    if (!words.length) { lines++; continue; }
    let current = "";
    lines++;
    for (const word of words) {
      const candidate = current ? `${current} ${word}` : word;
      if (current && measure(candidate) > width) {
        lines++;
        current = word;
      } else {
        current = candidate;
      }
    }
  }
  const lineHeight = size * 1.2;
  return lines * lineHeight + Math.max(0, lines - 1) * size * (lineSpacingFactor - 1);
}

/**
 * @param {string} text
 * @param {{width: number, height: number, fontFamily?: string, isBold?: boolean, lineSpacingFactor?: number,
 *          marginPercent?: number, minFontSize?: number, maxFontSize?: number,
 *          measure?: (text: string, fontFamily: string, size: number, bold: boolean) => number}} options
 *        `measure`: pomiar szerokości zamiast canvas (wspólny wzorzec shared/fixtures/autofit.json), bez pamięci podręcznej.
 */
export function optimalFontSize(text, options) {
  const {
    width, height, fontFamily = "Helvetica Neue", isBold = true, lineSpacingFactor = 1.15,
    marginPercent = 0.07, minFontSize = 14, maxFontSize = 260, measure,
  } = options;
  if (!text.trim()) return 48;
  if (width <= 50 || height <= 50) return 24;
  const key = [text, Math.round(width), Math.round(height), fontFamily, isBold, lineSpacingFactor, marginPercent, minFontSize, maxFontSize].join("\u0000");
  if (!measure && cache.has(key)) return cache.get(key);

  // 1% zapasu: pomiar w canvas i układ w DOM mogą się różnić o ułamek piksela.
  const usableWidth = Math.max(40, width * (1 - 2 * marginPercent)) * 0.99;
  const usableHeight = Math.max(40, height * (1 - 2 * marginPercent)) * 0.99;
  const words = text.split(/\s+/).filter(Boolean);
  let low = minFontSize, high = maxFontSize, best = minFontSize;

  for (let step = 0; step < 12; step++) {
    const mid = (low + high) / 2;
    if (mid < minFontSize) break;
    /** @type {(text: string) => number} */
    let measureWidth;
    if (measure) {
      measureWidth = (value) => measure(value, fontFamily, mid, isBold);
    } else {
      const ctx = measurer(cssFont(fontFamily, mid, isBold));
      measureWidth = (value) => ctx.measureText(value).width;
    }
    if (words.some((word) => measureWidth(word) > usableWidth)) {
      high = mid;
      continue;
    }
    if (wrappedHeight(text, measureWidth, mid, usableWidth, lineSpacingFactor) <= usableHeight) {
      best = mid;
      low = mid;
    } else {
      high = mid;
    }
  }
  const result = Math.max(minFontSize, Math.floor(best));
  if (measure) return result;
  if (cache.size >= CACHE_LIMIT) cache.clear();
  cache.set(key, result);
  return result;
}
