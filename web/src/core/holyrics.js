// @ts-check
// Import bibliotek Holyrics: odpowiednik HolyricsJavaDeserializer i HolyricsImporter z wersji macOS (wzorzec).
// .mufl / .muf to Java Object Serialization Stream (AC ED 00 05) z obiektami com.limagiran.holyrics.model.Music;
// obsługiwane są też eksporty JSON, XML i tekst ze znacznikami oraz archiwa .zip / .hly / .holyrics.
// Zgodność pilnują shared/fixtures/holyrics.json (pliki z data/holyrics_samples).

import { readZip } from "./zip.js";
import { decodeText } from "./importText.js";

const TC = { NULL: 0x70, REFERENCE: 0x71, CLASSDESC: 0x72, OBJECT: 0x73, STRING: 0x74, ARRAY: 0x75, CLASS: 0x76, BLOCKDATA: 0x77,
  ENDBLOCKDATA: 0x78, RESET: 0x79, BLOCKDATALONG: 0x7a, LONGSTRING: 0x7c, PROXYCLASSDESC: 0x7d, ENUM: 0x7e };
const BASE_WIRE_HANDLE = 0x7e0000;
/** Limit zagnieżdżenia (W6): uszkodzony plik nie może przepełnić stosu. */
const MAX_DEPTH = 32;

/** @typedef {{title: string, author: string, artist: string, lyrics: string, key: string, note: string, formatting: string, language: string}} RawMusicRecord */
/** @typedef {{title: string, author: string, key: string, tags: string[], rawLyrics: string}} HolyricsSong */

const MUSIC = Symbol("music");
const emptyRecord = () => /** @type {RawMusicRecord} */ ({ title: "", author: "", artist: "", lyrics: "", key: "", note: "", formatting: "", language: "" });
/** @param {any} value @returns {value is RawMusicRecord} */
const isRecord = (value) => Boolean(value && value[MUSIC]);

class ClassDescriptor {
  /** @param {string} name @param {number} flags @param {{name: string, type: string}[]} fields @param {unknown} superClass */
  constructor(name, flags, fields, superClass) {
    this.name = name;
    this.flags = flags;
    this.fields = fields;
    this.superClass = superClass;
  }
}

export class HolyricsError extends Error {}

/** @param {Uint8Array} bytes */
export const isJavaSerializedStream = (bytes) => bytes.length >= 4 && bytes[0] === 0xac && bytes[1] === 0xed && bytes[2] === 0x00 && bytes[3] === 0x05;

/** Czytnik strumienia: każdy odczyt sprawdza granice i rzuca błąd zamiast czytać za końcem (W6). */
class JavaStream {
  /** @param {Uint8Array} bytes */
  constructor(bytes) {
    this.bytes = bytes;
    this.pos = 0;
    this.depth = 0;
    /** @type {unknown[]} */
    this.handles = [];
    this.utf8 = new TextDecoder("utf-8");
  }

  get remaining() { return this.bytes.length - this.pos; }

  /** @param {number} count */
  require(count) {
    if (!(count >= 0 && count <= this.remaining)) throw new HolyricsError(`Przedwczesny koniec danych na pozycji ${this.pos}`);
  }

  u8() { this.require(1); return this.bytes[this.pos++]; }
  u16() { this.require(2); const v = (this.bytes[this.pos] << 8) | this.bytes[this.pos + 1]; this.pos += 2; return v; }
  u32() { this.require(4); const b = this.bytes, p = this.pos; this.pos += 4; return ((b[p] << 24) >>> 0) + (b[p + 1] << 16) + (b[p + 2] << 8) + b[p + 3]; }
  i64() {
    this.require(8);
    let value = 0n;
    for (let i = 0; i < 8; i++) value = (value << 8n) | BigInt(this.bytes[this.pos + i]);
    this.pos += 8;
    return BigInt.asIntN(64, value);
  }
  /** @param {number} count */
  skip(count) { this.require(count); this.pos += count; }
  /** @param {number} length */
  string(length) {
    this.require(length);
    const text = this.utf8.decode(this.bytes.subarray(this.pos, this.pos + length));
    this.pos += length;
    return text;
  }
  utf() { return this.string(this.u16()); }
  longUTF() {
    const length = this.i64();
    if (length < 0n || length > BigInt(this.remaining)) throw new HolyricsError(`Nieprawidłowa długość ${length} na pozycji ${this.pos}`);
    return this.string(Number(length));
  }

