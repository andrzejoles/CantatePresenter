import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S5: przywracanie kopii z walidacją i wycofaniem

@Suite("BackupRestorer (S5)")
struct BackupRestorerTests {
    private func songsJSON(_ titles: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(titles.map { Song(title: $0, rawLyrics: "Tekst") })
    }

    /// Katalog danych z biblioteką `current` i katalogiem `history/`, oraz rozpakowana kopia z biblioteką `backup`.
    private func makeFixture(in dir: TestDirectory, current: [String] = ["Obecna"], backup: Data? = nil) throws -> (data: URL, backup: URL) {
        let fileManager = FileManager.default
        let data = dir.url.appendingPathComponent("Application Support/CantatePresenter")
        try fileManager.createDirectory(at: data.appendingPathComponent("history"), withIntermediateDirectories: true)
        try songsJSON(current).write(to: data.appendingPathComponent("songs.json"))
        try Data("historia".utf8).write(to: data.appendingPathComponent("history/songs.1.json"))

        let root = dir.url.appendingPathComponent("rozpakowana")
        try fileManager.createDirectory(at: root.appendingPathComponent("logos"), withIntermediateDirectories: true)
        try (backup ?? songsJSON(["Z kopii 1", "Z kopii 2"])).write(to: root.appendingPathComponent("songs.json"))
        try Data("[]".utf8).write(to: root.appendingPathComponent("plans.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        try Data("png".utf8).write(to: root.appendingPathComponent("logos/logo.png"))
        try Data("#!/bin/sh".utf8).write(to: root.appendingPathComponent("obcy.sh"))
        return (data, root)
    }

    private func titles(in data: URL) throws -> [String] {
        try JSONFileStore.makeDecoder().decode([Song].self, from: Data(contentsOf: data.appendingPathComponent("songs.json"))).map(\.title)
    }

    @Test("Poprawna kopia: podmiana danych, znane pliki, history/ zostaje, poprzedni stan zachowany")
    func restoresValidBackup() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (data, backup) = try makeFixture(in: dir)
        let restorer = BackupRestorer(dataDirectory: data)

        let result = try restorer.restore(fromExtracted: backup)

        #expect(try titles(in: data) == ["Z kopii 1", "Z kopii 2"])
        #expect(result.songsCount == 2)
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("logos/logo.png").path))
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("history/songs.1.json").path))
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("obcy.sh").path))
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("manifest.json").path))
        #expect(try titles(in: result.previousState) == ["Obecna"])
    }

    @Test("Uszkodzony songs.json w kopii: dane nietknięte, bez pozostałości")
    func rejectsCorruptBackup() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (data, backup) = try makeFixture(in: dir, backup: Data("[{\"title\": ".utf8))
        let before = try Data(contentsOf: data.appendingPathComponent("songs.json"))

        #expect(throws: (any Error).self) {
            try BackupRestorer(dataDirectory: data).restore(fromExtracted: backup)
        }
        #expect(try Data(contentsOf: data.appendingPathComponent("songs.json")) == before)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: data.deletingLastPathComponent().path)
        #expect(siblings == ["CantatePresenter"])
    }

    @Test("Kopia bez songs.json jest odrzucana")
    func rejectsBackupWithoutSongs() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (data, backup) = try makeFixture(in: dir)
        try FileManager.default.removeItem(at: backup.appendingPathComponent("songs.json"))

        #expect(throws: (any Error).self) {
            try BackupRestorer(dataDirectory: data).restore(fromExtracted: backup)
        }
        #expect(try titles(in: data) == ["Obecna"])
    }

    @Test("Cofnij przywracanie wraca do poprzedniego stanu")
    func undoRestore() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (data, backup) = try makeFixture(in: dir)
        let restorer = BackupRestorer(dataDirectory: data)
        _ = try restorer.restore(fromExtracted: backup)

        #expect(restorer.canUndo)
        try restorer.undoLastRestore()

        #expect(try titles(in: data) == ["Obecna"])
        #expect(!restorer.canUndo)
    }

    @Test("Zostają najwyżej 3 poprzednie stany")
    func prunesPreviousStates() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (data, backup) = try makeFixture(in: dir)
        let restorer = BackupRestorer(dataDirectory: data)

        for _ in 0..<5 {
            _ = try restorer.restore(fromExtracted: backup)
        }

        #expect(restorer.previousStates().count == 3)
    }

    @Test("Rozpakowanie archiwum ditto poza wątkiem głównym")
    func unzipsArchive() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let source = dir.url.appendingPathComponent("źródło")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: source.appendingPathComponent("songs.json"))
        let archive = dir.file("kopia.cantatebackup")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--sequesterRsrc", source.path, archive.path]
        try zip.run()
        zip.waitUntilExit()

        let target = dir.url.appendingPathComponent("cel")
        try await BackupRestorer.unzip(archive, to: target)

        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("songs.json").path))
    }
}
