import Foundation
import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public var mainWindow: NSWindow?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        window.title = "Holyrics Mac — Prezenter Pieśni"
        window.minSize = NSSize(width: 950, height: 600)
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        self.mainWindow = window
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "O programie Holyrics Mac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Zakończ Holyrics Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Plik")
        fileMenu.addItem(NSMenuItem(title: "Importuj pieśni...", action: #selector(importAction), keyEquivalent: "i"))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj całą bazę (JSON)...", action: #selector(exportJSONAction), keyEquivalent: "e"))
        fileMenu.addItem(NSMenuItem(title: "Eksportuj pieśni do folderu (.txt)...", action: #selector(exportFolderAction), keyEquivalent: ""))
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
        
        NSApp.mainMenu = mainMenu
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
}