  /** @param {unknown} value */
  assign(value) { this.handles.push(value); return this.handles.length - 1; }
  /** @param {number} index @param {unknown} value */
  set(index, value) { if (index < this.handles.length) this.handles[index] = value; }

  /** Dane bloku aż do TC_ENDBLOCKDATA; obiekty po drodze są czytane. @param {boolean} collect */
  blockContents(collect) {
    /** @type {unknown[]} */
    const elements = [];
    for (;;) {
      this.require(1);
      const tag = this.bytes[this.pos];
      if (tag === TC.ENDBLOCKDATA) { this.pos++; return elements; }
      if (tag === TC.BLOCKDATA) { this.pos++; this.skip(this.u8()); }
      else if (tag === TC.BLOCKDATALONG) { this.pos++; this.skip(this.u32()); }
      else {
        const element = this.content();
        if (collect && element !== null && element !== undefined) elements.push(element);
      }
    }
  }

  /** @returns {unknown} */
  content() {
    if (this.depth >= MAX_DEPTH) throw new HolyricsError(`Zbyt głębokie zagnieżdżenie danych na pozycji ${this.pos}`);
    this.depth++;
    try {
      return this.readTagged();
    } finally {
      this.depth--;
    }
  }

  readTagged() {
    const tc = this.u8();
    switch (tc) {
      case TC.NULL: return null;
      case TC.REFERENCE: {
        const ref = this.u32();
        const index = ref - BASE_WIRE_HANDLE;
        if (ref < BASE_WIRE_HANDLE || index >= this.handles.length) throw new HolyricsError(`Nieprawidłowy uchwyt referencji ${ref}`);
        return this.handles[index];
      }
      case TC.STRING: { const h = this.assign(null); const s = this.utf(); this.set(h, s); return s; }
      case TC.LONGSTRING: { const h = this.assign(null); const s = this.longUTF(); this.set(h, s); return s; }
      case TC.CLASSDESC: {
        const h = this.assign(null);
        const name = this.utf();
        this.i64();
        const flags = this.u8();
        const count = this.u16();
        if (count * 3 > this.remaining) throw new HolyricsError(`Nieprawidłowa długość ${count} na pozycji ${this.pos}`);
        /** @type {{name: string, type: string}[]} */
        const fields = [];
        for (let i = 0; i < count; i++) {
          const type = String.fromCharCode(this.u8());
          const fieldName = this.utf();
          if (type === "[" || type === "L") this.content();
          fields.push({ name: fieldName, type });
        }
        // Adnotacje klasy aż do TC_ENDBLOCKDATA.
        for (;;) {
          this.require(1);
          const tag = this.bytes[this.pos];
          if (tag === TC.ENDBLOCKDATA) { this.pos++; break; }
          if (tag === TC.BLOCKDATA) { this.pos++; this.skip(this.u8()); } else this.pos++;
        }
        const descriptor = new ClassDescriptor(name, flags, fields, this.content());
        this.set(h, descriptor);
        return descriptor;
      }
      case TC.OBJECT: return this.object(tc);
      case TC.ARRAY: {
        this.content();
        const h = this.assign(null);
        const length = this.u32();
        if (length > this.remaining) throw new HolyricsError(`Nieprawidłowa długość ${length} na pozycji ${this.pos}`);
        /** @type {unknown[]} */
        const array = [];
        this.set(h, array);
        for (let i = 0; i < length; i++) array.push(this.content());
        return array;
      }
      case TC.BLOCKDATA: this.skip(this.u8()); return null;
      case TC.BLOCKDATALONG: this.skip(this.u32()); return null;
      case TC.ENDBLOCKDATA: return null;
      case TC.RESET: this.handles = []; return null;
      default: throw new HolyricsError(`Nieoczekiwany znacznik 0x${tc.toString(16).padStart(2, "0").toUpperCase()} na pozycji ${this.pos - 1}`);
    }
  }

  /** @param {number} tc */
  object(tc) {
    const descriptor = this.content();
    if (!(descriptor instanceof ClassDescriptor)) throw new HolyricsError(`Nieoczekiwany znacznik 0x${tc.toString(16)} na pozycji ${this.pos}`);
    const h = this.assign(null);
    /** @type {Record<string, unknown>} */
    const object = { _class: descriptor.name };
    this.set(h, object);
    /** @type {ClassDescriptor[]} */
    const hierarchy = [];
    /** @type {unknown} */
    let current = descriptor;
    while (current instanceof ClassDescriptor && hierarchy.length < MAX_DEPTH) {
      hierarchy.push(current);
      current = current.superClass;
    }
    hierarchy.reverse();
    const record = descriptor.name.includes("Music") ? Object.assign(emptyRecord(), { [MUSIC]: true }) : null;

