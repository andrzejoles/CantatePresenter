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
    private(set) var presentingDisplay: DisplayDescriptor?
    
    /// Okno projekcji; w testach atrapa bez prawdziwych okien (R8-01).
    private let windowHost: PresentationWindowHost
    public var presentationWindow: NSWindow? { windowHost.window }
    private var windowedPreviewWindow: NSWindow?
    private var windowedPreviewCloseObserver: (any NSObjectProtocol)?
    
    public convenience init() {
        self.init(windowHost: AppKitPresentationWindowHost(), observesScreens: true)
    }
    
    init(windowHost: PresentationWindowHost, observesScreens: Bool) {
        self.windowHost = windowHost
        guard observesScreens else { return }
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
            
            // Dopisek „[główny]” dodaje widok w języku interfejsu; „zewnętrzny” trafiał też na wbudowany ekran (R4-29).
            let label = "\(name) (\(width)x\(height))"
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
        startPresentation(
            on: DisplayDescriptor(targetScreen, isPrimary: targetScreen == NSScreen.screens.first),
            screen: targetScreen,
            frame: targetScreen.frame
        )
    }
    
    /// Kolejność ma znaczenie: zamknięcie poprzedniego okna zeruje stan projekcji, więc ekran projekcji
    /// zapisujemy dopiero po nim. Wcześniej był zapisywany przed, przez co `presentingDisplay` zawsze było
    /// `nil`: okno projekcji nie przejmowało klawiatury na jednym ekranie (R4-02), a odłączenie projektora
    /// nie było obsługiwane (S1). R8-01
    func startPresentation(on display: DisplayDescriptor, screen: NSScreen?, frame: CGRect) {
        closePresentationWindow()
        presentingDisplay = display
        isWaitingForDisplay = false
        
        let takesKeyboard = ScreenSelection.presentationWindowTakesKeyboard(projector: display.id, operatorScreen: windowHost.operatorScreenID)
        // Na osobnym projektorze okno główne zostaje kluczowe (R4-02).
        windowHost.open(on: screen, frame: frame, takesKeyboard: takesKeyboard)
        isPresentationActive = true
    }
    
    /// Okno projekcji zasłania okno główne (jeden ekran albo obraz lustrzany). Arkusze, panele i okna
    /// otwierane nad oknem głównym byłyby wtedy pod nim niewidoczne (R8-02).
    public var presentationCoversMainWindow: Bool {
        guard isPresentationActive, !isWaitingForDisplay, let display = presentingDisplay else { return false }
        return ScreenSelection.presentationWindowTakesKeyboard(projector: display.id, operatorScreen: windowHost.operatorScreenID)
    }

    /// Komunikat, który musi być widoczny także przy projekcji na ekranie operatora (pytanie przy ⌘Q):
    /// na czas `body` okno projekcji schodzi na zwykły poziom (R8-02).
    public func withPresentationLowered<T>(_ body: () -> T) -> T {
        guard presentationCoversMainWindow else { return body() }
        windowHost.setLowered(true)
        defer { windowHost.setLowered(false) }
        return body()
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
        windowHost.close()
        isPresentationActive = false
        isWaitingForDisplay = false
        presentingDisplay = nil
        
        if restoringMainWindow {
            windowHost.focusMainWindow(excluding: windowedPreviewWindow)
        }
    }
    
    /// Po zmianie ekranów projekcja zostaje na swoim ekranie, a gdy ten zniknie, okno jest chowane
    /// zamiast przenosić się na ekran operatora (poziom `.screenSaver` zasłoniłby mu wszystko). S1
    private func repositionPresentationWindowIfNeeded() {
        let screens = NSScreen.screens
        screensDidChange(screens.enumerated().map { (DisplayDescriptor($0.element, isPrimary: $0.offset == 0), $0.element.frame) })
    }
    
    func screensDidChange(_ screens: [(descriptor: DisplayDescriptor, frame: CGRect)]) {
        guard isPresentationActive, let display = presentingDisplay else { return }
        switch ScreenSelection.placement(after: screens.map(\.descriptor), presentingOn: display) {
        case .show(let index):
            presentingDisplay = screens[index].descriptor
            windowHost.setFrame(screens[index].frame)
            if isWaitingForDisplay {
                isWaitingForDisplay = false
                windowHost.show()
            }
        case .hide:
            windowHost.hide()
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
        
        window.title = Lnow("Podgląd projekcji (Okno testowe)")
        window.minSize = NSSize(width: 400, height: 250)
        window.backgroundColor = NSColor.black
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        // Jeden obserwator na okno, usuwany przy zamknięciu. Bez przeskoku przez `Task`: szybkie ponowne
        // otwarcie nie może wyzerować nowego okna (R4-19).
        windowedPreviewCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            let closed = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, closed == self.windowedPreviewWindow.map(ObjectIdentifier.init) else { return }
                self.windowedPreviewDidClose()
            }
        }
        
        window.makeKeyAndOrderFront(nil as Any?)
        self.windowedPreviewWindow = window
        self.isWindowedPreviewActive = true
    }
    
    public func stopWindowedPreview() {
        windowedPreviewWindow?.close()
        windowedPreviewDidClose()
    }

    private func windowedPreviewDidClose() {
        if let observer = windowedPreviewCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        windowedPreviewCloseObserver = nil
        windowedPreviewWindow = nil
        isWindowedPreviewActive = false
    }

    /// Tytuły okien AppKit po zmianie języka (R4-20).
    public func updateWindowTitles() {
        windowedPreviewWindow?.title = Lnow("Podgląd projekcji (Okno testowe)")
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

// MARK: - Presentation Window Host

/// Okno projekcji widziane przez `ScreenManager`. Oddzielone od stanu projekcji, żeby kolejność
/// startu i obsługę odłączenia projektora dało się sprawdzić testem bez otwierania okien (R8-01).
@MainActor
protocol PresentationWindowHost: AnyObject {
    var window: NSWindow? { get }
    /// Ekran okna głównego (`CGDirectDisplayID`), `nil` bez okna głównego.
    var operatorScreenID: UInt32? { get }
    func open(on screen: NSScreen?, frame: CGRect, takesKeyboard: Bool)
    func close()
    func setFrame(_ frame: CGRect)
    func hide()
    func show()
    /// Poziom `.normal` na czas komunikatu, który inaczej zostałby pod oknem projekcji (R8-02).
    func setLowered(_ lowered: Bool)
    func focusMainWindow(excluding other: NSWindow?)
}

@MainActor
final class AppKitPresentationWindowHost: PresentationWindowHost {
    private(set) var window: NSWindow?
    
    var operatorScreenID: UInt32? {
        (AppDelegate.shared?.mainWindow?.screen).map { DisplayDescriptor($0, isPrimary: false).id }
    }
    
    func open(on screen: NSScreen?, frame: CGRect, takesKeyboard: Bool) {
        let hostingController = NSHostingController(rootView: PresentationContentView(coversMainWindow: takesKeyboard))
        let window = PresentationWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // Okno trzymamy w `window`; domyślne zwolnienie przy `close()` dawało podwójne
        // zwolnienie i awarię po kliknięciu przycisku wyjścia w samym oknie projekcji.
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hostingController
        window.setFrame(frame, display: true)
        
        if takesKeyboard {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        self.window = window
    }
    
    func close() {
        if let window {
            window.level = .normal
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        window = nil
    }
    
    func setFrame(_ frame: CGRect) {
        window?.setFrame(frame, display: true)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func show() {
        window?.orderFrontRegardless()
    }
    
    func setLowered(_ lowered: Bool) {
        window?.level = lowered ? .normal : .screenSaver
    }
    
    func focusMainWindow(excluding other: NSWindow?) {
        NSApp.activate()
        if let main = AppDelegate.shared?.mainWindow {
            main.makeKeyAndOrderFront(nil)
        } else if let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 != other && $0 !== self.window }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}
