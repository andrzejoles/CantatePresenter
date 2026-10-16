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
}

// MARK: - Update Service

/// Automatyczne aktualizacje przez Sparkle: sprawdzanie raz dziennie i na żądanie (menu aplikacji).
/// Pobrane wydanie musi mieć ważny podpis EdDSA kluczem właściciela (docs/RELEASE.md).
@MainActor
public final class UpdateService: NSObject, SPUUpdaterDelegate {
    public static let shared = UpdateService()
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "updates")
    
    private let configuration = UpdateConfiguration.from(infoDictionary: Bundle.main.infoDictionary,
                                                         environment: ProcessInfo.processInfo.environment)
    private var controller: SPUStandardUpdaterController?
    
    public var isAvailable: Bool { controller != nil }
    
    public func start() {
        guard controller == nil else { return }
        guard configuration.isComplete else {
            Self.logger.notice("Aktualizacje wyłączone: brak SUFeedURL lub SUPublicEDKey w Info.plist")
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }
    
    @objc public func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
    
    public var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }
    
    // MARK: - SPUUpdaterDelegate
    
    nonisolated public func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["CANTATE_UPDATE_FEED"]
    }
}
