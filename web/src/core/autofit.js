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
 * @param {string} text @param {string} font @param {number} size @param {number} width @param {number} lineSpacingFactor
 */
function wrappedHeight(text, font, size, width, lineSpacingFactor) {
  const ctx = measurer(font);
  let lines = 0;
  for (const paragraph of text.split("\n")) {
    const words = paragraph.split(/\s+/).filter(Boolean);
    if (!words.length) { lines++; continue; }
    let current = "";
    lines++;
    for (const word of words) {
      const candidate = current ? `${current} ${word}` : word;
      if (current && ctx.measureText(candidate).width > width) {
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
 *          marginPercent?: number, minFontSize?: number, maxFontSize?: number}} options
 */
export function optimalFontSize(text, options) {
  const {
    width, height, fontFamily = "Helvetica Neue", isBold = true, lineSpacingFactor = 1.15,
    marginPercent = 0.07, minFontSize = 14, maxFontSize = 260,
  } = options;
  if (!text.trim()) return 48;
  if (width <= 50 || height <= 50) return 24;
  const key = [text, Math.round(width), Math.round(height), fontFamily, isBold, lineSpacingFactor, marginPercent, minFontSize, maxFontSize].join("\u0000");
  if (cache.has(key)) return cache.get(key);

  const usableWidth = Math.max(40, width * (1 - 2 * marginPercent));
  const usableHeight = Math.max(40, height * (1 - 2 * marginPercent));
  const words = text.split(/\s+/).filter(Boolean);
  let low = minFontSize, high = maxFontSize, best = minFontSize;

  for (let step = 0; step < 12; step++) {
    const mid = (low + high) / 2;
    if (mid < minFontSize) break;
    const font = cssFont(fontFamily, mid, isBold);
    const ctx = measurer(font);
    if (words.some((word) => ctx.measureText(word).width > usableWidth)) {
      high = mid;
      continue;
    }
    if (wrappedHeight(text, font, mid, usableWidth, lineSpacingFactor) <= usableHeight) {
      best = mid;
      low = mid;
    } else {
      high = mid;
    }
  }
  const result = Math.max(minFontSize, Math.floor(best));
  if (cache.size >= CACHE_LIMIT) cache.clear();
  cache.set(key, result);
  return result;
}