    for (const cls of hierarchy) {
      for (const field of cls.fields) {
        switch (field.type) {
          case "Z": object[field.name] = this.u8() !== 0; break;
          case "B": object[field.name] = this.u8(); break;
          case "C": object[field.name] = this.u16(); break;
          case "S": object[field.name] = (this.u16() << 16) >> 16; break;
          case "I": object[field.name] = this.u32() | 0; break;
          case "J": object[field.name] = this.i64(); break;
          case "F": this.skip(4); break;
          case "D": this.skip(8); break;
        }
      }
      for (const field of cls.fields) {
        if (field.type !== "[" && field.type !== "L") continue;
        const value = this.content();
        if (typeof value === "string") {
          object[field.name] = value;
          if (record) {
            switch (field.name) {
              case "title": case "author": case "artist": case "lyrics": case "formatting": case "note": case "language":
                record[field.name] = value; break;
              // Tonacja, jeśli eksport ją zawiera (N5).
              case "key": case "tone": case "tom": record.key = value; break;
            }
          }
        } else if (value !== null && value !== undefined) {
          object[field.name] = value;
        }
      }
      if (cls.flags & 0x01) {
        if (cls.name === "java.util.ArrayList") {
          const elements = this.blockContents(true);
          object._elements = elements;
          this.set(h, object);
          return elements;
        }
        this.blockContents(false);
      }
    }
    if (record) { this.set(h, record); return record; }
    this.set(h, object);
    return object;
  }
}

/** @param {Record<string, unknown>} dict @returns {RawMusicRecord | null} */
function recordFromDict(dict) {
  if (typeof dict.title !== "string") return null;
  const text = (/** @type {unknown} */ v) => (typeof v === "string" ? v : "");
  return { ...emptyRecord(), title: dict.title, author: text(dict.author), artist: text(dict.artist), lyrics: text(dict.lyrics),
    formatting: text(dict.formatting), note: text(dict.note), language: text(dict.language) };
}

/** Rekordy Music ze strumienia Java. @param {Uint8Array} bytes @returns {RawMusicRecord[]} */
export function deserializeMusicRecords(bytes) {
  if (bytes.length < 4) throw new HolyricsError("Błąd nagłówka: Plik jest za krótki");
  if (!isJavaSerializedStream(bytes)) throw new HolyricsError("Błąd nagłówka: Nieprawidłowy nagłówek Java ObjectStream (oczekiwano AC ED 00 05)");
  const stream = new JavaStream(bytes);
  stream.pos = 4;
  /** @type {RawMusicRecord[]} */
  const records = [];
  while (stream.pos < bytes.length) {
    const value = stream.content();
    if (value === null || value === undefined) continue;
    if (Array.isArray(value)) {
      if (value.every(isRecord)) records.push(...value);
    } else if (isRecord(value)) {
      records.push(value);
    } else if (typeof value === "object" && !(value instanceof ClassDescriptor)) {
      const dict = /** @type {Record<string, unknown>} */ (value);
      const elements = dict._elements;
      if (Array.isArray(elements) && elements.every(isRecord)) records.push(.../** @type {RawMusicRecord[]} */ (elements));
      else {
        const record = recordFromDict(dict);
        if (record) records.push(record);
      }
    }
  }
  return records;
}

// MARK: - Importer

