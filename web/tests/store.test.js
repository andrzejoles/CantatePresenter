// @ts-check
import { test, equal, ok } from "./harness.js";
import { Store } from "../src/app/store.js";
import { createSong, createPlan } from "../src/core/models.js";
import { decodeText, parseTextSong } from "../src/core/importText.js";

function sampleStore() {
  const a = createSong({ title: "Pierwsza", rawLyrics: "A1\n\nA2" });
  const b = createSong({ title: "Druga", rawLyrics: "[Zwrotka 1]\nB1\n\n[Refren]\nBR\n\n[Zwrotka 2]\nB2" });
  const c = createSong({ title: "Spoza planu", rawLyrics: "C1" });
  const plan = createPlan("Niedziela");
  plan.items = [{ id: "1", songId: a.id, note: "" }, { id: "2", songId: b.id, note: "" }];
  /** @type {string[]} */
  const saved = [];
  const store = new Store({ songs: [a, b, c], plans: [plan], persist: (kind) => saved.push(kind) });
  return { store, a, b, c, saved };
}

test("Koniec pieśni przechodzi do następnej pieśni z planu", () => {
  const { store, a } = sampleStore();
  store.present(a);
  store.nextSlide();
  equal(store.activeSlideIndex, 1);
  store.nextSlide();
  equal(store.activeSong?.title, "Druga");
  equal(store.activeSlideIndex, 0);
  store.prevSongInPlan();
  equal(store.activeSong?.title, "Pierwsza");
});

test("Po szybkim tekście plan idzie dalej od ostatniej pieśni z planu (N11)", () => {
  const { store, a, b } = sampleStore();
  store.present(a);
  store.presentQuickText("Ogłoszenie");
  equal(store.activeSong?.title, "Szybki tekst");
  ok(!store.songs.some((s) => s.title === "Szybki tekst"));
  store.nextSongInPlan();
  equal(store.activeSong?.id, b.id);
});

test("Zwrotka po numerze i refren", () => {
  const { store, b } = sampleStore();
  store.present(b);
  store.jumpToVerse(2);
  equal(store.currentLiveSlide?.text, "B2");
  store.jumpToChorus();
  equal(store.currentLiveSlide?.text, "BR");
});

test("Czarny ekran i ukrycie tekstu kasowane przy zmianie slajdu", () => {
  const { store, a } = sampleStore();
  store.present(a);
  store.toggleBlackScreen();
  ok(store.isBlackScreen);
  store.nextSlide();
  ok(!store.isBlackScreen);
});

test("Usunięcie pieśni zdejmuje ją z planów i zatrzymuje projekcję", () => {
  const { store, a } = sampleStore();
  store.present(a);
  store.deleteSong(a.id);
  ok(!store.isLive);
  equal(store.plans[0].items.length, 1);
});

test("Podgląd następnego slajdu sięga do następnej pieśni planu", () => {
  const { store, a } = sampleStore();
  store.present(a, 1);
  equal(store.nextSlidePreview?.text, "B1");
});

test("Plan: dodawanie, przesuwanie, usuwanie pozycji", () => {
  const { store, c } = sampleStore();
  store.addSongToPlan(c.id);
  store.movePlanItem(2, 0);
  equal(store.activePlan?.items[0].songId, c.id);
  store.removePlanItem(/** @type {any} */ (store.activePlan).items[0].id);
  equal(store.activePlan?.items.length, 2);
});

test("Edycja pieśni przelicza slajdy i zapisuje", () => {
  const { store, a, saved } = sampleStore();
  store.updateSong({ ...a, rawLyrics: "X\n\nY\n\nW" });
  equal(store.song(a.id)?.slides.length, 3);
  ok(saved.includes("songs"));
});

test("Import z innego źródła: zajęte identyfikatory dostają nowe (W8)", () => {
  const { store, a } = sampleStore();
  store.addSongs([{ ...a, title: "Kopia" }]);
  equal(store.songs.filter((s) => s.id === a.id).length, 1);
  equal(store.songs.length, 4);
});

test("Sortowanie biblioteki po polsku", () => {
  const store = new Store({ songs: ["Żywy", "Abba", "Łaska", "Lekko"].map((title) => createSong({ title })) });
  equal(store.filteredSongs("", () => true).map((s) => s.title), ["Abba", "Lekko", "Łaska", "Żywy"]);
});

test("Plik tekstowy: metadane i kodowanie Windows-1250", () => {
  const song = parseTextSong("Tytuł: Barka\nAutor: ks. S. Szmidt\nTonacja: D\n\nPan kiedyś stanął", "plik");
  equal([song.title, song.author, song.key, song.rawLyrics], ["Barka", "ks. S. Szmidt", "D", "Pan kiedyś stanął"]);
  equal(parseTextSong("Abba Ojcze\nTy podnosisz mnie", "x").title, "Abba Ojcze");
  // „Łódź” w Windows-1250
  equal(decodeText(new Uint8Array([0xa3, 0xf3, 0x64, 0x9f])), "Łódź");
  equal(decodeText(new TextEncoder().encode("﻿Zażółć")), "Zażółć");
});
