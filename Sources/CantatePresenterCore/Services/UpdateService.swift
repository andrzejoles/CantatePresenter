import Foundation
import AppKit
import Sparkle
import os

// MARK: - Update Configuration

/// Ustawienia automatycznych aktualizacji (Sparkle) zapisane w Info.plist przez `build_app.sh`.
/// Bez publicznego klucza EdDSA albo adresu kanału aktualizacje są wyłączone (np. przy `swift run`).
struct UpdateConfiguration: Equatable {
    var feedURL: String
    var publicKey: String
    
    var isComplete: Bool {
        !publicKey.isEmpty && (URL(string: feedURL)?.scheme == "https" || URL(string: feedURL)?.scheme == "http")
    }
    
    /// `CANTATE_UPDATE_FEED` zastępuje adres kanału (próby z lokalnym serwerem).
    static func from(infoDictionary: [String: Any]?, environment: [String: String]) -> UpdateConfiguration {
        UpdateConfiguration(
            feedURL: environment["CANTATE_UPDATE_FEED"] ?? infoDictionary?["SUFeedURL"] as? String ?? "",
            publicKey: infoDictionary?["SUPublicEDKey"] as? String ?? ""
        )
    }

    /// Adres kanału dla Sparkle, gdy różni się od `SUFeedURL` z Info.plist (`CANTATE_UPDATE_FEED`);
    /// `nil` = Sparkle bierze adres z Info.plist. Jedno źródło prawdy zamiast drugiego odczytu zmiennej (R5-06).
    func feedOverride(infoDictionary: [String: Any]?) -> String? {
        feedURL != (infoDictionary?["SUFeedURL"] as? String ?? "") ? feedURL : nil
    }
}

// MARK: - Update Presentation Policy

/// Kiedy Sparkle może sprawdzać i pokazywać aktualizacje (R12-03). Okno aktualizacji w trakcie projekcji
/// byłoby pod oknem projekcji albo przejmowałoby klawiaturę z przyciskiem „Zainstaluj” pod Enterem.
enum UpdatePresentationPolicy {
    /// Zaplanowane sprawdzenie (w tle) czeka do końca projekcji; polecenie z menu działa zawsze.
    static func mayCheck(userInitiated: Bool, isProjecting: Bool) -> Bool {
        userInitiated || !isProjecting
    }

    /// Sparkle sam pokazuje znalezione wydanie tylko wtedy, gdy chce je pokazać od razu, i nie w trakcie
    /// projekcji. W pozostałych przypadkach odkładał je do najbliższej aktywacji aplikacji, która może
    /// wypaść w trakcie projekcji; takie przypomnienie pokazuje `UpdateService`.
    static func sparkleShowsScheduledUpdate(immediateFocus: Bool, isProjecting: Bool) -> Bool {
        immediateFocus && !isProjecting
    }

    /// Odłożone przypomnienie: aplikacja aktywna i nic nie jest wyświetlane.
    static func showsPendingUpdate(appIsActive: Bool, isProjecting: Bool) -> Bool {
        appIsActive && !isProjecting
    }

    /// „Sprawdź uaktualnienia...”: nie w trakcie sprawdzania i nie pod oknem projekcji (R8-02).
    @MainActor
    static func isCheckMenuItemEnabled(canCheckForUpdates: Bool, presentationCoversMainWindow: Bool) -> Bool {
        canCheckForUpdates && AppDelegate.isMenuItemEnabled(
            action: #selector(UpdateService.checkForUpdates(_:)),
            hasAttachedSheet: false,
            canUndoRestore: true,
            presentationCoversMainWindow: presentationCoversMainWindow
        )
    }
}

// MARK: - Update Service

/// Automatyczne aktualizacje przez Sparkle: sprawdzanie raz dziennie i na żądanie (menu aplikacji).
/// Pobrane wydanie musi mieć ważny podpis EdDSA kluczem właściciela (docs/RELEASE.md).
@MainActor
public final class UpdateService: NSObject, SPUUpdaterDelegate {
    public static let shared = UpdateService()
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "updates")
    
    private let configuration: UpdateConfiguration
    nonisolated private let feedOverride: String?
    private var controller: SPUStandardUpdaterController?
    /// Wydanie znalezione w tle, którego Sparkle nie pokazał (projekcja albo nieodpowiedni moment), R12-03.
    private var hasPendingUpdate = false
    /// Zaplanowane sprawdzenie pominięte w trakcie projekcji; ponawiane po jej końcu.
    private var skippedScheduledCheck = false
    
    public var isAvailable: Bool { controller != nil }

    override private init() {
        let info = Bundle.main.infoDictionary
        configuration = UpdateConfiguration.from(infoDictionary: info, environment: ProcessInfo.processInfo.environment)
        feedOverride = configuration.feedOverride(infoDictionary: info)
        super.init()
    }
    
    public func start() {
        guard controller == nil else { return }
        guard configuration.isComplete else {
            Self.logger.notice("Aktualizacje wyłączone: brak SUFeedURL lub SUPublicEDKey w Info.plist")
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        ProjectionActivity.shared.addObserver { [weak self] projecting in
            if !projecting { self?.projectionDidEnd() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPendingUpdateIfPossible() }
        }
    }
    
    @objc public func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
    
    public var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }
    
    private var isProjecting: Bool { ProjectionActivity.shared.isProjecting }
    
    private func projectionDidEnd() {
        if skippedScheduledCheck {
            skippedScheduledCheck = false
            controller?.updater.checkForUpdatesInBackground()
        }
        showPendingUpdateIfPossible()
    }
    
    /// Przypomnienie o wydaniu odłożonym w trakcie projekcji; `checkForUpdates` przywołuje okno Sparkle.
    private func showPendingUpdateIfPossible() {
        guard hasPendingUpdate, UpdatePresentationPolicy.showsPendingUpdate(appIsActive: NSApp.isActive, isProjecting: isProjecting) else { return }
        hasPendingUpdate = false
        controller?.checkForUpdates(nil)
    }
    
    // MARK: - SPUUpdaterDelegate
    
    nonisolated public func feedURLString(for updater: SPUUpdater) -> String? {
        feedOverride
    }
    
    public func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !UpdatePresentationPolicy.mayCheck(userInitiated: updateCheck == .updates, isProjecting: isProjecting) else { return }
        skippedScheduledCheck = true
        throw NSError(domain: "com.cantate.presenter.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update check deferred during projection"])
    }
}

// MARK: - Menu Validation

extension UpdateService: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return UpdatePresentationPolicy.isCheckMenuItemEnabled(
            canCheckForUpdates: canCheckForUpdates,
            presentationCoversMainWindow: ScreenManager.shared.presentationCoversMainWindow
        )
    }
}

// MARK: - SPUStandardUserDriverDelegate (R12-03)

/// Delikatne przypomnienia Sparkle: zaplanowane wydanie nie wyskakuje w trakcie projekcji.
/// Sparkle wywołuje te metody na wątku głównym.
extension UpdateService: SPUStandardUserDriverDelegate {
    nonisolated public var supportsGentleScheduledUpdateReminders: Bool { true }
    
    nonisolated public func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        MainActor.assumeIsolated {
            UpdatePresentationPolicy.sparkleShowsScheduledUpdate(immediateFocus: immediateFocus, isProjecting: isProjecting)
        }
    }
    
    nonisolated public func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            // Jak Sparkle: okno pojawi się przy następnej aktywacji aplikacji albo po końcu projekcji.
            hasPendingUpdate = true
        }
    }
    
    nonisolated public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { hasPendingUpdate = false }
    }
    
    nonisolated public func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { hasPendingUpdate = false }
    }
}
