import Foundation
import AppKit
import SwiftUI
import Combine

public struct DisplayScreenItem: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let resolution: String
    public let frame: CGRect
    public let isPrimary: Bool
}

@MainActor
public final class ScreenManager: ObservableObject {
    public static let shared = ScreenManager()
    
    @Published public var availableScreens: [DisplayScreenItem] = []
    @Published public var isPresentationActive: Bool = false
    @Published public var isWindowedPreviewActive: Bool = false
    
    private var presentationWindow: NSWindow?
    private var windowedPreviewWindow: NSWindow?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
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
                name: label,
                resolution: "\(width) x \(height)",
                frame: screen.frame,
                isPrimary: isPrimary
            ))
        }
        
        self.availableScreens = list
    }
    
    // MARK: - Presentation Window Management
    public func startPresentation(on screenIndex: Int) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // When there is only 1 screen, targetScreen is always screens[0]
        let targetIndex: Int
        if screens.count == 1 {
            targetIndex = 0
        } else if screenIndex >= 0 && screenIndex < screens.count {
            targetIndex = screenIndex
        } else {
            targetIndex = 1
        }
        let targetScreen = screens[targetIndex]
        
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
        
        // Local monitor to ensure ESC (code 53) closes presentation even if focus is in a subview
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isPresentationActive else { return event }
                if event.keyCode == 53 { // ESC
                    Task { @MainActor in
                        self.stopPresentation()
                    }
                    return nil
                }
                return event
            }
        }
    }
    
    public func stopPresentation() {
        closePresentationWindow()
    }
    
    public func togglePresentation(on screenIndex: Int) {
        if isPresentationActive {
            stopPresentation()
        } else {
            startPresentation(on: screenIndex)
        }
    }
    
    private func closePresentationWindow() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        
        presentationWindow?.orderOut(nil)
        presentationWindow?.contentViewController = nil
        presentationWindow = nil
        isPresentationActive = false
        
        // Restore focus to the main app window
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 != self.presentationWindow && $0 != self.windowedPreviewWindow }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    private func repositionPresentationWindowIfNeeded() {
        guard let window = presentationWindow, isPresentationActive else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        let targetIndex: Int
        if screens.count == 1 {
            targetIndex = 0
        } else {
            let savedIndex = DataStore.shared.settings.selectedScreenIndex
            targetIndex = (savedIndex >= 0 && savedIndex < screens.count) ? savedIndex : (screens.count > 1 ? 1 : 0)
        }
        let targetScreen = screens[targetIndex]
        window.setFrame(targetScreen.frame, display: true)
    }
    
    // MARK: - Windowed Preview (for testing projection on a single screen)
    public func startWindowedPreview() {
        if windowedPreviewWindow != nil {
            windowedPreviewWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        let presentationView = PresentationContentView(isPreviewWindow: true)
        let hostingController = NSHostingController(rootView: presentationView)
        
        let initialRect = NSRect(x: 100, y: 100, width: 800, height: 450)
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Podgląd projekcji (Okno testowe)"
        window.minSize = NSSize(width: 400, height: 250)
        window.backgroundColor = .black
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
        
        window.makeKeyAndOrderFront(nil)
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
public final class PresentationWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            Task { @MainActor in
                ScreenManager.shared.stopPresentation()
            }
            return
        }
        
        // Navigation shortcuts during presentation:
        // Space (49), Right (124), Down (125), Return (36), Page Down (121) -> Next Slide
        if event.keyCode == 49 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 36 || event.keyCode == 121 {
            Task { @MainActor in
                DataStore.shared.nextSlide()
            }
            return
        }
        // Left (123), Up (126), Page Up (116) -> Previous Slide
        if event.keyCode == 123 || event.keyCode == 126 || event.keyCode == 116 {
            Task { @MainActor in
                DataStore.shared.prevSlide()
            }
            return
        }
        // 'B' (11) -> Toggle Black Screen
        if event.keyCode == 11 {
            Task { @MainActor in
                DataStore.shared.toggleBlackScreen()
            }
            return
        }
        // 'C' (8) -> Toggle Clear Text
        if event.keyCode == 8 {
            Task { @MainActor in
                DataStore.shared.toggleClearText()
            }
            return
        }
        
        super.keyDown(with: event)
    }
}
