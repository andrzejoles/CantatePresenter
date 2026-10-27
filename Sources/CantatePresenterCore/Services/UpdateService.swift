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
        feedOverride
    }
}
