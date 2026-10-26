# Pliki wzorcowe

Pliki w `fixtures/` opisują wejście i oczekiwany wynik kluczowej logiki aplikacji, niezależnie od kodu, który ją implementuje. Sprawdza je `Tests/CantatePresenterCoreTests/SharedFixturesTests.swift`.

| Plik | Co sprawdza | Kod |
|------|-------------|-----|
| `lyrics.json` | podział tekstu na slajdy (`type`, `label`, `text`, `number`) | `Song.parseLyrics` |
| `search.json` | zwijanie tekstu do wyszukiwania (`fold`, `searchFold`) | `Song.foldString`, `Song.searchFold` |
| `transpose.json` | transpozycja arkusza akordów | `ChordTransposer.transpose` |
| `keyboard.json` | skróty klawiszowe (kody klawiszy macOS) | `KeyboardRouter.action` |
| `chordsheet.json` | chwyty dla muzyków: dopasowanie arkusza do slajdu | `ChordSheet.lines` |
| `dedup.json` | duplikaty przy imporcie | `SongDeduplicationService` |
| `autofit.json` | Auto-Fit (dokładnie tylko przypadki `anyMeasurer`; wzorzec: `scripts/make_autofit_fixture.py`) | `AutoFitEngine` |
| `holyrics-*.mufl`, `holyrics-*.muf`, `holyrics-export.xml`, `holyrics.json` | import Holyrics, wynik w `holyrics.json`. `holyrics-music-list.mufl` i `holyrics-music-list-truncated.mufl` tworzy `scripts/make_holyrics_fixture.py`; `holyrics-tagged.muf` i `holyrics-export.xml` nie mają generatora w `scripts/` | `HolyricsImporter` |
| `wikisource.json` | odczyt tekstu z Wikiźródeł | `WikisourceParser` |
| `backup-macos.cantatebackup` | kopia zapasowa zrobiona przez `ditto` jak w macOS | `BackupRestorer` |

Zmiana zachowania: popraw implementację, potem zaktualizuj oczekiwane wyniki.