/** Znaczniki Holyrics ##(Verse 1) → [Zwrotka 1] itd. */
const MARKERS = /** @type {[RegExp, string][]} */ ([
  [/##\(Verse\s*(\d+)\)/gi, "[Zwrotka $1]"],
  [/##\(Verse\)/gi, "[Zwrotka]"],
  [/##\(Chorus\s*(\d*)\)/gi, "[Refren]"],
  [/##\(Bridge\s*(\d*)\)/gi, "[Bridge]"],
  [/##\(Coda\s*(\d*)\)/gi, "[Coda]"],
  [/##\(Intro\s*(\d*)\)/gi, "[Wstęp]"],
  [/##\((Outro|Ending)\s*(\d*)\)/gi, "[Zakończenie]"],
  [/##\(Pre-Chorus\s*(\d*)\)/gi, "[Przed-refren]"],
  [/##\((Tag|Interlude)\s*(\d*)\)/gi, "[Przejście]"],
  [/##\(([^)]+)\)/gi, "[$1]"],
]);

/** @param {string} text */
export function translateVerseMarkers(text) {
  let result = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  for (const [pattern, replacement] of MARKERS) result = result.replace(pattern, replacement);
  return result;
}

const trimAll = (/** @type {string} */ s) => s.replace(/^[\s\u0085]+|[\s\u0085]+$/g, "");
const trimSpaces = (/** @type {string} */ s) => s.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");

/** @param {RawMusicRecord} record @returns {HolyricsSong} */
export function songFromRecord(record) {
  const title = trimAll(record.title) || "Pieśń Holyrics";
  const author = trimAll(record.author) || trimAll(record.artist);
  const tags = ["Import Holyrics"];
  if (record.note) tags.push(trimAll(record.note));
  return { title, author, key: record.key, tags, rawLyrics: translateVerseMarkers(record.lyrics) };
}

/** @param {string} line */
const valueAfterColon = (line) => (line.includes(":") ? trimAll(line.slice(line.indexOf(":") + 1)) : "");

/** Jedna pieśń z tekstu ze znacznikami @title:, @autor: itd. @param {string} text @param {string} fallbackTitle @returns {HolyricsSong} */
export function parseSingleSong(text, fallbackTitle) {
  const lines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split(/[\n\u000B\u000C\u0085\u2028\u2029]/);
  let title = "", author = "", key = "";
  const tags = ["Import Holyrics"];
  /** @type {string[]} */
  const lyrics = [];
  let inLyrics = false;
  const starts = (/** @type {string} */ lower, /** @type {string[]} */ prefixes) => prefixes.some((p) => lower.startsWith(p));
  for (const rawLine of lines) {
    const line = trimSpaces(rawLine);
    if (!line) { if (inLyrics) lyrics.push(""); continue; }
    const lower = line.toLowerCase();
    if (starts(lower, ["@title:", "@nome:", "@titulo:", "title:", "título:", "nome:"])) title = valueAfterColon(line);
    else if (starts(lower, ["@author:", "@autor:", "@artist:", "@artista:", "author:", "autor:", "artist:"])) author = valueAfterColon(line);
    else if (starts(lower, ["@key:", "@tom:", "key:", "tom:"])) key = valueAfterColon(line);
    else if (starts(lower, ["@tags:", "@tag:", "tags:"])) tags.push(...valueAfterColon(line).split(",").map(trimSpaces).filter(Boolean));
    else if (starts(lower, ["@ccli:", "@copyright:", "@order:", "@ordem:"])) continue;
    else { inLyrics = true; lyrics.push(rawLine); }
  }
  return { title: title || fallbackTitle, author, key, tags, rawLyrics: translateVerseMarkers(trimAll(lyrics.join("\n"))) };
}

/** @param {string} text */
function splitMultiSong(text) {
  for (const delimiter of ["\n===\n", "\n===\r\n", "\n---song---\n", "\n[SONG]\n", "\n[MUSIC]\n", "\n{SONG}\n"]) {
    if (text.includes(delimiter)) return text.split(delimiter).map(trimAll).filter(Boolean);
  }
  return [text];
}

/** @param {string} text @returns {HolyricsSong[] | null} */
function parseJSON(text) {
  let data;
  try { data = JSON.parse(text); } catch { return null; }
  const isDicts = (/** @type {unknown} */ v) => Array.isArray(v) && v.every((x) => x && typeof x === "object" && !Array.isArray(x));
  /** @type {any[]} */
  let dicts = [];
  if (isDicts(data)) dicts = data;
  else if (data && typeof data === "object" && !Array.isArray(data)) {
    dicts = isDicts(data.songs) ? data.songs : isDicts(data.musics) ? data.musics : isDicts(data.items) ? data.items : [data];
  }
  if (!dicts.length) return null;
  const str = (/** @type {unknown[]} */ ...values) => /** @type {string} */ (values.find((v) => typeof v === "string") ?? "");
  /** @type {HolyricsSong[]} */
  const songs = [];
  for (const d of dicts) {
    const title = str(d.title, d.name, d.nome, d.titulo);
    let lyrics = str(d.lyrics, d.letra, d.text);
    if (!lyrics && Array.isArray(d.slides) && d.slides.every((/** @type {unknown} */ s) => typeof s === "string")) lyrics = d.slides.join("\n\n");
    else if (!lyrics && isDicts(d.paragraphs)) lyrics = d.paragraphs.map((/** @type {any} */ p) => p.text).filter((/** @type {unknown} */ t) => typeof t === "string").join("\n\n");
    if (title || lyrics) {
      songs.push({ title: title || "Bez tytułu", author: str(d.author, d.artist, d.artista, d.autor), key: str(d.key, d.tone, d.tom),
        tags: ["Import Holyrics JSON"], rawLyrics: translateVerseMarkers(lyrics) });
    }
  }
  return songs.length ? songs : null;
}

const SONG_ELEMENTS = new Set(["song", "music", "musica"]);
const FIELD_ALIASES = /** @type {Record<string, string>} */ ({ title: "title", nome: "title", titulo: "title", author: "author", artist: "author",
  autor: "author", artista: "author", key: "key", tom: "key", tone: "key", lyrics: "lyrics", letra: "lyrics" });

/** XML Holyrics / OpenSong (jak HolyricsXMLReader: pierwsze niepuste pole wygrywa). @param {string} xml @param {string} fallbackTitle */
function parseXML(xml, fallbackTitle) {
  const doc = new DOMParser().parseFromString(xml, "application/xml");
  if (doc.getElementsByTagName("parsererror").length) return [];
  /** @type {Record<string, string>[]} */
  const records = [];
  /** @type {Record<string, string>} */
  const documentFields = {};
  /** @param {Element} element @param {Record<string, string> | null} current */
  const walk = (element, current) => {
    const name = element.localName.toLowerCase();
    if (SONG_ELEMENTS.has(name)) {
      /** @type {Record<string, string>} */
      const record = {};
      for (const child of element.children) walk(child, record);
      records.push(record);
      return;
    }
    const alias = FIELD_ALIASES[name];
    if (alias) {
      const value = trimAll(element.textContent ?? "");
      const target = current ?? documentFields;
      if (!target[alias]) target[alias] = value;
    }
    for (const child of element.children) walk(child, current);
  };
  if (doc.documentElement) walk(doc.documentElement, null);
  const list = records.length ? records : Object.keys(documentFields).length ? [documentFields] : [];
  return list.filter((f) => f.title || f.lyrics).map((f) => ({
    title: f.title || fallbackTitle, author: f.author ?? "", key: f.key ?? "", tags: ["Import Holyrics XML"], rawLyrics: translateVerseMarkers(f.lyrics ?? ""),
  }));
}

/** Tekst eksportu Holyrics: JSON, XML, kilka pieśni z separatorami albo jedna. @param {string} raw @param {string} fallbackTitle */
export function parseHolyricsText(raw, fallbackTitle = "Pieśń Holyrics") {
  const text = trimAll(raw);
  if (!text) return [];
  if (text.startsWith("{") || text.startsWith("[")) {
    const songs = parseJSON(text);
    if (songs) return songs;
  }
  if (text.startsWith("<")) {
    const songs = parseXML(text, fallbackTitle);
    if (songs.length) return songs;
  }
  const blocks = splitMultiSong(text);
  if (blocks.length > 1) {
    const songs = blocks.map((b) => parseSingleSong(b, fallbackTitle)).filter((s) => s.title && s.rawLyrics);
    if (songs.length) return songs;
  }
  return [parseSingleSong(text, fallbackTitle)];
}

export const HOLYRICS_EXTENSIONS = new Set(["muf", "mufl", "hly", "holyrics", "zip"]);

/**
 * Pieśni z pliku Holyrics (bez deduplikacji): archiwum, strumień Java albo tekst.
 * @param {Uint8Array} bytes @param {string} fileName @returns {Promise<HolyricsSong[]>}
 */
export async function readHolyricsFile(bytes, fileName) {
  const extension = fileName.split(".").pop()?.toLowerCase() ?? "";
  if (["zip", "hly", "holyrics"].includes(extension)) {
    try {
      const files = await readZip(new Blob([bytes]));
      /** @type {HolyricsSong[]} */
      const songs = [];
      for (const [path, data] of files) {
        const inner = path.split(".").pop()?.toLowerCase() ?? "";
        if (["muf", "mufl", "txt", "json", "xml"].includes(inner)) songs.push(...(await readHolyricsFile(data, path.split("/").pop() ?? path)));
      }
      if (songs.length) return songs;
    } catch {
      // Nie ZIP: dalej jak zwykły plik.
    }
  }
  if (isJavaSerializedStream(bytes)) {
    try {
      const records = deserializeMusicRecords(bytes);
      if (records.length) return records.map(songFromRecord);
    } catch {
      // Uszkodzony strumień: tak jak w macOS próba odczytu jako tekst.
    }
  }
  return parseHolyricsText(decodeText(bytes), fileName.replace(/\.[^.]+$/, ""));
}
