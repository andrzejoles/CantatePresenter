import Foundation
import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) var shared: AppDelegate?
    public var mainWindow: NSWindow?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        
        setupMainMenu()
        setupMainWindow()
        
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
        appMenu.addItem(NSMenuItem(title: "Zakończ CantatePresenter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Plik")
        fileMenu.addItem(NSMenuItem(title: "Importuj pieśni...", action: #selector(importAction), keyEquivalent: "i"))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj całą bazę (JSON)...", action: #selector(exportJSONAction), keyEquivalent: "e"))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj pieśni do folderu (.txt)...", action: #selector(exportFolderAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Utwórz pełną kopię zapasową (.cantatebackup)...", action: #selector(createBackupAction), keyEquivalent: "b"))
        fileMenu.addItem(NSMenuItem(title: "Przywróć z kopii zapasowej...", action: #selector(restoreBackupAction), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Zamknij okno", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
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
    
    @objc private func importAction() {
        Task { @MainActor in
            let songs = TextImporter.pickFilesForImport()
            for s in songs {
                DataStore.shared.addSong(s)
            }
        }
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
            _ = BackupService.shared.restoreBackupWithOpenPanel()
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        let store = DataStore.shared
        if store.settings.googleDrive.isEnabled && store.settings.googleDrive.autoBackupOnExit {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                if let (archiveURL, _) = try? BackupService.shared.createBackupArchive(comment: "Automatyczny backup przy zamykaniu CantatePresenter") {
                    _ = try? await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archiveURL)
                    try? FileManager.default.removeItem(at: archiveURL)
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 4.0)
        }
    }
}
