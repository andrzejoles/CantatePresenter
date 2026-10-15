import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - K2: lokalizacja danych i migracja

@Suite("AppPaths (K2)")
struct AppPathsTests {
    private func makeLegacyData(in dir: TestDirectory) throws -> URL {
        let legacy = dir.url.appendingPathComponent("Programy/data", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("logos"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("holyrics_samples"), withIntermediateDirectories: true)
        try Data(#"[{"title":"Barka","rawLyrics":"Tekst"}]"#.utf8).write(to: legacy.appendingPathComponent("songs.json"))
        try Data("[]".utf8).write(to: legacy.appendingPathComponent("plans.json"))
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("settings.json"))
        try Data("<html></html>".utf8).write(to: legacy.appendingPathComponent("standby.html"))
        try Data("png".utf8).write(to: legacy.appendingPathComponent("logos/logo.png"))
        try Data("mufl".utf8).write(to: legacy.appendingPathComponent("holyrics_samples/a.mufl"))
        return legacy
    }

    private func resolve(in dir: TestDirectory, environment: [String: String] = [:]) -> AppPaths {
        AppPaths.resolve(
            environment: environment,
            bundleURL: dir.url.appendingPathComponent("Programy/CantatePresenter.app"),
            currentDirectory: dir.url.appendingPathComponent("terminal"),
            applicationSupport: dir.url.appendingPathComponent("Application Support")
        )
    }

    @Test("Dane trafiają do Application Support/CantatePresenter, nie obok aplikacji")
    func usesApplicationSupport() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }

        let paths = resolve(in: dir)

        #expect(paths.dataDirectory == dir.url.appendingPathComponent("Application Support/CantatePresenter"))
        #expect(paths.songsFile.lastPathComponent == "songs.json")
        #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path))
        #expect(paths.migration == .notNeeded)
    }

    @Test("Stare dane obok .app są kopiowane przy pierwszym uruchomieniu, oryginał zostaje")
    func migratesLegacyData() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let legacy = try makeLegacyData(in: dir)

        let paths = resolve(in: dir)

        #expect(paths.migration == .migrated(from: legacy))
        for name in ["songs.json", "plans.json", "settings.json", "standby.html", "logos/logo.png"] {
            #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.appendingPathComponent(name).path), "\(name)")
            #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent(name).path), "\(name)")
        }
        #expect(!FileManager.default.fileExists(atPath: paths.dataDirectory.appendingPathComponent("holyrics_samples").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.dataDirectory.path)
            .filter { $0.hasPrefix(".migration") }
        #expect(leftovers.isEmpty)
    }

    @Test("Istniejące dane w nowej lokalizacji nie są nadpisywane")
    func doesNotOverwriteExistingData() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        _ = try makeLegacyData(in: dir)
        let target = dir.url.appendingPathComponent("Application Support/CantatePresenter")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: target.appendingPathComponent("songs.json"))

        let paths = resolve(in: dir)

        #expect(paths.migration == .notNeeded)
        #expect(try Data(contentsOf: paths.songsFile) == Data("[]".utf8))
        #expect(!FileManager.default.fileExists(atPath: paths.standbyFile.path))
    }

    @Test("Zmienna CANTATE_DATA_DIR wskazuje katalog danych i wyłącza migrację")
    func environmentOverride() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        _ = try makeLegacyData(in: dir)
        let custom = dir.url.appendingPathComponent("własny katalog")

        let paths = resolve(in: dir, environment: ["CANTATE_DATA_DIR": custom.path])

        #expect(paths.dataDirectory.standardizedFileURL == custom.standardizedFileURL)
        #expect(paths.migration == .notNeeded)
        #expect(!FileManager.default.fileExists(atPath: paths.songsFile.path))
    }

    @Test("Przy swift run stare dane są szukane w bieżącym katalogu")
    func legacyDirectoryForSwiftRun() {
        let legacy = AppPaths.legacyDataDirectory(
            bundleURL: URL(fileURLWithPath: "/repo/.build/debug"),
            currentDirectory: URL(fileURLWithPath: "/repo")
        )

        #expect(legacy.path == "/repo/data")
    }

    @Test("Nieudana migracja: aplikacja zostaje przy starym katalogu, żeby nie zacząć od pustej biblioteki")
    func failedMigrationFallsBackToLegacy() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let legacy = try makeLegacyData(in: dir)
        // Plik w miejscu katalogu docelowego uniemożliwia migrację.
        let support = dir.url.appendingPathComponent("Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: support.appendingPathComponent("CantatePresenter"))

        let paths = resolve(in: dir)

        #expect(paths.dataDirectory == legacy)
        guard case .failed(let from, _) = paths.migration else {
            Issue.record("oczekiwano .failed, jest \(paths.migration)")
            return
        }
        #expect(from == legacy)
    }
}
