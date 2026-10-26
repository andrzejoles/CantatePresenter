import Foundation
import AppKit
import SwiftUI
import Combine

public struct DisplayScreenItem: Identifiable, Hashable {
    public let id: Int
    /// Identyfikator monitora (`CGDirectDisplayID`), stały mimo zmiany kolejności ekranów (S1).
    public let displayID: UInt32
    public let displayName: String
    public let name: String
    public let resolution: String
    public let frame: CGRect
    public let isPrimary: Bool
    
    public var aspectRatio: CGFloat {
        guard frame.height > 0 else { return 16.0 / 9.0 }
        let ratio = frame.width / frame.height
        return (ratio > 0.1 && !ratio.isNaN && !ratio.isInfinite) ? ratio : (16.0 / 9.0)
    }
}

@MainActor
public final class ScreenManager: ObservableObject {
    public static let shared = ScreenManager()
    
    @Published public var availableScreens: [DisplayScreenItem] = []
    @Published public var isPresentationActive: Bool = false
    @Published public var isWindowedPreviewActive: Bool = false
    /// Projektor zniknął w trakcie projekcji: okno projekcji ukryte, wróci po ponownym podłączeniu (S1).
    @Published public private(set) var isWaitingForDisplay: Bool = false
    /// Ekran, na którym trwa projekcja.
    private var presentingDisplay: DisplayDescriptor?
    
    public private(set) var presentationWindow: NSWindow?
    private var windowedPreviewWindow: NSWindow?
    
