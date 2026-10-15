import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - W8: unikalne identyfikatory przy imporcie

@MainActor
@Suite("Import: unikalne UUID (W8)")
struct ImportIdentifierTests {
    private func song(_ title: String, _ lyrics: String = "Pan jest moim pasterzem nie brak mi niczego", id: UUID = UUID()) -> Song {
        Song(id: id, title: title, rawLyrics: lyrics)
    }

    @Test("addSongs nadaje nowe id pieśniom, których id już jest w bibliotece")
    func addSongsReassignsCollidingIDs() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let existing = song("W bibliotece")
        store.songs = [existing]

        store.addSongs([song("Z importu", id: existing.id)])

        #expect(store.songs.count == 2)
        #expect(Set(store.songs.map(\.id)).count == 2)
        #expect(store.songs.first { $0.title == "W bibliotece" }?.id == existing.id)
    }

    @Test("addSongs rozdziela też powtórzone id wewnątrz importu, razem z id slajdów")
    func addSongsReassignsIDsWithinBatch() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.songs = []
        let shared = UUID()
        let first = song("A", "Pierwsza\n\nDruga", id: shared)
        var second = song("B", "Trzecia\n\nCzwarta", id: shared)
        second.slides = first.slides

        store.addSongs([first, second])

        #expect(Set(store.songs.map(\.id)).count == 2)
        let slideIDs = store.songs.flatMap(\.slides).map(\.id)
        #expect(Set(slideIDs).count == slideIDs.count)
    }

    @Test("addSong z zajętym id nie tworzy duplikatu")
    func addSongReassignsCollidingID() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let existing = song("Istniejąca")
        store.songs = [existing]

        store.addSong(song("Nowa", id: existing.id))

        #expect(Set(store.songs.map(\.id)).count == 2)
        #expect(store.selectedSong?.title == "Nowa")
    }

    @Test("Ponowny import własnego eksportu: kolizje ≥ 90% domyślnie pomijane")
    func reimportSkipsNearIdenticalCollisions() {
        let library = [song("Barka", "Pan kiedyś stanął nad brzegiem szukał ludzi gotowych pójść za Nim")]
        let incoming = library + [song("Nowa pieśń", "Zupełnie inny tekst tej nowej pieśni o czymś innym")]

        let result = SongDeduplicationService.shared.processAndDeduplicate(incoming: incoming, existingLibrary: library)
        let toCommit = result.songsToCommit(workingSongs: result.uniqueSongs, duplicateSkips: [:], collisionSkips: [:])

        #expect(Set(result.uniqueSongs.map(\.id)).isDisjoint(with: library.map(\.id)))
        #expect(result.existingCollisions.count == 1)
        #expect(result.existingCollisions.first?.shouldSkipDuplicate == true)
        #expect(toCommit.map(\.title) == ["Nowa pieśń"])
    }

    @Test("Kolizja z niską zgodnością jest domyślnie importowana, a decyzję można zmienić")
    func lowSimilarityCollisionIsImportedByDefault() throws {
        let library = [song("Barka", "Pan kiedyś stanął nad brzegiem szukał ludzi gotowych pójść za Nim")]
        let incoming = [song("Barka", "Całkiem inna pieśń o tym samym tytule z innym tekstem")]

        let result = SongDeduplicationService.shared.processAndDeduplicate(incoming: incoming, existingLibrary: library)
        let collision = try #require(result.existingCollisions.first)

        #expect(collision.shouldSkipDuplicate == false)
        #expect(result.songsToCommit(workingSongs: result.uniqueSongs, duplicateSkips: [:], collisionSkips: [:]).count == 1)
        #expect(result.songsToCommit(workingSongs: result.uniqueSongs, duplicateSkips: [:], collisionSkips: [collision.id: true]).isEmpty)
    }
}
