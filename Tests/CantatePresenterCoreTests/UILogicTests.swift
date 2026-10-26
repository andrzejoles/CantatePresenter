import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-13: sortowanie biblioteki

@Suite("Sortowanie biblioteki (R4-13)")
struct SongListSortTests {
    private let songs = [
        Song(title: "  Pieśń 10", author: "Zenon", rawLyrics: ""),
        Song(title: "Ćwiczenie", author: "", rawLyrics: ""),
        Song(title: "pieśń 2", author: " Adam ", rawLyrics: ""),
        Song(title: "Barka", author: "Adam", rawLyrics: "")
    ]

    @Test("Tytuły: po polsku, bez wielkości liter, liczby naturalnie, spacje na początku pomijane")
    func byTitle() {
        let titles = SongListView.sorted(songs, by: .titleAsc).map(\.title)
        #expect(titles == ["Barka", "Ćwiczenie", "pieśń 2", "  Pieśń 10"])
        #expect(SongListView.sorted(songs, by: .titleDesc).map(\.title) == titles.reversed())
    }

    @Test("Autorzy: pusty autor na końcu, przy tym samym autorze decyduje tytuł")
    func byAuthor() {
        let titles = SongListView.sorted(songs, by: .authorAsc).map(\.title)
        #expect(titles == ["Barka", "pieśń 2", "  Pieśń 10", "Ćwiczenie"])
    }
}

// MARK: - R4-10: uchwyt paska skrótów

@Suite("Zmiana wysokości paska skrótów (R4-10)")
struct BottomBarResizeTests {
    @Test("Przeciąganie liczy się od wysokości z początku ruchu, nie przyspiesza")
    func dragIsLinear() {
        var height = 72.0
        // Kolejne zdarzenia onChanged z narastającym przesunięciem (o 4 px w górę).
        for step in 1...5 {
            height = MainView.resizedBarHeight(start: 72, dragTranslation: -4 * Double(step))
        }
        #expect(height == 92)
    }

    @Test("Wysokość w granicach 52–160 px")
    func clamped() {
        #expect(MainView.resizedBarHeight(start: 72, dragTranslation: 500) == 52)
        #expect(MainView.resizedBarHeight(start: 72, dragTranslation: -500) == 160)
    }
}
