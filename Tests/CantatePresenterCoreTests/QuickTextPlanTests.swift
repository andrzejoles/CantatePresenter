import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N11: plan po „szybkim tekście”

@MainActor
@Suite("Plan po szybkim tekście (N11)")
struct QuickTextPlanTests {
    private func makeStore(_ dir: TestDirectory) -> (DataStore, [Song]) {
        let store = DataStore(dataDirectory: dir.url)
        let songs = (1...3).map { Song(title: "Pieśń \($0)", rawLyrics: "Tekst \($0)") }
        store.songs = songs
        store.plans = [ServicePlan(name: "Niedziela", items: songs.map { PlanItem(songId: $0.id) })]
        store.activePlanId = store.plans[0].id
        return (store, songs)
    }

    @Test("Po szybkim tekście „następna pieśń” to kolejna po ostatniej z planu, nie pierwsza")
    func nextAfterQuickText() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)
        store.present(song: songs[1])

        store.presentQuickText(text: "Ogłoszenie parafialne")
        store.nextSongInPlan()

        #expect(store.activeSong?.id == songs[2].id)
    }

    @Test("Po szybkim tekście „poprzednia pieśń” to ta przed ostatnią z planu")
    func prevAfterQuickText() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)
        store.present(song: songs[1])

        store.presentQuickText(text: "Ogłoszenie")
        store.prevSongInPlan()

        #expect(store.activeSong?.id == songs[0].id)
    }

    @Test("Bez wcześniejszej pieśni z planu „następna” zaczyna od pierwszej")
    func nextWithoutAnchor() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)

        store.presentQuickText(text: "Powitanie")
        store.nextSongInPlan()

        #expect(store.activeSong?.id == songs[0].id)
    }
}

// MARK: - R4-06: edycja szybkiego tekstu

@MainActor
@Suite("Edycja szybkiego tekstu (R4-06)")
struct QuickTextEditTests {
    @Test("Zapis w edytorze zmienia szybki tekst na ekranie, a biblioteka zostaje bez zmian")
    func editingQuickTextUpdatesScreen() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let librarySize = store.songs.count
        store.presentQuickText(text: "Ogłoszenie")
        var edited = try #require(store.selectedSong)
        edited.rawLyrics = "Ogłoszenie poprawione\n\nDruga część"
        edited.slides = Song.parseLyrics(edited.rawLyrics)

        store.updateSong(edited)

        #expect(store.selectedSong?.rawLyrics == edited.rawLyrics)
        #expect(store.activeSong?.slides.count == 2)
        #expect(store.currentLiveSlide?.text == "Ogłoszenie poprawione")
        #expect(store.songs.count == librarySize)
    }
}
