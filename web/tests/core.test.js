// @ts-check
import { test, equal, ok, fixture } from "./harness.js";
import { parseLyrics, slideTypeFrom } from "../src/core/lyrics.js";
import { foldString, searchFold, songMatches, matchingSnippet, SearchScope } from "../src/core/text.js";
import { transpose, isChordLine } from "../src/core/chords.js";

test("Wspólne pliki: podział na slajdy", async () => {
  for (const f of await fixture("lyrics.json")) {
    equal(parseLyrics(f.input), f.expected, f.name);
  }
});

test("Wspólne pliki: wyszukiwanie", async () => {
  for (const f of await fixture("search.json")) {
    equal(foldString(f.input), f.fold, `fold ${f.input}`);
    equal(searchFold(f.input), f.searchFold, `searchFold ${f.input}`);
  }
});

test("Wspólne pliki: transpozycja", async () => {
  for (const f of await fixture("transpose.json")) {
    equal(transpose(f.sheet, f.semitones), f.expected, f.sheet);
  }
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
