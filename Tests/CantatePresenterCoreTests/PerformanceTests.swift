import Foundation
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

    private func measure(_ iterations: Int = 20, _ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return clock.measure { for _ in 0..<iterations { work() } } / iterations
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

        let legacy = measure(5) { _ = Self.library.filter { $0.matches(query: "alleluja", scope: .all) } }
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
