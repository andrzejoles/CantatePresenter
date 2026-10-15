import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - K1: odczyt i zapis biblioteki

@MainActor
@Suite("DataStore: trwałość danych (K1)")
struct DataStorePersistenceTests {
    @Test("Zapisana biblioteka wczytuje się po ponownym uruchomieniu")
    func savedLibrarySurvivesRelaunch() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }

        let first = DataStore(dataDirectory: dir.url)
        first.songs = [Song(title: "Moja pieśń", rawLyrics: "Tekst")]
        first.saveSongs()
        first.plans = [ServicePlan(name: "Mój plan")]
        first.savePlans()

        let second = DataStore(dataDirectory: dir.url)

        #expect(second.songs.map(\.title) == ["Moja pieśń"])
        #expect(second.plans.map(\.name) == ["Mój plan"])
        #expect(second.persistenceIssues.isEmpty)
    }

    @Test("Brak pliku biblioteki: przykładowe pieśni zapisane na dysk")
    func missingLibraryLoadsSamples() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }

        let store = DataStore(dataDirectory: dir.url)

        #expect(!store.songs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.file("songs.json").path))
        #expect(store.persistenceIssues.isEmpty)
    }

    @Test("Uszkodzony songs.json nie jest nadpisywany i trafia do kwarantanny")
    func corruptLibraryIsQuarantined() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"[{"title": "Ucięty plik"#, to: "songs.json")
        let original = try dir.contents(of: "songs.json")

        let store = DataStore(dataDirectory: dir.url)
        store.addSong(Song(title: "Nowa", rawLyrics: "Tekst"))

        #expect(try dir.contents(of: "songs.json") == original)
        #expect(!store.songs.contains { SampleSongs.loadDefaults().map(\.title).contains($0.title) })
        let issue = try #require(store.persistenceIssues.first)
        #expect(issue.fileName == "songs.json")
        let copy = try #require(issue.quarantinedCopy)
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test("Uszkodzony plans.json nie jest nadpisywany")
    func corruptPlansAreQuarantined() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("nie json", to: "plans.json")

        let store = DataStore(dataDirectory: dir.url)
        _ = store.createPlan(name: "Nowy")

        #expect(try dir.contents(of: "plans.json") == Data("nie json".utf8))
        #expect(store.persistenceIssues.map(\.fileName) == ["plans.json"])
    }

    @Test("Uszkodzony settings.json nie jest nadpisywany")
    func corruptSettingsAreQuarantined() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("{", to: "settings.json")

        let store = DataStore(dataDirectory: dir.url)
        store.saveSettings()

        #expect(try dir.contents(of: "settings.json") == Data("{".utf8))
        #expect(store.persistenceIssues.map(\.fileName) == ["settings.json"])
    }

    @Test("Udane ponowne wczytanie (np. po przywróceniu kopii) odblokowuje zapis")
    func reloadAfterRestoreUnlocksSaving() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("uszkodzony", to: "songs.json")
        let store = DataStore(dataDirectory: dir.url)

        try dir.write("[]", to: "songs.json")
        store.loadSongs()
        store.addSong(Song(title: "Po przywróceniu", rawLyrics: "Tekst"))

        let reloaded = DataStore(dataDirectory: dir.url)
        #expect(reloaded.songs.map(\.title) == ["Po przywróceniu"])
    }
}

// MARK: - K1: kopie rotacyjne

@Suite("JSONFileStore: kopie rotacyjne (K1)")
struct JSONFileStoreHistoryTests {
    @Test("Przed zapisem poprzednia wersja trafia do history/, najwyżej 5 kopii")
    func keepsLastFiveVersions() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let fileStore = JSONFileStore()
        let url = dir.file("songs.json")

        for version in 1...8 {
            try fileStore.save([version], to: url, encoder: JSONEncoder())
        }

        let history = dir.url.appendingPathComponent("history")
        let names = try FileManager.default.contentsOfDirectory(atPath: history.path).sorted()
        #expect(names == ["songs.1.json", "songs.2.json", "songs.3.json", "songs.4.json", "songs.5.json"])
        let newest = try JSONDecoder().decode([Int].self, from: Data(contentsOf: history.appendingPathComponent("songs.1.json")))
        let oldest = try JSONDecoder().decode([Int].self, from: Data(contentsOf: history.appendingPathComponent("songs.5.json")))
        #expect(newest == [7])
        #expect(oldest == [3])
    }

    @Test("Wynik odczytu odróżnia brak pliku od pliku nieczytelnego")
    func distinguishesMissingFromUnreadable() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let fileStore = JSONFileStore()

        guard case .missing = fileStore.load([Int].self, from: dir.file("brak.json")) else {
            Issue.record("brak pliku powinien dać .missing")
            return
        }
        try dir.write("[1,", to: "zly.json")
        guard case .unreadable(_, let copy) = fileStore.load([Int].self, from: dir.file("zly.json")) else {
            Issue.record("uszkodzony plik powinien dać .unreadable")
            return
        }
        #expect(copy?.lastPathComponent.hasPrefix("zly.corrupt-") == true)
    }
}
