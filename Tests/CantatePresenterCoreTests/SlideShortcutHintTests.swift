import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-03: znaczek klawisza na karcie slajdu

@Suite("Znaczek klawisza na karcie slajdu (R4-03)")
struct SlideShortcutHintTests {
    private func song(_ slides: [SongSlide]) -> Song {
        Song(title: "Test", rawLyrics: "", slides: slides)
    }

    @Test("Z1, R, Z2, R, Z3: karta Z2 pokazuje 2 (cyfra 2 przechodzi do niej), R tylko na pierwszym refrenie")
    func versesAndChoruses() {
        let s = song([
            SongSlide(type: .verse, label: "Z1", text: "a", number: 1),
            SongSlide(type: .chorus, label: "R", text: "r", number: 1),
            SongSlide(type: .verse, label: "Z2", text: "b", number: 2),
            SongSlide(type: .chorus, label: "R", text: "r", number: 1),
            SongSlide(type: .verse, label: "Z3", text: "c", number: 3)
        ])
        #expect(s.slideShortcutHints == [0: "1", 1: "R", 2: "2", 4: "3"])
        #expect(s.slideIndex(forVerse: 3) == 4)
        #expect(s.chorusSlideIndex == 1)
    }

    @Test("Bridge i Coda nie dostają cyfry, która przełącza na inny slajd")
    func otherTypesWithoutDigit() {
        let s = song([
            SongSlide(type: .verse, label: "Z1", text: "a", number: 1),
            SongSlide(type: .bridge, label: "B", text: "b", number: 1),
            SongSlide(type: .verse, label: "Z2", text: "c", number: 2),
            SongSlide(type: .coda, label: "C", text: "d", number: 1)
        ])
        let hints = s.slideShortcutHints
        #expect(hints[1] == nil)
        #expect(hints[3] == nil)
        #expect(hints[2] == "2")
    }

    @Test("Pieśń bez numerowanych zwrotek: cyfra wybiera slajd po kolei, tak jak klawisz")
    func unnumberedSongFallsBackToPosition() {
        let s = song([
            SongSlide(type: .custom, label: "A", text: "a", number: 1),
            SongSlide(type: .custom, label: "B", text: "b", number: 1)
        ])
        #expect(s.slideIndex(forVerse: 2) == 1)
        #expect(s.slideShortcutHints[1] == "2")
    }

    @MainActor
    @Test("Klawisz cyfry albo R przechodzi do slajdu, którego karta pokazuje ten klawisz")
    func hintMatchesDataStoreJump() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let s = song([
            SongSlide(type: .verse, label: "Z1", text: "a", number: 1),
            SongSlide(type: .chorus, label: "R", text: "r", number: 1),
            SongSlide(type: .verse, label: "Z2", text: "b", number: 2),
            SongSlide(type: .bridge, label: "B", text: "x", number: 1),
            SongSlide(type: .verse, label: "Z3", text: "c", number: 3)
        ])
        store.present(song: s)
        for (index, hint) in s.slideShortcutHints {
            if hint == "R" {
                store.jumpToChorus()
            } else {
                store.jumpToVerse(number: try #require(Int(hint)))
            }
            #expect(store.activeSlideIndex == index)
        }
    }
}
