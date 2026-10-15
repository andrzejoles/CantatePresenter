import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S4: eksport do folderu

@Suite("SongExporter: eksport do folderu (S4)")
struct SongExporterTests {
    @Test("Pieśni o tym samym tytule dostają sufiks zamiast się nadpisywać")
    func duplicateTitlesGetSuffix() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let songs = [
            Song(title: "Barka", rawLyrics: "z akordami"),
            Song(title: "Barka", rawLyrics: "bez akordów"),
            Song(title: "barka", rawLyrics: "mała litera"),
            Song(title: "Pan/Bóg", rawLyrics: "ukośnik")
        ]

        let written = try SongExporter.exportSongs(songs, to: dir.url)

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names == ["Barka (2).txt", "Barka.txt", "Pan_Bóg.txt", "barka (3).txt"])
        #expect(written == 4)
        let second = try String(contentsOf: dir.file("Barka (2).txt"), encoding: .utf8)
        #expect(second.contains("bez akordów"))
    }

    @Test("Licznik to faktycznie zapisane pliki")
    func countsOnlyWrittenFiles() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let missing = dir.url.appendingPathComponent("nie-istnieje/głębiej")

        #expect(throws: (any Error).self) {
            try SongExporter.exportSongs([Song(title: "A", rawLyrics: "x")], to: missing)
        }
    }
}
