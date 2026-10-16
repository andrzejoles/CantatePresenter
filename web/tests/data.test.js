// @ts-check
import { test, equal, ok, fixture } from "./harness.js";
import { normalizeSong, normalizePlan, normalizeSettings, parseDate, createSong, copyrightNotice } from "../src/core/models.js";
import { createZip, readZip, crc32 } from "../src/core/zip.js";
import { createBackup, readBackup, backupFileName, BackupError } from "../src/core/backup.js";
import { keyboardAction, MAC_KEY_CODES } from "../src/core/keyboard.js";
import { DEFAULT_SHORTCUTS } from "../src/core/models.js";
import { APP_VERSION } from "../src/version.js";

test("Wspólne pliki: skróty klawiszowe", async () => {
  for (const f of await fixture("keyboard.json")) {
    const action = keyboardAction({ macCode: f.macCode, characters: f.characters, command: f.command, shortcuts: { ...DEFAULT_SHORTCUTS }, context: f.context });
    equal(action, f.expected, f.note);
  }
});

test("Kody klawiszy: strzałki, spacja, litery jak w macOS", () => {
  equal(MAC_KEY_CODES.Space, 49);
  equal(MAC_KEY_CODES.ArrowLeft, 123);
  equal(MAC_KEY_CODES.KeyB, 11);
  equal(MAC_KEY_CODES.PageDown, 121);
});

test("Daty: ISO z ułamkami, liczby od 2001 roku, błędne", () => {
  equal(parseDate("2026-10-15T06:04:51.250Z"), "2026-10-15T06:04:51Z");
  equal(parseDate(0), "2001-01-01T00:00:00Z");
  ok(/^\d{4}-\d\d-\d\dT/.test(parseDate("nonsense")));
});

test("Pieśń: stare typy slajdów, brakujące pola, numer CCLI jako liczba, nieznane pola zostają", () => {
  const song = normalizeSong({ title: "T", rawLyrics: "A\n\nB", ccliNumber: 22025, futureField: 1, slides: [{ type: "Refren", label: "Refren", text: "x" }] });
  equal(song.slides[0].type, "chorus");
  equal(song.ccliNumber, "22025");
  equal(/** @type {any} */ (song).futureField, 1);
  equal(song.author, "");
  const noSlides = normalizeSong({ title: "S", rawLyrics: "A\n\nB" });
  equal(noSlides.slides.map((s) => s.label), ["Zwrotka 1", "Zwrotka 2"]);
  ok(/^[0-9A-F-]{36}$/.test(createSong({ title: "Nowa" }).id));
});

test("Plan: pozycje bez songId pomijane", () => {
  const plan = normalizePlan({ name: "P", items: [{ songId: "7b1e7c4c-8e43-4e8b-9c1b-2d4a0f1e2a11" }, { note: "x" }] });
  equal(plan?.items.length, 1);
  equal(plan?.items[0].songId, "7B1E7C4C-8E43-4E8B-9C1B-2D4A0F1E2A11");
});

test("Ustawienia: stare wartości, zakresy, pola tylko z macOS zachowane", () => {
  const s = normalizeSettings({ textAlignment: "lewo", marginPercent: 9, shortcuts: { nextSlideKey: 121 }, googleDrive: { isEnabled: true } });
  equal(s.textAlignment, "left");
  equal(s.marginPercent, 0.3);
  equal(s.shortcuts.nextSlideKey, 121);
  equal(s.shortcuts.prevSlideKey, 123);
  equal(/** @type {any} */ (s).googleDrive, { isEnabled: true });
});

test("ZIP: zapis i odczyt, CRC32", async () => {
  equal(crc32(new TextEncoder().encode("123456789")), 0xcbf43926);
  const blob = await createZip([{ path: "a.txt", data: "Zażółć gęślą jaźń ".repeat(50) }, { path: "dir/b.json", data: "{}" }]);
  const files = await readZip(blob);
  equal(new TextDecoder().decode(files.get("a.txt")), "Zażółć gęślą jaźń ".repeat(50));
  equal(new TextDecoder().decode(files.get("dir/b.json")), "{}");
});

test("Kopia z macOS (ditto) wczytuje się w wersji webowej", async () => {
  const response = await fetch(new URL("../../shared/fixtures/backup-macos.cantatebackup", import.meta.url));
  const backup = await readBackup(await response.blob());
  equal(backup.songs.length, 2);
  equal(backup.songs[0].slides[0].type, "verse");
  equal(backup.songs[0].ccliNumber, "9999001");
  equal(backup.songs[1].slides.length, 2);
  equal(backup.plans[0].items.length, 1);
  equal(backup.settings.textAlignment, "left");
  equal(backup.settings.copyrightNoticePlacement, "firstSlide");
  equal(backup.settings.shortcuts.nextSlideKey, 121);
  ok(backup.extraFiles?.has("logos/custom.svg"));
  ok(backup.extraFiles?.has("ccli_usage.json"));
  equal(backup.manifest.deviceName, "Mac");
});

test("Kopia z wersji webowej: ta sama zawartość po odczycie, pliki z macOS przeniesione", async () => {
  const response = await fetch(new URL("../../shared/fixtures/backup-macos.cantatebackup", import.meta.url));
  const original = await readBackup(await response.blob());
  const again = await readBackup(await createBackup(original, "test"));
  equal(again.songs, original.songs);
  equal(again.plans, original.plans);
  equal(again.settings, original.settings);
  equal(again.manifest.comment, "test");
  ok(again.extraFiles?.has("logos/custom.svg"));
  ok(/^CantatePresenter_Backup_\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d\.cantatebackup$/.test(backupFileName()));
});

test("Kopia bez songs.json albo nie-ZIP: czytelny błąd", async () => {
  let code = "";
  try { await readBackup(new Blob(["nie zip"])); } catch (e) { code = e instanceof BackupError ? e.code : "?"; }
  equal(code, "notArchive");
  try { await readBackup(await createZip([{ path: "x.txt", data: "x" }])); } catch (e) { code = e instanceof BackupError ? e.code : "?"; }
  equal(code, "noSongs");
});

test("Informacja o prawach CCLI na slajdzie", () => {
  const song = normalizeSong({ title: "T", author: "A", rawLyrics: "1\n\n2", ccliNumber: "1", copyright: "© X" });
  const settings = normalizeSettings({ ccliLicenseNumber: "99" });
  const t = (/** @type {string} */ k, /** @type {unknown[]} */ ...a) => k.replace("{0}", String(a[0]));
  equal(copyrightNotice(song, 0, settings, t), "T · A · © X · Pieśń CCLI nr 1 · Licencja CCLI nr 99");
  equal(copyrightNotice(song, 1, settings, t), null);
});

test("Wersja zgodna z plikiem VERSION", async () => {
  const version = (await (await fetch(new URL("../../VERSION", import.meta.url))).text()).trim();
  equal(APP_VERSION, version);
});