    public init() {
        refreshScreens()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreens()
                self?.repositionPresentationWindowIfNeeded()
            }
        }
    }
    
    public func refreshScreens() {
        let screens = NSScreen.screens
        var list: [DisplayScreenItem] = []
        
        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName
            let width = Int(screen.frame.width)
            let height = Int(screen.frame.height)
            let isPrimary = (index == 0)
            
            let label = "\(name) (\(width)x\(height))\(isPrimary ? " [Główny]" : " [Zewnętrzny]")"
            list.append(DisplayScreenItem(
                id: index,
                displayID: DisplayDescriptor(screen, isPrimary: isPrimary).id,
                displayName: name,
                name: label,
                resolution: "\(width) x \(height)",
                frame: screen.frame,
                isPrimary: isPrimary
            ))
        }
        
        self.availableScreens = list
    }
    
    // MARK: - Screen Target Resolution & Aspect Ratio
    
    private static func descriptors(_ screens: [NSScreen]) -> [DisplayDescriptor] {
        screens.enumerated().map { DisplayDescriptor($0.element, isPrimary: $0.offset == 0) }
    }
    
    private static func saved(_ settings: AppSettings) -> ScreenSelection.Saved {
        ScreenSelection.Saved(id: settings.selectedScreenID, name: settings.selectedScreenName, legacyIndex: settings.selectedScreenIndex)
    }
    
    /// Ekran projekcji wybrany w ustawieniach (po identyfikatorze, nazwie, a w starych plikach po indeksie).
    public func targetScreen(for settings: AppSettings? = nil) -> NSScreen? {
        let settings = settings ?? DataStore.shared.settings
        let screens = NSScreen.screens
        guard let index = ScreenSelection.resolve(Self.descriptors(screens), saved: Self.saved(settings)) else { return nil }
        return screens[index]
    }
    
    /// Zapamiętuje wybór ekranu po identyfikatorze i nazwie.
    public func selectScreen(_ item: DisplayScreenItem) {
        let store = DataStore.shared
        store.settings.selectedScreenIndex = item.id
        store.settings.selectedScreenID = item.displayID
        store.settings.selectedScreenName = item.displayName
        store.saveSettings()
    }
    
    /// Pozycja na liście `availableScreens` ekranu wybranego w ustawieniach.
    public var selectedScreenItemID: Int? {
        guard let screen = targetScreen() else { return nil }
        return NSScreen.screens.firstIndex(of: screen)
    }
    
    private static func ratio(of screen: NSScreen?) -> CGFloat {
        guard let screen, screen.frame.height > 0 else { return 16.0 / 9.0 }
        let ratio = screen.frame.width / screen.frame.height
        return (ratio > 0.1 && !ratio.isNaN && !ratio.isInfinite) ? ratio : (16.0 / 9.0)
    }
    
    public var selectedScreenAspectRatio: CGFloat {
        Self.ratio(of: targetScreen())
    }
    
    public var selectedScreenSize: CGSize {
        guard let screen = targetScreen(), screen.frame.width > 0, screen.frame.height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }
        return screen.frame.size
    }
    
    public static func formattedAspectRatio(for ratio: CGFloat) -> String {
        if abs(ratio - 16.0 / 9.0) < 0.03 { return "16:9" }
        if abs(ratio - 16.0 / 10.0) < 0.08 { return "16:10" }
        if abs(ratio - 4.0 / 3.0) < 0.03 { return "4:3" }
        if abs(ratio - 21.0 / 9.0) < 0.08 { return "21:9" }
        if abs(ratio - 5.0 / 4.0) < 0.03 { return "5:4" }
        return String(format: "%.2f:1", ratio)
    }
    
    // MARK: - Presentation Window Management
    public func startPresentation() {
        guard let targetScreen = targetScreen() else { return }
        presentingDisplay = DisplayDescriptor(targetScreen, isPrimary: targetScreen == NSScreen.screens.first)
        isWaitingForDisplay = false
        
        closePresentationWindow()
        
        let presentationView = PresentationContentView()
        let hostingController = NSHostingController(rootView: presentationView)
        
        let window = PresentationWindow(
            contentRect: targetScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        
        // Okno trzymamy w `presentationWindow`; domyślne zwolnienie przy `close()` dawało podwójne
        // zwolnienie i awarię po kliknięciu przycisku wyjścia w samym oknie projekcji.
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hostingController
        window.setFrame(targetScreen.frame, display: true)
        
        window.makeKeyAndOrderFront(nil)
        self.presentationWindow = window
        self.isPresentationActive = true
    }
    
    public func stopPresentation(restoringMainWindow: Bool = true) {
        closePresentationWindow(restoringMainWindow: restoringMainWindow)
    }
    
    public func togglePresentation() {
        if isPresentationActive {
            stopPresentation()
        } else {
            startPresentation()
        }
    }
    
    private func closePresentationWindow(restoringMainWindow: Bool = true) {
        if let window = presentationWindow {
            window.level = .normal
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        presentationWindow = nil
        isPresentationActive = false
        isWaitingForDisplay = false
        presentingDisplay = nil
        
        // Restore focus to the main app window
        guard restoringMainWindow else { return }
        NSApp.activate()
        if let main = AppDelegate.shared?.mainWindow {
            main.makeKeyAndOrderFront(nil)
        } else if let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 != self.windowedPreviewWindow }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    /// Po zmianie ekranów projekcja zostaje na swoim ekranie, a gdy ten zniknie, okno jest chowane
    /// zamiast przenosić się na ekran operatora (poziom `.screenSaver` zasłoniłby mu wszystko). S1
    private func repositionPresentationWindowIfNeeded() {
        guard let window = presentationWindow, isPresentationActive, let display = presentingDisplay else { return }
        let screens = NSScreen.screens
        switch ScreenSelection.placement(after: Self.descriptors(screens), presentingOn: display) {
        case .show(let index):
            let screen = screens[index]
            presentingDisplay = DisplayDescriptor(screen, isPrimary: index == 0)
            window.setFrame(screen.frame, display: true)
            if isWaitingForDisplay {
                isWaitingForDisplay = false
                window.orderFrontRegardless()
            }
        case .hide:
            window.orderOut(nil)
            isWaitingForDisplay = true
        }
    }
    
    // MARK: - Windowed Preview (for testing projection on a single screen)
    public func startWindowedPreview() {
        if windowedPreviewWindow != nil {
            windowedPreviewWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        let presentationView = PresentationContentView(isPreviewWindow: true)
        let hostingController = NSHostingController(rootView: presentationView)
        
        let ratio = selectedScreenAspectRatio
        let initialWidth: CGFloat = 800
        let initialHeight = max(250, initialWidth / ratio)
        let initialRect = NSRect(x: 100, y: 100, width: initialWidth, height: initialHeight)
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Podgląd projekcji (Okno testowe)"
        window.minSize = NSSize(width: 400, height: 250)
        window.backgroundColor = NSColor.black
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isWindowedPreviewActive = false
                self?.windowedPreviewWindow = nil
            }
        }
        
        window.makeKeyAndOrderFront(nil as Any?)
        self.windowedPreviewWindow = window
        self.isWindowedPreviewActive = true
    }
    
    public func stopWindowedPreview() {
        windowedPreviewWindow?.close()
        windowedPreviewWindow = nil
        isWindowedPreviewActive = false
    }
    
    public func toggleWindowedPreview() {
        if isWindowedPreviewActive {
            stopWindowedPreview()
        } else {
            startWindowedPreview()
        }
    }
}

// MARK: - Presentation Window Subclass
/// Klawiaturę okna projekcji obsługuje `KeyboardMonitor` (K3, W5).
public final class PresentationWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}
