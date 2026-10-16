# Wspólne pliki testowe

Pliki w `fixtures/` opisują logikę, która musi działać identycznie w każdej wersji CantatePresenter (macOS, web, Windows):

| Plik | Co sprawdza | Wzorzec |
|------|-------------|---------|
| `lyrics.json` | podział tekstu na slajdy (`type`, `label`, `text`, `number`) | `Song.parseLyrics` |
| `search.json` | zwijanie tekstu do wyszukiwania (`fold`, `searchFold`) | `Song.foldString`, `Song.searchFold` |
| `transpose.json` | transpozycja arkusza akordów | `ChordTransposer.transpose` |
| `keyboard.json` | skróty klawiszowe (kody klawiszy macOS) | `KeyboardRouter.action` |
| `chordsheet.json` | chwyty dla muzyków: dopasowanie arkusza do slajdu | `ChordSheet.lines` |
| `backup-macos.cantatebackup` | kopia zapasowa zrobiona przez `ditto` jak w macOS | `BackupRestorer` |

Wzorcem jest wersja macOS. Testy: `SharedFixturesTests` (Swift) i `web/tests/` (JavaScript).

Zmiana zachowania: popraw najpierw implementację Swift, zaktualizuj oczekiwane wyniki, potem pozostałe wersje.
