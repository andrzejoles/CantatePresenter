import Foundation
import Combine
import Observation

// MARK: - Display Sleep Blocker

/// Blokada usypiania ekranów na czas projekcji; w testach atrapa bez prawdziwej blokady (R12-02).
@MainActor
protocol DisplaySleepBlocker: AnyObject {
    func begin(reason: String)
    func end()
}

/// `ProcessInfo.beginActivity` z `.idleDisplaySleepDisabled`: ekrany (i projektor) nie gasną, a wygaszacz
/// nie startuje, choć nikt nie dotyka Maca (pilot w telefonie, długie kazanie z planszą).
@MainActor
final class ProcessInfoDisplaySleepBlocker: DisplaySleepBlocker {
    private var activity: (any NSObjectProtocol)?

    func begin(reason: String) {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: reason)
    }

    func end() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}

// MARK: - Projection Activity

/// Czy trwa projekcja: okno projekcji otwarte albo tekst na żywo. Na ten czas ekrany nie usypiają (R12-02),
/// a Sparkle nie pokazuje okna aktualizacji (R12-03).
@MainActor
public final class ProjectionActivity {
    public static let shared = ProjectionActivity(blocker: ProcessInfoDisplaySleepBlocker())

    private let blocker: DisplaySleepBlocker
    public private(set) var isProjecting = false
    private var observers: [(Bool) -> Void] = []
    private var presentationSubscription: AnyCancellable?

    init(blocker: DisplaySleepBlocker) {
        self.blocker = blocker
    }

    /// Wywoływane przy każdej zmianie stanu; blokada jest brana i zwalniana parami.
    func update(isPresentationActive: Bool, isLive: Bool) {
        let projecting = isPresentationActive || isLive
        guard projecting != isProjecting else { return }
        isProjecting = projecting
        if projecting {
            blocker.begin(reason: "CantatePresenter: projekcja")
        } else {
            blocker.end()
        }
        for observer in observers {
            observer(projecting)
        }
    }

    /// `body(true)` na początku projekcji, `body(false)` po jej końcu.
    func addObserver(_ body: @escaping (Bool) -> Void) {
        observers.append(body)
    }

    /// Śledzi `ScreenManager.shared` i `DataStore.shared` (start aplikacji).
    public func start() {
        guard presentationSubscription == nil else { return }
        presentationSubscription = ScreenManager.shared.$isPresentationActive.sink { [weak self] active in
            // `@Published` wysyła nową wartość przed jej zapisaniem, więc bierzemy ją z argumentu.
            MainActor.assumeIsolated {
                self?.update(isPresentationActive: active, isLive: DataStore.shared.isLive)
            }
        }
        observeLiveState()
    }

    /// Zakończenie programu: blokada zwalniana jawnie.
    public func stop() {
        presentationSubscription = nil
        update(isPresentationActive: false, isLive: false)
    }

    private func observeLiveState() {
        withObservationTracking {
            _ = DataStore.shared.isLive
        } onChange: { [weak self] in
            // Wywoływane przed zmianą; nowy stan czytamy w następnym kroku pętli.
            Task { @MainActor in
                guard let self, self.presentationSubscription != nil else { return }
                self.update(isPresentationActive: ScreenManager.shared.isPresentationActive, isLive: DataStore.shared.isLive)
                self.observeLiveState()
            }
        }
    }
}
