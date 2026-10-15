import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Wspólne pliki testowe (macOS, web, Windows)

/// `shared/fixtures/*.json` opisują wejście i oczekiwany wynik logiki, która musi działać tak samo we wszystkich
/// wersjach aplikacji (podział na slajdy, wyszukiwanie, transpozycja). Wersja webowa sprawdza te same pliki.
@Suite("Wspólne pliki testowe")
struct SharedFixturesTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures")

    static func load(_ name: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("Podział tekstu na slajdy")
    func lyrics() throws {
        for fixture in try Self.load("lyrics.json") {
            let name = fixture["name"] as? String ?? "?"
            let expected = try #require(fixture["expected"] as? [[String: Any]])
            let slides = Song.parseLyrics(try #require(fixture["input"] as? String))
            #expect(slides.count == expected.count, "\(name)")
            for (slide, wanted) in zip(slides, expected) {
                #expect(slide.type.rawValue == wanted["type"] as? String, "\(name)")
                #expect(slide.label == wanted["label"] as? String, "\(name)")
                #expect(slide.text == wanted["text"] as? String, "\(name)")
                #expect(slide.number == wanted["number"] as? Int, "\(name)")
            }
        }
    }

    @Test("Zwijanie tekstu do wyszukiwania")
    func search() throws {
        for fixture in try Self.load("search.json") {
            let input = try #require(fixture["input"] as? String)
            #expect(Song.foldString(input) == fixture["fold"] as? String, "\(input)")
            #expect(Song.searchFold(input) == fixture["searchFold"] as? String, "\(input)")
        }
    }

    @Test("Transpozycja akordów")
    func transpose() throws {
        for fixture in try Self.load("transpose.json") {
            let sheet = try #require(fixture["sheet"] as? String)
            let semitones = try #require(fixture["semitones"] as? Int)
            #expect(ChordTransposer.transpose(sheet, semitones: semitones) == fixture["expected"] as? String, "\(sheet)")
        }
    }
}
