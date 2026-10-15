// @ts-check
// Koder kodów QR (tryb bajtowy, poziom korekcji M, wersje 1–10) bez zależności.
// Służy do pokazania adresu otpauth:// przy konfiguracji aplikacji uwierzytelniającej.
// Algorytm według ISO/IEC 18004 (układ jak w referencyjnej implementacji Nayuki).

/** [łączna liczba słów kodowych, słowa korekcji na blok, liczba bloków] dla poziomu M. */
const VERSIONS_M = [null, [26, 10, 1], [44, 16, 1], [70, 26, 1], [100, 18, 2], [134, 24, 2], [172, 16, 4],
  [196, 18, 4], [242, 22, 4], [292, 22, 5], [346, 26, 5]];
const ALIGNMENT = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
/** Bity reszty na końcu danych. */
const REMAINDER = [0, 0, 7, 7, 7, 7, 7, 0, 0, 0, 0];

// MARK: - Reed–Solomon w GF(256), wielomian 0x11D

/** @param {number} x @param {number} y */
function multiply(x, y) {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

/** @param {number} degree */
function divisor(degree) {
  const result = new Array(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < result.length; j++) {
      result[j] = multiply(result[j], root);
      if (j + 1 < result.length) result[j] ^= result[j + 1];
    }
    root = multiply(root, 0x02);
  }
  return result;
}

/** @param {number[]} data @param {number[]} div */
function remainder(data, div) {
  const result = new Array(div.length).fill(0);
  for (const b of data) {
    const factor = b ^ /** @type {number} */ (result.shift());
    result.push(0);
    div.forEach((coefficient, i) => { result[i] ^= multiply(coefficient, factor); });
  }
  return result;
}

// MARK: - Kodowanie

/**
 * Macierz modułów (true = ciemny) dla tekstu.
 * @param {string} text
 * @returns {boolean[][]}
 */
