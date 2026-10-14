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
        
        let targetIndex = (screenIndex >= 0 && screenIndex < screens.count) ? screenIndex : (screens.count > 1 ? 1 : 0)
        let targetScreen = screens[targetIndex]
        
        closePresentationWindow()
        
        let presentationView = PresentationContentView()
        let hostingController = NSHostingController(rootView: presentationView)
        
        let window = NSWindow(
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
        presentationWindow?.orderOut(nil)
        presentationWindow?.contentViewController = nil
        presentationWindow = nil
        isPresentationActive = false
    }
    
    private func repositionPresentationWindowIfNeeded() {
        guard let window = presentationWindow, isPresentationActive else { return }
        let screens = NSScreen.screens
        let savedIndex = DataStore.shared.settings.selectedScreenIndex
        if savedIndex >= 0 && savedIndex < screens.count {
            let targetScreen = screens[savedIndex]
            window.setFrame(targetScreen.frame, display: true)
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
