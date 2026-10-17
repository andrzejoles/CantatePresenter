// @ts-check
import { test, equal, ok, fixture } from "./harness.js";
import { parseLyrics, slideTypeFrom } from "../src/core/lyrics.js";
import { foldString, searchFold, songMatches, matchingSnippet, SearchScope } from "../src/core/text.js";
import { transpose, isChordLine } from "../src/core/chords.js";
import { linesForSlide, splitConcatenatedChords } from "../src/core/chordsheet.js";
import { processAndDeduplicate, songsToCommit } from "../src/core/dedup.js";
import { optimalFontSize } from "../src/core/autofit.js";

test("Wspólne pliki: podział na slajdy", async () => {
  for (const f of await fixture("lyrics.json")) {
    equal(parseLyrics(f.input), f.expected, f.name);
  }
});

test("Wspólne pliki: Auto-Fit (stały pomiar szerokości)", async () => {
  const { cases } = await fixture("autofit.json");
  /** @param {string} text @param {string} _font @param {number} size */
  const measure = (text, _font, size) => text.length * size * 0.6;
  for (const c of cases) {
    equal(optimalFontSize(c.text, { width: c.width, height: c.height, lineSpacingFactor: c.lineSpacingFactor, marginPercent: c.marginPercent, measure }), c.expected, c.name);
  }
});

test("Wspólne pliki: wyszukiwanie", async () => {
  for (const f of await fixture("search.json")) {
    equal(foldString(f.input), f.fold, `fold ${f.input}`);
    equal(searchFold(f.input), f.searchFold, `searchFold ${f.input}`);
  }
});

test("Wspólne pliki: duplikaty przy imporcie", async () => {
  /** @param {string} key @param {any[]} args */
  const t = (key, ...args) => args.reduce((text, value, i) => text.replace(`{${i}}`, String(value)), key);
  for (const f of await fixture("dedup.json")) {
    const report = processAndDeduplicate(f.incoming, f.existing, t);
    const e = f.expected;
    equal(report.uniqueSongs.map((s) => s.id), e.unique, f.name);
    equal(report.duplicateRecords.map((r) => ({ primary: r.primarySong.id, duplicate: r.duplicateSong.id, score: r.similarityScore, reason: r.reason })),
      e.duplicates.map((/** @type {any} */ d) => ({ ...d, reason: t(d.reason, d.score) })), f.name);
    equal(report.existingCollisions.map((r) => ({ library: r.primarySong.id, incoming: r.duplicateSong.id, score: r.similarityScore, skip: r.shouldSkipDuplicate, reason: r.reason })),
      e.collisions.map((/** @type {any} */ c) => ({ ...c, reason: t(c.reason, c.score) })), f.name);
    equal(songsToCommit(report).map((s) => s.title), e.commit, f.name);
    const none = (/** @type {{id: string}[]} */ records) => new Map(records.map((r) => [r.id, false]));
    equal(songsToCommit(report, none(report.duplicateRecords), none(report.existingCollisions)).map((s) => s.title), e.commitNothingSkipped, f.name);
  }
});

test("Wspólne pliki: transpozycja", async () => {
  for (const f of await fixture("transpose.json")) {
    equal(transpose(f.sheet, f.semitones), f.expected, f.sheet);
  }
});

test("Wspólne pliki: chwyty dla muzyków", async () => {
  for (const f of await fixture("chordsheet.json")) {
    const result = linesForSlide(f.slide, f.sheet, f.semitones ?? 0);
    equal(result, { lines: f.expected.lines.map((/** @type {any} */ l) => ({ chords: l.chords ?? null, text: l.text })), borrowedFrom: f.expected.borrowedFrom ?? null }, f.name);
  }
  equal(splitConcatenatedChords("Afis"), ["A", "fis"]);
  equal(splitConcatenatedChords("Ala"), null);
});

test("Typy slajdów: kody, stare polskie nazwy, nieznane jako custom", () => {
  equal(slideTypeFrom("chorus"), "chorus");
  equal(slideTypeFrom("Refren"), "chorus");
  equal(slideTypeFrom("Coś nowego"), "custom");
});

test("Dopasowanie pieśni w zakresach i fragment tekstu", () => {
  const song = { title: "Barka", author: "ks. Stanisław Szmidt", tags: ["Oazowe"], rawLyrics: "Pan kiedyś stanął nad brzegiem,\nSzukał ludzi" };
  ok(songMatches(song, "stanal nad"));
  ok(!songMatches(song, "stanal nad", SearchScope.titleOnly));
  ok(songMatches(song, "szmidt", SearchScope.authorOnly));
  ok(songMatches(song, "oazowe"));
  equal(matchingSnippet(song, "szukal"), "Szukał ludzi");
  equal(matchingSnippet(song, "barka"), null);
});

test("Linia akordowa a linia tekstu", () => {
  ok(isChordLine("C  G  a  F | x2"));
  ok(!isChordLine("A to jest tekst"));
});
