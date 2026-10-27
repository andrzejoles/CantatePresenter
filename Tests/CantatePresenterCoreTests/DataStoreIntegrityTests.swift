import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Spójność biblioteki: powtórzone id, nowszy format, zapis zbiorczy (R2-06, R2-08, R2-10)

@MainActor
@Suite("DataStore: spójność danych")
struct DataStoreIntegrityTests {
    private func writeSongs(_ songs: [Song], to dir: TestDirectory) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(songs).write(to: dir.file("songs.json"))
    }

    @Test("Powtórzone id w songs.json są naprawiane przy wczytaniu; usunięcie usuwa jedną pieśń (R2-06)")
    func repairsDuplicateIdentifiers() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let first = Song(title: "Barka", rawLyrics: "Pan kiedyś stanął")
        var copy = Song(title: "Barka (kopia)", rawLyrics: "Pan kiedyś stanął nad brzegiem")
        copy.id = first.id
        try writeSongs([first, copy], to: dir)

        let store = DataStore(dataDirectory: dir.url)

        #expect(store.songs.count == 2)
        #expect(Set(store.songs.map(\.id)).count == 2)
        #expect(store.songs.first?.id == first.id)
        store.deleteSong(id: first.id)
        #expect(store.songs.map(\.title) == ["Barka (kopia)"])

        // Naprawa jest zapisana na dysku.
        let reloaded = DataStore(dataDirectory: dir.url)
        #expect(reloaded.songs.map(\.title) == ["Barka (kopia)"])
    }

    @Test("Nowsza wersja danych z ustawieniami, których ta wersja nie odczyta: tylko odczyt (R2-08)")
    func newerSchemaWithUnreadableSettingsIsReadOnly() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try writeSongs([Song(title: "Barka", rawLyrics: "Tekst")], to: dir)
        try dir.write(#"{"schemaVersion": 2, "shortcuts": [1, 2, 3]}"#, to: "settings.json")
        let songsBefore = try dir.contents(of: "songs.json")

        let store = DataStore(dataDirectory: dir.url)
        store.addSong(Song(title: "Nowa", rawLyrics: "x"))

        #expect(store.isReadOnlyNewerSchema)
        #expect(try dir.contents(of: "songs.json") == songsBefore)
    }

    @Test("Zbiorcza zmiana pieśni: jeden zapis, poprzednia biblioteka w history/ (R2-10)")
    func batchUpdateSavesOnce() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let songs = (1...10).map { Song(title: "Pieśń \($0)", rawLyrics: "Tekst \($0)") }
        try writeSongs(songs, to: dir)
        let store = DataStore(dataDirectory: dir.url)
        let before = try dir.contents(of: "songs.json")
        let history = dir.url.appendingPathComponent("history")
        let historyBefore = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []

        let changed = store.songs.map { song -> Song in
            var song = song
            song.author = "Autor"
            return song
        }
        store.updateSongs(changed)

        #expect(store.songs.allSatisfy { $0.author == "Autor" })
        let historyAfter = try FileManager.default.contentsOfDirectory(atPath: history.path)
        #expect(historyAfter.filter { $0.hasPrefix("songs.") }.count == historyBefore.filter { $0.hasPrefix("songs.") }.count + 1)
        #expect(try Data(contentsOf: history.appendingPathComponent("songs.1.json")) == before)
    }
}

// MARK: - R6-07: po przywróceniu kopii stan w pamięci pasuje do wczytanych danych

@MainActor
@Suite("DataStore: ponowne wczytanie po przywróceniu kopii")
struct DataStoreReloadTests {
    private func writeSongs(_ songs: [Song], to dir: TestDirectory) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(songs).write(to: dir.file("songs.json"))
    }

    @Test("Zaznaczenie, plan i projekcja nie wskazują danych sprzed przywrócenia (R6-07)")
    func reloadDropsStaleState() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let old = Song(title: "Stara", rawLyrics: "Stary tekst")
        let kept = Song(title: "Barka", rawLyrics: "Pan kiedyś stanął")
        try writeSongs([kept, old], to: dir)
        let store = DataStore(dataDirectory: dir.url)
        store.selectedSongId = old.id
        store.present(song: old)

        let restored = Song(title: "Nowa", rawLyrics: "Nowy tekst")
        try writeSongs([restored], to: dir)
        let plan = ServicePlan(name: "Plan z kopii", items: [PlanItem(songId: restored.id)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([plan]).write(to: dir.file("plans.json"))
        store.reloadAll()

        #expect(store.songs.map(\.id) == [restored.id])
        #expect(store.selectedSongId == restored.id)
        #expect(store.activePlanId == plan.id)
        #expect(store.activeSong == nil)
        #expect(!store.isLive)
    }

    @Test("Pieśń na ekranie, która jest w przywróconych danych, pokazuje ich wersję (R6-07)")
    func reloadRefreshesActiveSong() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let song = Song(title: "Barka", rawLyrics: "Pierwsza\n\nDruga\n\nTrzecia")
        try writeSongs([song], to: dir)
        let store = DataStore(dataDirectory: dir.url)
        store.selectedSongId = song.id
        store.present(song: song, slideIndex: 2)

        try writeSongs([Song(id: song.id, title: "Barka", rawLyrics: "Jedyna zwrotka")], to: dir)
        store.reloadAll()

        #expect(store.selectedSongId == song.id)
        #expect(store.isLive)
        #expect(store.activeSong?.rawLyrics == "Jedyna zwrotka")
        #expect(store.activeSlideIndex == 0)
    }
}
