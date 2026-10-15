import Foundation
import AppKit

public final class AppInstallerService {
    public static let shared = AppInstallerService()
    
    private init() {}
    
    public var isInstalledInApplications: Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasPrefix("/Applications/") || bundlePath.contains("/Applications/CantatePresenter.app")
    }
    
    public var isRunningFromDiskImage: Bool {
        return Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }
    
    public func promptToInstallIfNecessary() {
        // Only prompt if not already in /Applications
        guard !isInstalledInApplications else { return }
        
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "suppress_move_to_applications") { return }
        
        // Show after a tiny delay so the main window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let alert = NSAlert()
            alert.messageText = "Zainstalować CantatePresenter w folderze Programy?"
            alert.informativeText = "Aplikacja została uruchomiona z lokalizacji:\n\(Bundle.main.bundlePath)\n\nAby program był łatwo dostępny w Launchpadzie, Docku i Spotlight, zaleca się zainstalowanie go w folderze Programy (/Applications)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Zainstaluj w Programach")
            alert.addButton(withTitle: "Uruchom stąd")
            alert.addButton(withTitle: "Nie pytaj ponownie")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.installToApplications()
            } else if response == .alertThirdButtonReturn {
                defaults.set(true, forKey: "suppress_move_to_applications")
            }
        }
    }
    
    public func installToApplications() {
        let fileManager = FileManager.default
        let currentAppPath = Bundle.main.bundlePath
        let destAppPath = "/Applications/CantatePresenter.app"
        
        // Check if we are already in /Applications
        if currentAppPath == destAppPath {
            let alert = NSAlert()
            alert.messageText = "Program jest już zainstalowany"
            alert.informativeText = "CantatePresenter znajduje się już w folderze /Applications."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        
        do {
            if fileManager.fileExists(atPath: destAppPath) {
                // If it already exists, create temporary backup and replace
                let tempBackup = "/Applications/CantatePresenter.app.old-\(UUID().uuidString)"
                try fileManager.moveItem(atPath: destAppPath, toPath: tempBackup)
                
                do {
                    try fileManager.copyItem(atPath: currentAppPath, toPath: destAppPath)
                    try? fileManager.removeItem(atPath: tempBackup)
                } catch {
                    // Restore backup if copy failed
                    try? fileManager.moveItem(atPath: tempBackup, toPath: destAppPath)
                    throw error
                }
            } else {
                try fileManager.copyItem(atPath: currentAppPath, toPath: destAppPath)
            }
            
            // Launch new app from /Applications
            let destURL = URL(fileURLWithPath: destAppPath)
            NSWorkspace.shared.openApplication(at: destURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Błąd instalacji"
            errorAlert.informativeText = "Nie udało się skopiować aplikacji do /Applications:\n\(error.localizedDescription)\n\nMożesz ręcznie przeciągnąć plik CantatePresenter.app do folderu Programy w Finderze."
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
}
