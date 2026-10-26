import Foundation
import AppKit
import SwiftUI

@MainActor
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
        
        Localization.currentLanguage = DataStore.shared.settings.appLanguage
        UpdateService.shared.start()
        setupMainMenu()
        setupMainWindow()
        KeyboardMonitor.shared.start()
        NotificationCenter.default.addObserver(forName: .appLanguageDidChange, object: nil, queue: .main) { [weak self] _ in
            // Menu i tytuł okna AppKit nie odświeżają się same jak widoki SwiftUI.
            MainActor.assumeIsolated {
                self?.setupMainMenu()
                self?.mainWindow?.title = Lnow("CantatePresenter — Prezenter Pieśni & Słowa")
            }
        }
        
        NSApp.activate()
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
        
        window.title = Lnow("CantatePresenter — Prezenter Pieśni & Słowa")
        window.minSize = NSSize(width: 950, height: 600)
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Okno projekcji też jest oknem, więc bez tego zamknięcie okna głównego zostawiało projekcję na ekranie.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                ScreenManager.shared.stopPresentation(restoringMainWindow: false)
                ScreenManager.shared.stopWindowedPreview()
                NSApp.terminate(nil)
            }
        }
        
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
            
            window.title = Lnow("Instrukcja obsługi — CantatePresenter")
            window.minSize = NSSize(width: 800, height: 550)
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            self.manualWindow = window
        }
    }
    
    @objc public func openInstructionMarkdownAction() {
        if let url = AppPaths.userGuideFile {
            NSWorkspace.shared.open(url)
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
        appMenu.addItem(NSMenuItem(title: Lnow("O programie CantatePresenter"), action: #selector(showAboutPanelAction), keyEquivalent: ""))
        // Menu buduje się na wątku głównym (start aplikacji i zmiana języka).
        if let updater = MainActor.assumeIsolated({ UpdateService.shared.isAvailable ? UpdateService.shared : nil }) {
            let updates = NSMenuItem(title: Lnow("Sprawdź uaktualnienia..."), action: #selector(UpdateService.checkForUpdates(_:)), keyEquivalent: "")
            updates.target = updater
            appMenu.addItem(updates)
        }
        appMenu.addItem(NSMenuItem.separator())
        if !AppInstallerService.shared.isInstalledInApplications {
            appMenu.addItem(NSMenuItem(title: Lnow("Zainstaluj w folderze Programy (/Applications)..."), action: #selector(installToApplicationsAction), keyEquivalent: ""))
            appMenu.addItem(NSMenuItem.separator())
        }
        appMenu.addItem(NSMenuItem(title: Lnow("Zakończ CantatePresenter"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: Lnow("Plik"))
        fileMenu.addItem(NSMenuItem(title: Lnow("Szybki tekst na żywo..."), action: #selector(quickTextAction), keyEquivalent: "t"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: Lnow("Importuj pieśni..."), action: #selector(importAction), keyEquivalent: "i"))
        fileMenu.addItem(NSMenuItem(title: Lnow("Eksportuj całą bazę (JSON)..."), action: #selector(exportJSONAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: Lnow("Eksportuj pieśni do folderu (.txt)..."), action: #selector(exportFolderAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: Lnow("Utwórz pełną kopię zapasową (.cantatebackup)..."), action: #selector(createBackupAction), keyEquivalent: "b"))
        fileMenu.addItem(NSMenuItem(title: Lnow("Przywróć z kopii zapasowej..."), action: #selector(restoreBackupAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: Lnow("Cofnij ostatnie przywracanie..."), action: #selector(undoRestoreAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: Lnow("Zamknij okno"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Edit Menu: bez pozycji z akcjami copy:/paste:/undo: skróty ⌘C, ⌘V, ⌘Z nie działają w polach tekstowych (W1)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: Lnow("Edycja"))
        editMenu.addItem(NSMenuItem(title: Lnow("Cofnij"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: Lnow("Ponów"), action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: Lnow("Wytnij"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: Lnow("Kopiuj"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: Lnow("Wklej"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: Lnow("Usuń"), action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: Lnow("Zaznacz wszystko"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: Lnow("Szukaj pieśni"), action: #selector(focusSongSearchAction), keyEquivalent: "f"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // View Menu (Zooming)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: Lnow("Widok"))
        
        let zoomInItem = NSMenuItem(title: Lnow("Powiększ interfejs"), action: #selector(zoomInAction), keyEquivalent: "+")
        let zoomOutItem = NSMenuItem(title: Lnow("Pomniejsz interfejs"), action: #selector(zoomOutAction), keyEquivalent: "-")
        let zoomResetItem = NSMenuItem(title: Lnow("Domyślny rozmiar interfejsu (100%)"), action: #selector(zoomResetAction), keyEquivalent: "0")
        
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(zoomResetItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: Lnow("Okno"))
        windowMenu.addItem(NSMenuItem(title: Lnow("Minimalizuj"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: Lnow("Powiększ"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: Lnow("Pomoc"))
        helpMenu.addItem(NSMenuItem(title: Lnow("Instrukcja obsługi CantatePresenter..."), action: #selector(openUserManualAction), keyEquivalent: "?"))
        helpMenu.addItem(NSMenuItem(title: Lnow("Otwórz plik INSTRUKCJA.md..."), action: #selector(openInstructionMarkdownAction), keyEquivalent: ""))
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(NSMenuItem(title: Lnow("Strona projektu na GitHub..."), action: #selector(openGitHubProjectAction), keyEquivalent: ""))
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
            showInfoAlert(title: result.success ? Lnow("Przywrócono kopię zapasową") : Lnow("Nie przywrócono kopii zapasowej"), message: result.message, isError: !result.success)
        }
    }
    
    @MainActor @objc fileprivate func undoRestoreAction() {
        let alert = NSAlert()
        alert.messageText = Lnow("Cofnąć ostatnie przywracanie?")
        alert.informativeText = Lnow("Dane wrócą do stanu sprzed ostatniego przywrócenia kopii zapasowej. Dane z przywróconej kopii zostaną usunięte.")
        alert.addButton(withTitle: Lnow("Cofnij przywracanie"))
        alert.addButton(withTitle: Lnow("Anuluj"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try BackupService.shared.undoLastRestore()
            showInfoAlert(title: Lnow("Cofnięto przywracanie"), message: Lnow("Przywrócono dane sprzed ostatniego przywrócenia kopii."), isError: false)
        } catch {
            showInfoAlert(title: Lnow("Nie udało się cofnąć przywracania"), message: error.localizedDescription, isError: true)
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
    
    /// Okno „O programie” z autorem i informacją o współpracy z Claude.
    @objc private func showAboutPanelAction() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: Lnow("Autor: Andrzej Oles\nOpracowano we współpracy z Claude (Anthropic)"),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
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
        Self.isMenuItemEnabled(
            action: menuItem.action,
            hasAttachedSheet: mainWindow?.attachedSheet != nil,
            canUndoRestore: BackupService.shared.canUndoRestore
        )
    }

    /// Pozycje, które otwierają arkusz albo okno nad oknem głównym, są wyłączone przy otwartym arkuszu
    /// (np. Ustawieniach). SwiftUI pokazuje tylko jeden arkusz naraz, więc ⌘T albo ⌘I przy otwartych
    /// Ustawieniach zostawiały flagę arkusza włączoną i przycisk przestawał działać (R4-04).
    static func isMenuItemEnabled(action: Selector?, hasAttachedSheet: Bool, canUndoRestore: Bool) -> Bool {
        let opensOverMainWindow: [Selector] = [
            #selector(focusSongSearchAction),
            #selector(quickTextAction),
            #selector(importAction),
            #selector(createBackupAction),
            #selector(restoreBackupAction),
            #selector(undoRestoreAction)
        ]
        if let action, opensOverMainWindow.contains(action), hasAttachedSheet {
            return false
        }
        if action == #selector(undoRestoreAction) {
            return canUndoRestore
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
                Text(Lnow("Tworzenie kopii zapasowej na Dysku Google…"))
                    .font(.system(size: 13, weight: .medium))
            }
            Text(Lnow("Jeśli wysyłka się nie uda, kopia zostanie zapisana lokalnie."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button(Lnow("Pomiń i zamknij"), action: onSkip)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 380)
    }
}
