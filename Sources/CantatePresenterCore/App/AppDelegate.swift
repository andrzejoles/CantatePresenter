import Foundation
import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) var shared: AppDelegate?
    public var mainWindow: NSWindow?
    private var exitBackupCoordinator: ExitBackupCoordinator?
    
    public override init() {
        super.init()
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        
        setupMainMenu()
        setupMainWindow()
        KeyboardMonitor.shared.start()
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    private func setupMainWindow() {
        let rootView = MainView()
        let hostingController = NSHostingController(rootView: rootView)
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let windowWidth: CGFloat = min(1280, screenRect.width * 0.85)
        let windowHeight: CGFloat = min(820, screenRect.height * 0.85)
        let initialRect = NSRect(
            x: screenRect.midX - windowWidth / 2,
            y: screenRect.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )
        
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "CantatePresenter — Prezenter Pieśni & Słowa"
        window.minSize = NSSize(width: 950, height: 600)
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        self.mainWindow = window
        // SwiftUI daje fokus pierwszemu polu tekstowemu (wyszukiwanie), przez co klawisze pisały w nim
        // zamiast sterować slajdami. Pole staje się aktywne dopiero po kliknięciu.
        for delay in [0.0, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                if window?.firstResponder is NSTextView {
                    window?.makeFirstResponder(nil)
                }
            }
        }
        AppInstallerService.shared.promptToInstallIfNecessary()
    }
    
    private var manualWindow: NSWindow?
    
    @objc public func openUserManualAction() {
        Task { @MainActor in
            if let window = self.manualWindow, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return
            }
            
            let manualView = UserManualView()
            let hostingController = NSHostingController(rootView: manualView)
            
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1000, height: 750)
            let windowWidth: CGFloat = min(980, screenRect.width * 0.82)
            let windowHeight: CGFloat = min(740, screenRect.height * 0.85)
            let initialRect = NSRect(
                x: screenRect.midX - windowWidth / 2 + 30,
                y: screenRect.midY - windowHeight / 2 - 30,
                width: windowWidth,
                height: windowHeight
            )
            
            let window = NSWindow(
                contentRect: initialRect,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "Instrukcja obsługi — CantatePresenter"
            window.minSize = NSSize(width: 800, height: 550)
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            self.manualWindow = window
        }
    }
    
    @objc public func openInstructionMarkdownAction() {
        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let projectFolder = bundleURL.pathExtension == "app"
            ? bundleURL.deletingLastPathComponent()
            : URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        let docURL = projectFolder.appendingPathComponent("INSTRUKCJA.md")
        if fileManager.fileExists(atPath: docURL.path) {
            NSWorkspace.shared.open(docURL)
        } else {
            let localURL = URL(fileURLWithPath: "/Users/aoles/dev_gem/INSTRUKCJA.md")
            if fileManager.fileExists(atPath: localURL.path) {
                NSWorkspace.shared.open(localURL)
            }
        }
    }
    
    @objc public func openGitHubProjectAction() {
        if let url = URL(string: "https://github.com/andrzejoles/CantatePresenter") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "O programie CantatePresenter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        if !AppInstallerService.shared.isInstalledInApplications {
            appMenu.addItem(NSMenuItem(title: "Zainstaluj w folderze Programy (/Applications)...", action: #selector(installToApplicationsAction), keyEquivalent: ""))
            appMenu.addItem(NSMenuItem.separator())
        }
        appMenu.addItem(NSMenuItem(title: "Zakończ CantatePresenter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Plik")
        fileMenu.addItem(NSMenuItem(title: "Szybki tekst na żywo...", action: #selector(quickTextAction), keyEquivalent: "t"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Importuj pieśni...", action: #selector(importAction), keyEquivalent: "i"))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj całą bazę (JSON)...", action: #selector(exportJSONAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj pieśni do folderu (.txt)...", action: #selector(exportFolderAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Utwórz pełną kopię zapasową (.cantatebackup)...", action: #selector(createBackupAction), keyEquivalent: "b"))
        fileMenu.addItem(NSMenuItem(title: "Przywróć z kopii zapasowej...", action: #selector(restoreBackupAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "Cofnij ostatnie przywracanie...", action: #selector(undoRestoreAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Zamknij okno", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Edit Menu: bez pozycji z akcjami copy:/paste:/undo: skróty ⌘C, ⌘V, ⌘Z nie działają w polach tekstowych (W1)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edycja")
        editMenu.addItem(NSMenuItem(title: "Cofnij", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Ponów", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Usuń", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Szukaj pieśni", action: #selector(focusSongSearchAction), keyEquivalent: "f"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // View Menu (Zooming)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Widok")
        
        let zoomInItem = NSMenuItem(title: "Powiększ interfejs", action: #selector(zoomInAction), keyEquivalent: "+")
        let zoomOutItem = NSMenuItem(title: "Pomniejsz interfejs", action: #selector(zoomOutAction), keyEquivalent: "-")
        let zoomResetItem = NSMenuItem(title: "Domyślny rozmiar interfejsu (100%)", action: #selector(zoomResetAction), keyEquivalent: "0")
        
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(zoomResetItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Okno")
        windowMenu.addItem(NSMenuItem(title: "Minimalizuj", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Powiększ", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Pomoc")
        helpMenu.addItem(NSMenuItem(title: "Instrukcja obsługi CantatePresenter...", action: #selector(openUserManualAction), keyEquivalent: "?"))
        helpMenu.addItem(NSMenuItem(title: "Otwórz plik INSTRUKCJA.md...", action: #selector(openInstructionMarkdownAction), keyEquivalent: ""))
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(NSMenuItem(title: "Strona projektu na GitHub...", action: #selector(openGitHubProjectAction), keyEquivalent: ""))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }
    
    @objc private func zoomInAction() {
        Task { @MainActor in
            DataStore.shared.zoomInUI()
        }
    }
    
    @objc private func zoomOutAction() {
        Task { @MainActor in
            DataStore.shared.zoomOutUI()
        }
    }
    
    @objc private func zoomResetAction() {
        Task { @MainActor in
            DataStore.shared.resetZoomUI()
        }
    }
    
    /// Analiza w tle, przegląd duplikatów i jeden zapis, jak w oknie Import/Eksport (S3).
    @objc private func importAction() {
        NotificationCenter.default.post(name: .openImportFlow, object: nil)
    }
    
    @objc private func exportJSONAction() {
        Task { @MainActor in
            _ = SongExporter.exportSongsAsJSONFile(DataStore.shared.songs)
        }
    }
    
    @objc private func exportFolderAction() {
        Task { @MainActor in
            _ = SongExporter.exportSongsToFolder(DataStore.shared.songs)
        }
    }
    
    @objc private func createBackupAction() {
        Task { @MainActor in
            _ = BackupService.shared.exportBackupWithSavePanel()
        }
    }
    
    @objc private func restoreBackupAction() {
        Task { @MainActor in
            let result = await BackupService.shared.restoreBackupWithOpenPanel()
            guard result.message != "Anulowano wybór pliku." else { return }
            showInfoAlert(title: result.success ? "Przywrócono kopię zapasową" : "Nie przywrócono kopii zapasowej", message: result.message, isError: !result.success)
        }
    }
    
    @MainActor @objc fileprivate func undoRestoreAction() {
        let alert = NSAlert()
        alert.messageText = "Cofnąć ostatnie przywracanie?"
        alert.informativeText = "Dane wrócą do stanu sprzed ostatniego przywrócenia kopii zapasowej. Dane z przywróconej kopii zostaną usunięte."
        alert.addButton(withTitle: "Cofnij przywracanie")
        alert.addButton(withTitle: "Anuluj")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try BackupService.shared.undoLastRestore()
            showInfoAlert(title: "Cofnięto przywracanie", message: "Przywrócono dane sprzed ostatniego przywrócenia kopii.", isError: false)
        } catch {
            showInfoAlert(title: "Nie udało się cofnąć przywracania", message: error.localizedDescription, isError: true)
        }
    }
    
    private func showInfoAlert(title: String, message: String, isError: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = isError ? .warning : .informational
        alert.runModal()
    }

    
    @objc fileprivate func focusSongSearchAction() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusSongSearch, object: nil)
    }
    
    @objc private func quickTextAction() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenQuickTextSheet"), object: nil)
    }
    
    @objc private func installToApplicationsAction() {
        AppInstallerService.shared.installToApplications()
    }
    
    // MARK: - Exit Backup (W2)
    
    /// Kopia przy zamykaniu nie może czekać na wątku głównym (zakleszczenie z `@MainActor`),
    /// więc zamknięcie jest odkładane (`.terminateLater`) do zakończenia kopii, limitu czasu albo „Pomiń”.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let googleDrive = DataStore.shared.settings.googleDrive
        guard googleDrive.isEnabled, googleDrive.autoBackupOnExit, exitBackupCoordinator == nil else {
            return .terminateNow
        }
        
        let coordinator = ExitBackupCoordinator()
        exitBackupCoordinator = coordinator
        let panel = makeExitBackupPanel(onSkip: { coordinator.skip() })
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
        Task { @MainActor in
            _ = await coordinator.run(operations: ExitBackupCoordinator.liveOperations(), timeout: .seconds(60))
            panel.close()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    
    private func makeExitBackupPanel(onSkip: @escaping () -> Void) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "CantatePresenter"
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.contentView = NSHostingView(rootView: ExitBackupProgressView(onSkip: onSkip))
        return panel
    }
}

// MARK: - Menu Validation
extension AppDelegate: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoRestoreAction) {
            return BackupService.shared.canUndoRestore
        }
        if menuItem.action == #selector(focusSongSearchAction) {
            // Nie przy otwartym arkuszu (np. Ustawieniach).
            return mainWindow?.attachedSheet == nil
        }
        return true
    }
}

// MARK: - Exit Backup Progress View
private struct ExitBackupProgressView: View {
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Tworzenie kopii zapasowej na Dysku Google…")
                    .font(.system(size: 13, weight: .medium))
            }
            Text("Jeśli wysyłka się nie uda, kopia zostanie zapisana lokalnie.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("Pomiń i zamknij", action: onSkip)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 380)
    }
}
