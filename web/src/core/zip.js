// @ts-check
// Minimalny ZIP bez zależności: zapis (deflate przez CompressionStream) i odczyt (metody 0 i 8).
// Wystarcza do kopii .cantatebackup tworzonych przez macOS (ditto -c -k) i przez wersję webową.

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

/** @param {Uint8Array} data */
export function crc32(data) {
  let crc = 0xffffffff;
  for (let i = 0; i < data.length; i++) crc = CRC_TABLE[(crc ^ data[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** @param {Uint8Array} data @param {"deflate-raw"} format @param {boolean} compress */
async function transform(data, format, compress) {
  const stream = new Blob([data]).stream().pipeThrough(compress ? new CompressionStream(format) : new DecompressionStream(format));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Data i czas w formacie DOS. @param {Date} date */
function dosDateTime(date) {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
  const day = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time, day };
}

/**
 * Tworzy archiwum ZIP z plików (ścieżka → zawartość).
 * @param {{path: string, data: Uint8Array | string}[]} files
 * @param {Date} [date]
 * @returns {Promise<Blob>}
 */
export async function createZip(files, date = new Date()) {
  const encoder = new TextEncoder();
  const { time, day } = dosDateTime(date);
  /** @type {BlobPart[]} */
  const parts = [];
  /** @type {Uint8Array[]} */
  const central = [];
  let offset = 0;

  for (const file of files) {
    const name = encoder.encode(file.path);
    const raw = typeof file.data === "string" ? encoder.encode(file.data) : file.data;
    const compressed = await transform(raw, "deflate-raw", true);
    const useDeflate = compressed.length < raw.length;
    const body = useDeflate ? compressed : raw;
    const crc = crc32(raw);

    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true);
    local.setUint16(4, 20, true);
    local.setUint16(6, 0x0800, true); // nazwy w UTF-8
    local.setUint16(8, useDeflate ? 8 : 0, true);
    local.setUint16(10, time, true);
    local.setUint16(12, day, true);
    local.setUint32(14, crc, true);
    local.setUint32(18, body.length, true);
    local.setUint32(22, raw.length, true);
    local.setUint16(26, name.length, true);
    parts.push(local.buffer, name, body);

    const entry = new DataView(new ArrayBuffer(46));
    entry.setUint32(0, 0x02014b50, true);
    entry.setUint16(4, 20, true);
    entry.setUint16(6, 20, true);
    entry.setUint16(8, 0x0800, true);
    entry.setUint16(10, useDeflate ? 8 : 0, true);
    entry.setUint16(12, time, true);
    entry.setUint16(14, day, true);
    entry.setUint32(16, crc, true);
    entry.setUint32(20, body.length, true);
    entry.setUint32(24, raw.length, true);
    entry.setUint16(28, name.length, true);
    entry.setUint32(42, offset, true);
    central.push(new Uint8Array(entry.buffer), name);

    offset += 30 + name.length + body.length;
  }

  const centralSize = central.reduce((sum, part) => sum + part.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, files.length, true);
  end.setUint16(10, files.length, true);
  end.setUint32(12, centralSize, true);
  end.setUint32(16, offset, true);
  return new Blob([...parts, ...central, end.buffer], { type: "application/zip" });
}

/** Największe akceptowane archiwum i plik po rozpakowaniu (ochrona przed „bombą ZIP”). */
export const MAX_ARCHIVE_SIZE = 200 * 1024 * 1024;
export const MAX_ENTRY_SIZE = 100 * 1024 * 1024;

/**
 * Odczytuje pliki z archiwum ZIP (pomija katalogi i metadane macOS z __MACOSX).
 * @param {Blob} blob
 * @returns {Promise<Map<string, Uint8Array>>}
 */
export async function readZip(blob) {
  if (blob.size > MAX_ARCHIVE_SIZE) throw new Error("archive too large");
  const bytes = new Uint8Array(await blob.arrayBuffer());
  const view = new DataView(bytes.buffer);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("not a zip archive");
  const count = view.getUint16(eocd + 10, true);
  let pointer = view.getUint32(eocd + 16, true);
  const decoder = new TextDecoder();
  /** @type {Map<string, Uint8Array>} */
  const files = new Map();

  for (let n = 0; n < count; n++) {
    if (pointer + 46 > bytes.length || view.getUint32(pointer, true) !== 0x02014b50) throw new Error("corrupt zip directory");
    const method = view.getUint16(pointer + 10, true);
    const compressedSize = view.getUint32(pointer + 20, true);
    const size = view.getUint32(pointer + 24, true);
    const nameLength = view.getUint16(pointer + 28, true);
    const extraLength = view.getUint16(pointer + 30, true);
    const commentLength = view.getUint16(pointer + 32, true);
    const localOffset = view.getUint32(pointer + 42, true);
    const name = decoder.decode(bytes.subarray(pointer + 46, pointer + 46 + nameLength));
    pointer += 46 + nameLength + extraLength + commentLength;

    if (name.endsWith("/") || name.startsWith("__MACOSX/") || name.includes("/._")) continue;
    if (size > MAX_ENTRY_SIZE) throw new Error("zip entry too large");
    if (view.getUint32(localOffset, true) !== 0x04034b50) throw new Error("corrupt zip entry");
    const start = localOffset + 30 + view.getUint16(localOffset + 26, true) + view.getUint16(localOffset + 28, true);
    const body = bytes.subarray(start, start + compressedSize);
    if (method === 0) files.set(name, body);
    else if (method === 8) files.set(name, await transform(body, "deflate-raw", false));
    else throw new Error(`unsupported zip method ${method}`);
  }
  return files;
}
