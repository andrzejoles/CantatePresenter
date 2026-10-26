import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-01: klawisze slajdów po zatrzymaniu projekcji

@MainActor
@Suite("Nawigacja slajdów tylko w trakcie projekcji (R4-01)")
struct LiveNavigationTests {
    private func makeStore(_ dir: TestDirectory) -> (DataStore, [Song]) {
        let store = DataStore(dataDirectory: dir.url)
        let songs = [
            Song(title: "Pierwsza", rawLyrics: "A1\n\nA2"),
            Song(title: "Druga", rawLyrics: "B1\n\nB2")
        ]
        store.songs = songs
        store.plans = [ServicePlan(name: "Niedziela", items: songs.map { PlanItem(songId: $0.id) })]
        store.activePlanId = store.plans[0].id
        return (store, songs)
    }

    @Test("Po Esc strzałka w prawo na ostatnim slajdzie nie wyświetla następnej pieśni z planu")
    func nextSlideAfterStopDoesNotGoLive() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)
        store.present(song: songs[0], slideIndex: 1)
        store.stopLive()

        store.nextSlide()

        #expect(!store.isLive)
        #expect(store.activeSong?.id == songs[0].id)
        #expect(store.activeSlideIndex == 1)
    }

    @Test("Po Esc strzałki, refren i cyfry nie zmieniają ukrytego slajdu")
    func slideKeysIgnoredWhenStopped() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)
        store.present(song: songs[0], slideIndex: 1)
        store.stopLive()

        store.prevSlide()
        store.jumpToVerse(number: 1)
        store.jumpToChorus()
        store.jumpToSlide(index: 0)

        #expect(!store.isLive)
        #expect(store.activeSlideIndex == 1)
    }

    @Test("W trakcie projekcji strzałka w prawo na ostatnim slajdzie przechodzi do następnej pieśni z planu")
    func nextSlideWhileLiveContinuesPlan() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let (store, songs) = makeStore(dir)
        store.present(song: songs[0], slideIndex: 1)

        store.nextSlide()

        #expect(store.isLive)
        #expect(store.activeSong?.id == songs[1].id)
    }
}