export function encodeQR(text) {
  const bytes = Array.from(new TextEncoder().encode(text));
  let version = 1;
  for (; version <= 10; version++) {
    const [total, ec, blocks] = /** @type {number[]} */ (VERSIONS_M[version]);
    const capacityBits = (total - ec * blocks) * 8;
    const needed = 4 + (version < 10 ? 8 : 16) + bytes.length * 8;
    if (needed <= capacityBits) break;
  }
  if (version > 10) throw new Error("text too long for QR");
  const [total, ecPerBlock, numBlocks] = /** @type {number[]} */ (VERSIONS_M[version]);
  const dataCapacity = total - ecPerBlock * numBlocks;

  // Bity: tryb bajtowy, długość, dane, terminator, dopełnienie.
  /** @type {number[]} */
  const bits = [];
  const push = (/** @type {number} */ value, /** @type {number} */ length) => { for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
  push(0b0100, 4);
  push(bytes.length, version < 10 ? 8 : 16);
  bytes.forEach((b) => push(b, 8));
  push(0, Math.min(4, dataCapacity * 8 - bits.length));
  push(0, (8 - (bits.length % 8)) % 8);
  for (let pad = 0xec; bits.length < dataCapacity * 8; pad ^= 0xec ^ 0x11) push(pad, 8);
  /** @type {number[]} */
  const data = [];
  for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));

  // Bloki, korekcja błędów i przeplot.
  const shortBlocks = numBlocks - (total % numBlocks);
  const shortLength = Math.floor(total / numBlocks);
  const div = divisor(ecPerBlock);
  /** @type {number[][]} */
  const blocks = [];
  for (let i = 0, k = 0; i < numBlocks; i++) {
    const dataLength = shortLength - ecPerBlock + (i < shortBlocks ? 0 : 1);
    const block = data.slice(k, k + dataLength);
    k += dataLength;
    const ec = remainder(block, div);
    if (i < shortBlocks) block.push(0);
    blocks.push(block.concat(ec));
  }
  /** @type {number[]} */
  const codewords = [];
  for (let i = 0; i < blocks[0].length; i++) {
    blocks.forEach((block, j) => { if (i !== shortLength - ecPerBlock || j >= shortBlocks) codewords.push(block[i]); });
  }

  // Wzory stałe.
  const size = version * 4 + 17;
  const modules = Array.from({ length: size }, () => new Array(size).fill(false));
  const fixed = Array.from({ length: size }, () => new Array(size).fill(false));
  const set = (/** @type {number} */ x, /** @type {number} */ y, /** @type {boolean} */ dark) => { modules[y][x] = dark; fixed[y][x] = true; };
  for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const distance = Math.max(Math.abs(dx), Math.abs(dy));
        const x = cx + dx, y = cy + dy;
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, distance !== 2 && distance !== 4);
      }
    }
  }
  const positions = /** @type {number[]} */ (ALIGNMENT[version]);
  positions.forEach((ay, i) => positions.forEach((ax, j) => {
    const last = positions.length - 1;
    if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) return;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }));
  const drawFormat = (/** @type {number} */ mask) => {
    const value = (0b00 << 3) | mask; // poziom M = 00
    let rem = value;
    for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    const formatBits = ((value << 10) | rem) ^ 0x5412;
    const bit = (/** @type {number} */ i) => ((formatBits >>> i) & 1) === 1;
    for (let i = 0; i <= 5; i++) set(8, i, bit(i));
    set(8, 7, bit(6));
    set(8, 8, bit(7));
    set(7, 8, bit(8));
    for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
    set(8, size - 8, true);
  };
  drawFormat(0);
  if (version >= 7) {
    let rem = version;
    for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
    const versionBits = (version << 12) | rem;
    for (let i = 0; i < 18; i++) {
      const dark = ((versionBits >>> i) & 1) === 1;
      const a = size - 11 + (i % 3), b = Math.floor(i / 3);
      set(a, b, dark);
      set(b, a, dark);
    }
  }

  // Dane zygzakiem od prawego dolnego rogu.
  const totalBits = codewords.length * 8 + REMAINDER[version];
  let index = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vertical = 0; vertical < size; vertical++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vertical : vertical;
        if (!fixed[y][x] && index < totalBits) {
          modules[y][x] = index < codewords.length * 8 && ((codewords[index >>> 3] >>> (7 - (index & 7))) & 1) === 1;
          index++;
        }
      }
    }
  }

  // Maska z najniższą karą.
  const maskFunctions = [
    (/** @type {number} */ x, /** @type {number} */ y) => (x + y) % 2 === 0, (_x, y) => y % 2 === 0, (x) => x % 3 === 0,
    (x, y) => (x + y) % 3 === 0, (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
    (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0, (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
    (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
  ];
  const applyMask = (/** @type {number} */ mask) => {
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!fixed[y][x] && maskFunctions[mask](x, y)) modules[y][x] = !modules[y][x];
  };
  let bestMask = 0, bestPenalty = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    applyMask(mask);
    drawFormat(mask);
    const value = penalty(modules);
    if (value < bestPenalty) { bestPenalty = value; bestMask = mask; }
    applyMask(mask);
  }
  applyMask(bestMask);
  drawFormat(bestMask);
  return modules;
}

/** Kara za trudne do odczytania układy (reguły N1–N4). @param {boolean[][]} m */
function penalty(m) {
  const size = m.length;
  let result = 0;
  const lines = [...m, ...m[0].map((_, x) => m.map((row) => row[x]))];
  for (const line of lines) {
    let run = 1;
    for (let i = 1; i <= size; i++) {
      if (i < size && line[i] === line[i - 1]) run++;
      else { if (run >= 5) result += 3 + run - 5; run = 1; }
    }
    const text = line.map((d) => (d ? "1" : "0")).join("");
    for (const pattern of ["10111010000", "00001011101"]) {
      for (let at = text.indexOf(pattern); at >= 0; at = text.indexOf(pattern, at + 1)) result += 40;
    }
  }
  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const c = m[y][x];
      if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) result += 3;
    }
  }
  const dark = m.flat().filter(Boolean).length;
  result += Math.floor(Math.abs((dark * 20) / (size * size) - 10)) * 10;
  return result;
}

/**
 * Kod QR jako SVG (z marginesem 4 modułów).
 * @param {string} text @param {number} [pixels]
 */
export function qrSVG(text, pixels = 220) {
  const modules = encodeQR(text);
  const size = modules.length + 8;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", `0 0 ${size} ${size}`);
  svg.setAttribute("width", String(pixels));
  svg.setAttribute("height", String(pixels));
  svg.setAttribute("shape-rendering", "crispEdges");
  let path = "";
  modules.forEach((row, y) => row.forEach((dark, x) => { if (dark) path += `M${x + 4} ${y + 4}h1v1h-1z`; }));
  const background = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  background.setAttribute("width", String(size));
  background.setAttribute("height", String(size));
  background.setAttribute("fill", "#fff");
  const foreground = document.createElementNS("http://www.w3.org/2000/svg", "path");
  foreground.setAttribute("d", path);
  foreground.setAttribute("fill", "#000");
  svg.append(background, foreground);
  return svg;
}
