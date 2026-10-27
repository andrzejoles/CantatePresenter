import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R12-02: ekrany nie usypiają w trakcie projekcji

@MainActor
private final class FakeDisplaySleepBlocker: DisplaySleepBlocker {
    private(set) var begins = 0
    private(set) var ends = 0
    var isHeld: Bool { begins > ends }

    func begin(reason: String) { begins += 1 }
    func end() { ends += 1 }
}

@MainActor
@Suite("Blokada usypiania ekranów w trakcie projekcji (R12-02)")
struct ProjectionActivityTests {
    @Test("Okno projekcji albo tekst na żywo biorą blokadę raz, koniec obu ją zwalnia")
    func pairsBeginAndEnd() {
        let blocker = FakeDisplaySleepBlocker()
        let activity = ProjectionActivity(blocker: blocker)
        var changes: [Bool] = []
        activity.addObserver { changes.append($0) }

        activity.update(isPresentationActive: true, isLive: false)
        activity.update(isPresentationActive: true, isLive: true)
        #expect(blocker.begins == 1 && blocker.isHeld && activity.isProjecting)

        // Okno projekcji zamknięte, tekst nadal na żywo (np. okno testowe): blokada zostaje.
        activity.update(isPresentationActive: false, isLive: true)
        #expect(blocker.isHeld)

        activity.update(isPresentationActive: false, isLive: false)
        #expect(blocker.begins == 1 && blocker.ends == 1 && !blocker.isHeld && !activity.isProjecting)
        #expect(changes == [true, false])
    }

    @Test("Bez projekcji nic nie jest brane ani zwalniane")
    func idleDoesNothing() {
        let blocker = FakeDisplaySleepBlocker()
        let activity = ProjectionActivity(blocker: blocker)
        activity.update(isPresentationActive: false, isLive: false)
        activity.stop()
        #expect(blocker.begins == 0 && blocker.ends == 0)
    }

    @Test("Zakończenie programu w trakcie projekcji zwalnia blokadę")
    func stopReleases() {
        let blocker = FakeDisplaySleepBlocker()
        let activity = ProjectionActivity(blocker: blocker)
        activity.update(isPresentationActive: true, isLive: true)
        activity.stop()
        #expect(blocker.begins == 1 && blocker.ends == 1)
    }
}
