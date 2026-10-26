import Foundation
import AppKit
import os

// MARK: - App Installer

/// Kopiowanie aplikacji do folderu Programy, gdy działa spoza niego (np. prosto z obrazu DMG).
@MainActor
public final class AppInstallerService {
    public static let shared = AppInstallerService()

    nonisolated private static let logger = Logger(subsystem: "com.cantate.presenter", category: "installer")
    private static let suppressKey = "suppress_move_to_applications"
    static let destinationPath = "/Applications/CantatePresenter.app"

    private init() {}

    public var isInstalledInApplications: Bool {
        Self.isInstalled(bundlePath: Bundle.main.bundlePath)
    }

    /// Zainstalowana to ta w /Applications albo ~/Applications. Kopia uruchomiona z pobranego pliku w kwarantannie
    /// działa z losowej ścieżki w /private/var/folders (App Translocation), więc nie uchodzi za zainstalowaną.
    nonisolated static func isInstalled(bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        let folders = ["/Applications", (home as NSString).appendingPathComponent("Applications")]
        return folders.contains { path.hasPrefix($0 + "/") }
    }

    public func promptToInstallIfNecessary() {
        guard !isInstalledInApplications, !UserDefaults.standard.bool(forKey: Self.suppressKey) else { return }

        // Chwila na pokazanie okna głównego
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let alert = NSAlert()
            alert.messageText = Lnow("Zainstalować CantatePresenter w folderze Programy?")
            alert.informativeText = Lnow("Aplikacja została uruchomiona z lokalizacji:\n{0}\n\nAby program był łatwo dostępny w Launchpadzie, Docku i Spotlight, zaleca się zainstalowanie go w folderze Programy (/Applications).", Bundle.main.bundlePath)
            alert.alertStyle = .informational
            alert.addButton(withTitle: Lnow("Zainstaluj w Programach"))
            alert.addButton(withTitle: Lnow("Uruchom stąd"))
            alert.addButton(withTitle: Lnow("Nie pytaj ponownie"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.installToApplications()
            } else if response == .alertThirdButtonReturn {
                UserDefaults.standard.set(true, forKey: Self.suppressKey)
            }
        }
    }

    public func installToApplications() {
        let currentAppPath = Bundle.main.bundlePath
        let destination = URL(fileURLWithPath: Self.destinationPath)

        if (currentAppPath as NSString).standardizingPath == destination.path {
            let alert = NSAlert()
            alert.messageText = Lnow("Program jest już zainstalowany")
            alert.informativeText = Lnow("CantatePresenter znajduje się już w folderze /Applications.")
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        do {
            try Self.install(from: URL(fileURLWithPath: currentAppPath), to: destination)
            relaunch(at: destination)
        } catch {
            Self.logger.error("Instalacja w /Applications: \(String(describing: error), privacy: .public)")
            let errorAlert = NSAlert()
            errorAlert.messageText = Lnow("Błąd instalacji")
            errorAlert.informativeText = Lnow("Nie udało się skopiować aplikacji do /Applications:\n{0}\n\nMożesz ręcznie przeciągnąć plik CantatePresenter.app do folderu Programy w Finderze.", error.localizedDescription)
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }

    // MARK: - Copy

    /// Kopiowanie się nie udało i poprzedniej wersji nie dało się odłożyć z powrotem.
    struct RestoreFailed: LocalizedError {
        let copyError: Error
        let backup: URL
        var errorDescription: String? {
            "\(copyError.localizedDescription)\n\(Lnow("Poprzednia wersja programu jest w {0}.", backup.path))"
        }
    }

    /// Kopiuje pakiet na miejsce `destination`. Poprzednia wersja jest odkładana obok i wraca, gdy kopiowanie się nie uda.
    /// Kopia nie dziedziczy kwarantanny: użytkownik uruchomił już ten program, a z atrybutem macOS uruchamiałby
    /// kopię z /Applications dalej z losowej ścieżki (App Translocation).
    nonisolated static func install(from source: URL, to destination: URL, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: destination.path) {
            let backup = destination.deletingLastPathComponent()
                .appendingPathComponent("\(destination.lastPathComponent).old-\(UUID().uuidString)")
            try fileManager.moveItem(at: destination, to: backup)
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                do {
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.moveItem(at: backup, to: destination)
                } catch let restoreError {
                    logger.error("Nie przywrócono poprzedniej wersji: \(String(describing: restoreError), privacy: .public)")
                    throw RestoreFailed(copyError: error, backup: backup)
                }
                throw error
            }
            do {
                try fileManager.removeItem(at: backup)
            } catch {
                logger.error("Nie usunięto poprzedniej wersji \(backup.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        removeQuarantine(at: destination)
    }

    nonisolated private static func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("xattr: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Relaunch

    /// Pomocnik czekający na zamknięcie tej instancji; `nil`, gdy żaden nie działa.
    private var pendingRelaunch: RelaunchHelper?

    /// Uruchamia kopię z `destination` dopiero po zamknięciu tej instancji. `NSWorkspace.openApplication` przy działającym
    /// programie o tym samym identyfikatorze tylko by go aktywował, a dwie instancje naraz zapisywałyby te same dane.
    private func relaunch(at destination: URL) {
        let helper = RelaunchHelper(waitingFor: ProcessInfo.processInfo.processIdentifier, open: destination.path)
        do {
            try helper.start()
            pendingRelaunch = helper
        } catch {
            Self.logger.error("Ponowne uruchomienie: \(String(describing: error), privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    /// Zamknięcie zostało anulowane (np. „Anuluj” w trakcie projekcji, R7-04): kopia z /Applications nie może
    /// wystartować sama później, przy zamknięciu albo awarii tej instancji.
    public func cancelPendingRelaunch() {
        guard let helper = pendingRelaunch else { return }
        helper.cancel()
        pendingRelaunch = nil
        Self.logger.notice("Zamknięcie anulowane; kopia z /Applications nie zostanie uruchomiona")
    }
}

// MARK: - Relaunch Helper

/// `/bin/sh` czekający, aż proces `pid` się zakończy, a potem otwierający `path`.
final class RelaunchHelper {
    private let process = Process()

    init(waitingFor pid: Int32, open path: String, opener: String = "/usr/bin/open") {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // PID i ścieżka jako argumenty pozycyjne, nie wklejane w skrypt.
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; \"$3\" \"$2\"",
            "relaunch", String(pid), path, opener
        ]
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        try process.run()
    }

    func cancel() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}
