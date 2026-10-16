import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - K1: zgodność wstecz i w przód dekoderów modeli

@Suite("Dekodowanie modeli (K1)")
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONFileStore.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("Daty zapisane jako ISO 8601 (format saveSongs)")
    func iso8601Dates() throws {
        let song = try decode(Song.self, #"""
        {"id":"7B1E7C4C-8E43-4E8B-9C1B-2D4A0F1E2A11","title":"Barka","author":"","key":"","tags":[],
         "rawLyrics":"Tekst","slides":[],"createdAt":"2026-10-15T06:04:51Z","updatedAt":"2026-10-15T06:04:51.250Z"}
        """#)

        #expect(song.createdAt == ISO8601DateFormatter().date(from: "2026-10-15T06:04:51Z"))
        #expect(song.updatedAt.timeIntervalSince(song.createdAt) == 0.25)
    }

    @Test("Daty zapisane jako liczby (domyślny format Codable)")
    func numericDates() throws {
        let plan = try decode(ServicePlan.self, #"""
        {"id":"7B1E7C4C-8E43-4E8B-9C1B-2D4A0F1E2A11","name":"Plan","items":[],"createdAt":0,"updatedAt":86400}
        """#)

        #expect(plan.createdAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(plan.updatedAt == Date(timeIntervalSinceReferenceDate: 86400))
    }

    @Test("Pieśń z brakującymi polami i nieznanym nowym polem się wczytuje")
    func toleratesMissingAndUnknownFields() throws {
        let song = try decode(Song.self, #"{"title":"Stara pieśń","rawLyrics":"A\n\nB","ccliNumber":12345}"#)

        #expect(song.title == "Stara pieśń")
        #expect(song.author.isEmpty)
        #expect(song.tags.isEmpty)
        #expect(song.slides.count == 2)
    }

    @Test("Nieznany typ slajdu nie psuje całej biblioteki")
    func unknownSlideType() throws {
        let slide = try decode(SongSlide.self, #"{"type":"Hymn","label":"X","text":"Y"}"#)

        #expect(slide.type == .custom)
        #expect(slide.text == "Y")
    }

    @Test("Pozycja planu bez notatki się wczytuje")
    func planItemWithoutNote() throws {
        let item = try decode(PlanItem.self, #"{"songId":"7B1E7C4C-8E43-4E8B-9C1B-2D4A0F1E2A11"}"#)

        #expect(item.note.isEmpty)
    }
}

@Suite("Skróty z niepełnym zapisem")
struct ShortcutDecodingTests {
    @Test("Brakujące skróty dostają wartości domyślne, zamiast odrzucać całe ustawienia")
    func partialShortcuts() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"shortcuts":{"nextSlideKey":121}}"#.utf8))
        #expect(settings.shortcuts.nextSlideKey == 121)
        #expect(settings.shortcuts.prevSlideKey == ShortcutSettings().prevSlideKey)
        #expect(settings.shortcuts.blackScreenKey == ShortcutSettings().blackScreenKey)
    }

}

@Suite("Pieśni z chwytami")
struct SongChordsFlagTests {
    @Test("hasChords: tylko niepusty arkusz chwytów")
    func hasChords() {
        var song = Song(title: "A", rawLyrics: "x")
        #expect(!song.hasChords)
        song.chords = "  \n "
        #expect(!song.hasChords)
        song.chords = "G  D\nTekst"
        #expect(song.hasChords)
    }
}
