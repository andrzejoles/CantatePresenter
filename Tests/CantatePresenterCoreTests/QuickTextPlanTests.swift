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

// MARK: - R13-01: ta sama pieśń dwa razy w planie

@MainActor
@Suite("Pieśń powtórzona w planie (R13-01)")
struct RepeatedPlanSongTests {
    /// Plan: A, B, A, C (np. pieśń na wejście powtórzona na zakończenie).
    private func makeStore(_ dir: TestDirectory) -> (DataStore, [Song], ServicePlan) {
        let store = DataStore(dataDirectory: dir.url)
        let songs = ["A", "B", "C"].map { Song(title: $0, rawLyrics: "Tekst \($0)") }
        store.songs = songs
        let plan = ServicePlan(name: "Niedziela", items: [songs[0], songs[1], songs[0], songs[2]].map { PlanItem(songId: $0.id) })
        store.plans = [plan]
        store.activePlanId = plan.id
        return (store, songs, plan)
    }

    @Test("Następna pieśń po drugim wystąpieniu to pieśń po nim, nie powrót do pozycji po pierwszym")
    func nextAfterSecondOccurrence() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs, plan) = makeStore(dir)
        store.present(song: songs[0], planItemId: plan.items[2].id)

        store.nextSongInPlan()

        #expect(store.activeSong?.id == songs[2].id)
        #expect(store.livePlanItemId == plan.items[3].id)
    }

    @Test("Przechodzenie klawiszem przez cały plan nie zapętla się na powtórzonej pieśni")
    func walkingThroughPlan() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs, plan) = makeStore(dir)
        store.nextSongInPlan()
        var visited = [store.livePlanItemId]
        for _ in 0..<5 {
            store.nextSongInPlan()
            visited.append(store.livePlanItemId)
        }

        #expect(Array(visited.prefix(4)) == plan.items.map(\.id))
        #expect(store.activeSong?.id == songs[2].id)
        store.prevSongInPlan()
        #expect(store.livePlanItemId == plan.items[2].id)
        store.prevSongInPlan()
        #expect(store.livePlanItemId == plan.items[1].id)
    }

    @Test("Po szybkim tekście kolejność liczy się od pozycji w planie, nie od pierwszego wystąpienia pieśni")
    func quickTextKeepsPosition() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs, plan) = makeStore(dir)
        store.present(song: songs[0], planItemId: plan.items[2].id)

        store.presentQuickText(text: "Ogłoszenia")
        store.nextSongInPlan()

        #expect(store.activeSong?.id == songs[2].id)
    }

    @Test("Pilot zaznacza jako bieżącą tylko wyświetlaną pozycję planu")
    func remoteMarksOnlyCurrentItem() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs, plan) = makeStore(dir)
        RemoteControlBridge.perform(.planItem(2), on: store)

        let state = RemoteControlBridge.state(of: store)
        #expect(store.activeSong?.id == songs[0].id)
        #expect(state.plan.map(\.isCurrent) == [false, false, true, false])
        #expect(store.livePlanItemId == plan.items[2].id)
    }

    @Test("Pieśń spoza planu wybrana bez pozycji: pierwsze wystąpienie, a przy kolejnym wyborze zostaje bieżąca pozycja")
    func presentWithoutItemPicksFirstOccurrence() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs, plan) = makeStore(dir)
        store.present(song: songs[0])
        #expect(store.livePlanItemId == plan.items[0].id)

        store.present(song: songs[0], planItemId: plan.items[2].id)
        store.present(song: songs[0], slideIndex: 0)
        #expect(store.livePlanItemId == plan.items[2].id)
    }
}

// MARK: - R13-04: usunięcie wyświetlanej pieśni

@MainActor
@Suite("Usunięcie pieśni z ekranu (R13-04)")
struct DeleteActiveSongTests {
    @Test("Usunięta pieśń znika z ekranu i nie wraca przez „Start” pilota")
    func deletedSongIsNotResumed() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let song = Song(title: "Do usunięcia", rawLyrics: "Tekst\n\nDruga")
        let other = Song(title: "Zostaje", rawLyrics: "Inny tekst")
        store.songs = [song, other]
        store.selectedSongId = other.id
        store.present(song: song, slideIndex: 1)
        store.stopLive()

        store.deleteSong(id: song.id)

        #expect(store.activeSong == nil)
        #expect(store.activeSlideIndex == 0)
        #expect(RemoteControlBridge.startCandidate(in: store)?.id == other.id)
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
