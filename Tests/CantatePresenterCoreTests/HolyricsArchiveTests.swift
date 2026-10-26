import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R3-08: archiwum Holyrics z dowiązaniem symbolicznym

@Suite("Import archiwum Holyrics (.zip/.hly)")
struct HolyricsArchiveTests {
    /// Archiwum ZIP z katalogu (`ditto` zapisuje dowiązania symboliczne jako dowiązania).
    private func zip(_ folder: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", folder.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Dowiązanie symboliczne w archiwum nie wczytuje pliku spoza archiwum (R3-08)")
    func symlinkIsNotFollowed() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("TAJNE HASŁO 1234\nsekretna linia", to: "sekret.txt")
        let pack = dir.file("paczka")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("Pan jest pasterzem moim\nniczego mi nie braknie".utf8).write(to: pack.appendingPathComponent("pasterz.txt"))
        try FileManager.default.createSymbolicLink(atPath: pack.appendingPathComponent("a.txt").path,
                                                   withDestinationPath: dir.file("sekret.txt").path)
        try FileManager.default.createSymbolicLink(atPath: pack.appendingPathComponent("b.txt").path,
                                                   withDestinationPath: "../../sekret.txt")
        let archive = dir.file("paczka.hly")
        try zip(pack, to: archive)

        let songs = HolyricsImporter.readRawSongs(from: archive)
        let text = songs.map { $0.title + "\n" + $0.rawLyrics }.joined(separator: "\n")
        #expect(text.contains("Pan jest pasterzem"))
        #expect(!text.contains("TAJNE"))
    }
}
