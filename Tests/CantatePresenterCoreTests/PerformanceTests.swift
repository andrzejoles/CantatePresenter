import Foundation
import Observation
import Testing
@testable import CantatePresenterCore

// MARK: - S2: wyszukiwanie i Auto-Fit bez liczenia wszystkiego od nowa

@Suite("Wydajność (S2)", .serialized)
struct PerformanceTests {
    /// ~900 pieśni po ~600 znaków, jak biblioteka po imporcie z Holyrics.
    static let library: [Song] = (0..<900).map { index in
        let verse = "Pan jest moim pasterzem, nie brak mi niczego. Pozwala mi leżeć na zielonych pastwiskach \(index).\n"
        return Song(
            title: index % 7 == 0 ? "Łaska \(index)" : "Pieśń numer \(index)",
            author: index % 5 == 0 ? "Józef Żółć" : "Autor \(index % 40)",
            tags: ["uwielbienie", "adwent \(index % 4)"],
            rawLyrics: String(repeating: verse, count: 6) + (index % 11 == 0 ? "Alleluja, chwała Ci Jezu" : "")
        )
    }

    /// Średni czas jednego wywołania; najkrótszy z kilku pomiarów, bo inne zestawy testów działają równolegle
    /// i pojedynczy pomiar na zajętym komputerze CI może trafić na przerwę (R1-14). Najkrótszy pomiar takiej
    /// przerwy nie zawiera, a przewaga indeksu i cache jest wielokrotnie większa niż wymagana.
    private func measure(_ iterations: Int = 20, samples: Int = 5, _ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return (0..<samples).map { _ in clock.measure { for _ in 0..<iterations { work() } } / iterations }.min() ?? .zero
    }

    @Test("Indeks wyszukiwania daje te same wyniki co Song.matches", arguments: ["jezu", "LASKA", "zolc", "pastwiskach 12", "adwent 3", "", "brak-takiego"])
    func indexMatchesLegacySearch(query: String) {
        var index = SongSearchIndex()
        index.update(with: Self.library)

        for scope in Song.SearchScope.allCases {
            let legacy = Self.library.filter { $0.matches(query: query, scope: scope) }.map(\.id)
            #expect(index.filter(Self.library, query: query, scope: scope).map(\.id) == legacy, "\(query) \(scope)")
        }
    }

    @Test("Wyszukiwanie z indeksem jest wielokrotnie szybsze")
    func searchIsFaster() {
        var index = SongSearchIndex()
        index.update(with: Self.library)

        let legacy = measure(5, samples: 3) { _ = Self.library.filter { $0.matches(query: "alleluja", scope: .all) } }
        let indexed = measure { _ = index.filter(Self.library, query: "alleluja", scope: .all) }

        print("S2 wyszukiwanie 900 pieśni: było \(legacy), jest \(indexed)")
        #expect(indexed * 5 < legacy)
    }

    @Test("Aktualizacja indeksu po zmianie jednej pieśni przelicza tylko ją")
    func incrementalUpdate() {
        var index = SongSearchIndex()
        index.update(with: Self.library)
        var changed = Self.library
        changed[3].rawLyrics = "Zupełnie nowy tekst o Maranatha"

        let recomputed = index.update(with: changed)

        #expect(recomputed == 1)
        #expect(index.filter(changed, query: "maranatha", scope: .all).map(\.id) == [changed[3].id])
    }

    @Test("Auto-Fit: ten sam slajd liczony raz")
    func autoFitIsCached() {
        AutoFitEngine.clearCache()
        let text = Self.library[0].slides[0].text
        let size = CGSize(width: 1920, height: 1080)

        let first = AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: size)
        let cold = measure(1) { AutoFitEngine.clearCache(); _ = AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: size) }
        let warm = measure { _ = AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: size) }

        print("S2 Auto-Fit jednego slajdu: bez cache \(cold), z cache \(warm)")
        #expect(AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: size) == first)
        #expect(warm * 10 < cold)
        #expect(AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: CGSize(width: 800, height: 450)) < first)
    }
}

// MARK: - S2: zmiana slajdu nie unieważnia listy pieśni

@MainActor
@Suite("DataStore: śledzenie pojedynczych właściwości (S2)")
struct DataStoreObservationTests {
    private func makeStore(_ dir: TestDirectory) -> DataStore {
        let store = DataStore(dataDirectory: dir.url)
        store.songs = Array(PerformanceTests.library.prefix(20))
        return store
    }

    /// Właściwości czytane przez listę pieśni.
    private func trackLibraryReads(_ store: DataStore, onChange: @escaping @Sendable () -> Void) {
        withObservationTracking {
            _ = store.songs
            _ = store.selectedSongId
            _ = store.settings.uiScale
            _ = store.searchIndex
            // Znacznik „na żywo” przy pieśni na liście
            _ = store.activeSong?.id
            _ = store.isLive
        } onChange: {
            onChange()
        }
    }

    @Test("Przełączenie slajdu, czarny ekran i ukrycie tekstu nie powiadamiają listy pieśni")
    func liveChangesDoNotInvalidateLibrary() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = makeStore(dir)
        store.present(song: store.songs[0])
        let fired = Flag()

        trackLibraryReads(store) { fired.set() }
        store.nextSlide()
        store.toggleBlackScreen()
        store.toggleClearText()

        #expect(!fired.value)
    }

    @Test("Zmiana biblioteki powiadamia listę pieśni")
    func libraryChangeInvalidates() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = makeStore(dir)
        let fired = Flag()

        trackLibraryReads(store) { fired.set() }
        store.addSong(Song(title: "Nowa", rawLyrics: "Tekst"))

        #expect(fired.value)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}

// MARK: - Wyszukiwanie bez znaków interpunkcyjnych

@Suite("Wyszukiwanie ignoruje interpunkcję")
struct SearchPunctuationTests {
    private let song = Song(title: "Mój Jezu, mój Zbawco", author: "K. Sz.", rawLyrics: "Mój Jezu, mój Zbawco, któż jest tak wielki jak Ty?\nCały świat...")

    @Test("Zapytanie bez polskich znaków i przecinków znajduje pieśń", arguments: [
        "moj jezu moj zbawco", "jezu mój zbawco", "MOJ JEZU, MOJ ZBAWCO", "tak wielki jak ty", "caly swiat", "k sz"
    ])
    func ignoresPunctuation(query: String) {
        var index = SongSearchIndex()
        index.update(with: [song])
        #expect(index.filter([song], query: query, scope: .all).count == 1, "\(query)")
        #expect(song.matches(query: query, scope: .all), "\(query)")
    }

    @Test("Interpunkcja nie skleja słów i nie daje fałszywych trafień")
    func noFalseMatches() {
        var index = SongSearchIndex()
        index.update(with: [song])
        #expect(index.filter([song], query: "jezumoj", scope: .all).isEmpty)
    }
}
