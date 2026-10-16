import Foundation
import Testing
@testable import CantatePresenterCore

@MainActor
@Suite("Wersja formatu danych (schemaVersion)")
struct DataSchemaTests {
    @Test("Stare settings.json bez pola: wersja 0, po wczytaniu zapisana bieżąca")
    func legacyIsMigrated() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"{"appLanguage":"en"}"#, to: "settings.json")
        try dir.write("[]", to: "songs.json")
        try dir.write("[]", to: "plans.json")
        #expect(DataSchema.version(ofSettingsAt: dir.file("settings.json")) == 0)

        let store = DataStore(dataDirectory: dir.url)
        #expect(store.settings.appLanguage == "en")
        #expect(store.settings.schemaVersion == DataSchema.current)
        #expect(DataSchema.version(ofSettingsAt: dir.file("settings.json")) == DataSchema.current)
        #expect(store.persistenceIssues.isEmpty)
        // Format pieśni się nie zmienia: nadal tablica.
        store.addSong(Song(title: "A", rawLyrics: "x"))
        let songs = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.file("songs.json")))
        #expect(songs is [Any])
    }

    @Test("Nowy katalog: settings.json od razu z bieżącą wersją")
    func freshDirectory() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        _ = DataStore(dataDirectory: dir.url)
        #expect(DataSchema.version(ofSettingsAt: dir.file("settings.json")) == DataSchema.current)
    }

    @Test("Dane z nowszej wersji: wczytane, ale nic nie jest zapisywane")
    func newerIsReadOnly() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let settings = #"{"schemaVersion":99,"appLanguage":"de","futureField":{"a":1}}"#
        try dir.write(settings, to: "settings.json")
        let songs = #"[{"id":"6F1C5A39-2B5E-4F0B-9C55-111111111111","title":"Przyszła","rawLyrics":"x","futureField":true}]"#
        try dir.write(songs, to: "songs.json")
        try dir.write("[]", to: "plans.json")

        let store = DataStore(dataDirectory: dir.url)
        #expect(store.songs.map(\.title) == ["Przyszła"])
        #expect(store.settings.appLanguage == "de")
        #expect(store.persistenceIssues.contains { $0.kind == .newerSchema })

        store.addSong(Song(title: "Nowa", rawLyrics: "y"))
        store.settings.appLanguage = "pl"
        store.saveSettings()
        #expect(try String(contentsOf: dir.file("songs.json"), encoding: .utf8) == songs)
        #expect(try String(contentsOf: dir.file("settings.json"), encoding: .utf8) == settings)
    }

    @Test("Kopia zapasowa z nowszej wersji jest odrzucana przed podmianą danych")
    func newerBackupRejected() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = dir.url.appendingPathComponent("data")
        let backup = dir.url.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: data.appendingPathComponent("songs.json"))
        try Data("[]".utf8).write(to: backup.appendingPathComponent("songs.json"))
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: backup.appendingPathComponent("settings.json"))

        #expect(throws: BackupRestorer.RestoreError.self) {
            try BackupRestorer(dataDirectory: data).restore(fromExtracted: backup)
        }
        // Manifest z nowszą wersją (bez settings.json) też.
        try FileManager.default.removeItem(at: backup.appendingPathComponent("settings.json"))
        try Data(#"{"schemaVersion":7}"#.utf8).write(to: backup.appendingPathComponent("manifest.json"))
        #expect(throws: BackupRestorer.RestoreError.self) {
            try BackupRestorer(dataDirectory: data).restore(fromExtracted: backup)
        }
        try Data(#"{"schemaVersion":1}"#.utf8).write(to: backup.appendingPathComponent("manifest.json"))
        #expect(try BackupRestorer(dataDirectory: data).restore(fromExtracted: backup).songsCount == 0)
    }

    @Test("Migracja od wersji 0 do bieżącej")
    func migrationSteps() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        #expect(try DataSchema.migrate(from: 0, in: dir.url).count == DataSchema.current)
        #expect(try DataSchema.migrate(from: DataSchema.current, in: dir.url).isEmpty)
    }
}
