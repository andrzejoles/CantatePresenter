import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Song.parseLyrics

@Suite("Song.parseLyrics")
struct SongParseLyricsTests {
    @Test("Bloki bez nagłówków to kolejne zwrotki")
    func plainBlocksBecomeNumberedVerses() throws {
        let slides = Song.parseLyrics("Pierwsza linia\nDruga linia\n\nTrzecia linia")

        try #require(slides.count == 2)
        #expect(slides.map(\.type) == [.verse, .verse])
        #expect(slides.map(\.label) == ["Zwrotka 1", "Zwrotka 2"])
        #expect(slides[0].text == "Pierwsza linia\nDruga linia")
    }

    @Test("Nagłówki w nawiasach kwadratowych ustawiają typ i są usuwane z tekstu")
    func bracketHeaders() throws {
        let slides = Song.parseLyrics("[Zwrotka 1]\nTekst zwrotki\n\n[Refren]\nTekst refrenu")

        try #require(slides.count == 2)
        #expect(slides.map(\.type) == [.verse, .chorus])
        #expect(slides.map(\.label) == ["Zwrotka 1", "Refren"])
        #expect(slides[1].text == "Tekst refrenu")
    }

    @Test("Prefiks R: oznacza refren")
    func chorusPrefix() throws {
        let slides = Song.parseLyrics("Pan jest moim pasterzem\n\nR: Alleluja\nAmen")

        try #require(slides.count == 2)
        #expect(slides[1].type == .chorus)
        #expect(slides[1].text == "Alleluja\nAmen")
    }

    @Test("Końce linii CRLF są normalizowane")
    func crlfLineEndings() throws {
        let slides = Song.parseLyrics("A\r\nB\r\n\r\nC")

        try #require(slides.count == 2)
        #expect(slides[0].text == "A\nB")
    }

    @Test("Pusty tekst daje jeden pusty slajd")
    func emptyInput() throws {
        let slides = Song.parseLyrics("")

        try #require(slides.count == 1)
        #expect(slides[0].text.isEmpty)
    }
}

// MARK: - S7: nagłówki sekcji

@Suite("Song.parseLyrics: nagłówki (S7)")
struct SongSectionHeaderTests {
    @Test("[Pre-Chorus] i [Przed-refren] to przedrefren, nie refren", arguments: ["[Pre-Chorus]", "[Przed-refren]", "[Przedrefren]", "Pre-chorus:"])
    func preChorusHeaders(header: String) throws {
        let slides = Song.parseLyrics("\(header)\nCoraz bliżej\n\n[Refren]\nAlleluja")

        try #require(slides.count == 2)
        #expect(slides[0].type == .preChorus)
        #expect(slides[1].type == .chorus)
        #expect(slides[1].label == "Refren")
    }

    @Test("Pozostałe nagłówki bez zmian")
    func otherHeaders() {
        let raw = "[Zwrotka 1]\nA\n\n[Refren]\nB\n\n[Bridge]\nC\n\n[Coda]\nD\n\n[Przejście]\nE\n\n[Intro]\nF\n\n[Zakończenie]\nG\n\n[Refren]\nH"
        let slides = Song.parseLyrics(raw)

        #expect(slides.map(\.type) == [.verse, .chorus, .bridge, .coda, .interlude, .intro, .ending, .chorus])
        #expect(slides.last?.label == "Refren 2")
    }
}
