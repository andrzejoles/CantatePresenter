// @ts-check
import { test, equal, ok, fixture } from "./harness.js";
import { normalizeSong, normalizePlan, normalizeSettings, parseDate, createSong, copyrightNotice, SCHEMA_VERSION } from "../src/core/models.js";
import { createZip, readZip, crc32 } from "../src/core/zip.js";
import { createBackup, readBackup, backupFileName, BackupError } from "../src/core/backup.js";
import { keyboardAction, MAC_KEY_CODES } from "../src/core/keyboard.js";
import { DEFAULT_SHORTCUTS } from "../src/core/models.js";
import { APP_VERSION } from "../src/version.js";
import { usageEntry, usageCSV, normalizeUsageEntry } from "../src/core/ccli.js";
import { Store } from "../src/app/store.js";

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
  ok(!backup.extraFiles?.has("ccli_usage.json"));
  ok((backup.ccliUsage ?? []).length > 0, "raport CCLI z macOS");
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

test("Wersja formatu danych: zapisywana w ustawieniach i manifeście, nowsza kopia odrzucana", async () => {
  equal(SCHEMA_VERSION, 1);
  equal(normalizeSettings({}).schemaVersion, SCHEMA_VERSION);
  const zip = await createBackup({ songs: [], plans: [], settings: normalizeSettings({}) });
  const files = await readZip(zip);
  equal(JSON.parse(new TextDecoder().decode(files.get("manifest.json"))).schemaVersion, SCHEMA_VERSION);
  for (const [name, content] of [["settings.json", '{"schemaVersion":99}'], ["manifest.json", '{"schemaVersion":5}']]) {
    let code = "";
    try {
      await readBackup(await createZip([{ path: "songs.json", data: "[]" }, { path: name, data: content }]));
    } catch (e) { code = e instanceof BackupError ? e.code : "?"; }
    equal(code, "newerSchema", name);
  }
});

test("Raport CCLI: raz na pieśń dziennie, CSV jak w macOS, wpisy z macOS", () => {
  const song = { title: "Pieśń, \"cytat\"", author: "Autor", ccliNumber: " 123 ", copyright: "© 2020" };
  const day = new Date(2026, 9, 18, 10, 0);
  const first = usageEntry(song, day, []);
  ok(first && first.ccliNumber === "123");
  equal(usageEntry(song, new Date(2026, 9, 18, 19, 0), [/** @type {any} */ (first)]), null);
  ok(usageEntry(song, new Date(2026, 9, 25, 10, 0), [/** @type {any} */ (first)]));
  equal(usageEntry({ title: "Bez", author: "" }, day, []), null);
  equal(usageCSV([/** @type {any} */ (first)]), 'Date,Title,Authors,CCLI Song Number,Copyright\r\n2026-10-18,"Pieśń, ""cytat""",Autor,123,© 2020\r\n');
  const fromMac = normalizeUsageEntry({ id: "6f1c5a39-2b5e-4f0b-9c55-111111111111", date: "2026-10-15T08:30:00Z", title: "A", author: "B", ccliNumber: 7 });
  equal(fromMac.ccliNumber, "7");
  equal(fromMac.id, "6F1C5A39-2B5E-4F0B-9C55-111111111111");

  /** @type {any[]} */
  const saved = [];
  const store = new Store({ songs: [], persist: (kind, value) => saved.push([kind, value]) });
  const added = store.addSong({ title: "S", rawLyrics: "x" });
  store.updateSong({ ...added, ccliNumber: "55" });
  store.present(/** @type {any} */ (store.songs[0]));
  store.present(/** @type {any} */ (store.songs[0]));
  equal(store.ccliUsage.length, 1);
  equal(saved.filter(([kind]) => kind === "ccliUsage").length, 1);
});

test("Kopia: raport CCLI w ccli_usage.json w obie strony", async () => {
  const entry = normalizeUsageEntry({ date: "2026-10-15T08:30:00Z", title: "A", author: "B", ccliNumber: "1" });
  const zip = await createBackup({ songs: [], plans: [], settings: normalizeSettings({}), ccliUsage: [entry] });
  const back = await readBackup(zip);
  equal(back.ccliUsage, [entry]);
  ok(!back.extraFiles?.has("ccli_usage.json"));
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
