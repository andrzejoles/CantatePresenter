import Foundation
import AppKit

// MARK: - Keyboard Action

public enum KeyboardAction: Equatable {
    case nextSlide
    case prevSlide
    case nextSong
    case prevSong
    case startPresentation
    case stopPresentation
    case blackScreen
    case clearText
    case chorus
    case verse(Int)
    case quickText
    case zoomIn
    case zoomOut
    case zoomReset
}

// MARK: - Keyboard Router

/// Jedyne miejsce obsługi skrótów prezentacji (K3, W5).
///
/// Działa wyłącznie w oknie głównym bez otwartego arkusza i bez fokusu w polu tekstowym
/// oraz w oknie projekcji. W pozostałych przypadkach klawisz trafia normalnie do okna,
/// więc np. Esc zamyka arkusz Ustawień zamiast przerywać projekcję.
public enum KeyboardRouter {
    public enum Focus: Equatable {
        case text
        case list
        case other
    }

    public enum WindowKind: Equatable {
        case main
        case presentation
        case other
    }

    public struct KeyWindowState: Equatable {
        public var kind: WindowKind
        public var hasAttachedSheet: Bool
        public var focus: Focus

        public init(kind: WindowKind, hasAttachedSheet: Bool, focus: Focus) {
            self.kind = kind
            self.hasAttachedSheet = hasAttachedSheet
            self.focus = focus
        }
    }

    public enum Context: Equatable {
        case mainWindow(focus: Focus)
        case presentationWindow
    }

    // MARK: - Key Codes

    enum Key {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let pageDown: UInt16 = 121
        static let pageUp: UInt16 = 116
        static let r: UInt16 = 15
        /// Kody klawiszy cyfr 1–9 w górnym rzędzie.
        static let digits: Set<UInt16> = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    // MARK: - Context

    public static func context(for state: KeyWindowState) -> Context? {
        guard !state.hasAttachedSheet else { return nil }
        switch state.kind {
        case .main:
            return state.focus == .text ? nil : .mainWindow(focus: state.focus)
        case .presentation:
            return .presentationWindow
        case .other:
            return nil
        }
    }

    // MARK: - Action

    /// Kolejność: skróty z ⌘, skróty z ustawień, a dopiero potem stałe klawisze
    /// (strzałki, Page Up/Down, Esc, R, cyfry), żeby wybrany w ustawieniach klawisz zawsze wygrywał.
    public static func action(
        keyCode: UInt16,
        characters: String?,
        command: Bool,
        shortcuts: ShortcutSettings,
        context: Context
    ) -> KeyboardAction? {
        if command {
            guard case .mainWindow = context else { return nil }
            switch characters {
            case "t": return .quickText
            case "=", "+": return .zoomIn
            case "-": return .zoomOut
            case "0": return .zoomReset
            default: return nil
            }
        }

        let isPresentation = context == .presentationWindow
        // Na liście góra/dół zmieniają zaznaczenie.
        if context == .mainWindow(focus: .list), keyCode == Key.up || keyCode == Key.down {
            return nil
        }

        let configured: [(UInt16, KeyboardAction)] = [
            (shortcuts.nextSlideKey, .nextSlide),
            (shortcuts.prevSlideKey, .prevSlide),
            (shortcuts.nextSongKey, .nextSong),
            (shortcuts.prevSongKey, .prevSong),
            (shortcuts.stopPresentationKey, .stopPresentation),
            (shortcuts.blackScreenKey, .blackScreen),
            (shortcuts.clearTextKey, .clearText),
            // W oknie projekcji pieśń już jest wyświetlana; Enter przełącza tam slajd (patrz niżej).
            (isPresentation ? nil : shortcuts.startPresentationKey, .startPresentation)
        ].compactMap { code, action in code.map { ($0, action) } }

        if let match = configured.first(where: { $0.0 == keyCode }) {
            return match.1
        }

        switch keyCode {
        case Key.right, Key.down, Key.pageDown:
            return .nextSlide
        case Key.returnKey where isPresentation:
            return .nextSlide
        case Key.left, Key.up, Key.pageUp:
            return .prevSlide
        case Key.escape:
            return .stopPresentation
        case Key.r:
            return .chorus
        case let code where Key.digits.contains(code):
            if let number = characters.flatMap(Int.init), (1...9).contains(number) {
                return .verse(number)
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Shortcut Conflicts

extension ShortcutSettings {
    /// Opisy konfliktów do pokazania w Ustawieniach (W5).
    public var conflicts: [String] {
        let entries: [(String, UInt16)] = [
            ("Poprzedni slajd", prevSlideKey),
            ("Następny slajd", nextSlideKey),
            ("Poprzedni utwór", prevSongKey),
            ("Następny utwór", nextSongKey),
            ("Uruchomienie prezentacji", startPresentationKey),
            ("Zatrzymanie prezentacji", stopPresentationKey),
            ("Czarny ekran", blackScreenKey),
            ("Ukrycie tekstu", clearTextKey)
        ]
        var result: [String] = []

        let grouped = Dictionary(grouping: entries, by: { $0.1 })
        for (code, group) in grouped.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            let names = group.map(\.0).joined(separator: ", ")
            result.append("\(ShortcutPresets.nameForKeyCode(code)): \(names). Zadziała tylko pierwsza akcja.")
        }
        for (name, code) in entries {
            if code == KeyboardRouter.Key.r {
                result.append("\(name) na klawiszu R: klawisz przestanie przechodzić do refrenu.")
            } else if KeyboardRouter.Key.digits.contains(code) {
                result.append("\(name) na klawiszu cyfry: cyfra przestanie przechodzić do zwrotki.")
            } else if code == KeyboardRouter.Key.escape, name != "Zatrzymanie prezentacji" {
                result.append("\(name) na klawiszu Esc: Esc przestanie kończyć projekcję.")
            }
        }
        return result
    }
}

// MARK: - Keyboard Monitor

/// Rejestruje jeden lokalny monitor klawiatury na cały czas działania aplikacji
/// i wykonuje akcje wybrane przez `KeyboardRouter`.
@MainActor
public final class KeyboardMonitor {
    public static let shared = KeyboardMonitor()

    private var monitor: Any?

    private init() {}

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Lokalne monitory są wywoływane na wątku głównym.
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = NSApp.keyWindow,
              let context = KeyboardRouter.context(for: state(of: window)) else {
            return false
        }
        let store = DataStore.shared
        guard let action = KeyboardRouter.action(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers?.lowercased(),
            command: event.modifierFlags.contains(.command),
            shortcuts: store.settings.shortcuts,
            context: context
        ) else {
            return false
        }
        perform(action, in: context)
        return true
    }

    private func state(of window: NSWindow) -> KeyboardRouter.KeyWindowState {
        let kind: KeyboardRouter.WindowKind
        if window is PresentationWindow {
            kind = .presentation
        } else if window === AppDelegate.shared?.mainWindow {
            kind = .main
        } else {
            kind = .other
        }

        let focus: KeyboardRouter.Focus
        switch window.firstResponder {
        case is NSText, is NSTextField:
            focus = .text
        case is NSTableView:
            focus = .list
        default:
            focus = .other
        }
        return KeyboardRouter.KeyWindowState(kind: kind, hasAttachedSheet: window.attachedSheet != nil, focus: focus)
    }

    private func perform(_ action: KeyboardAction, in context: KeyboardRouter.Context) {
        let store = DataStore.shared
        let screenManager = ScreenManager.shared

        switch action {
        case .nextSlide: store.nextSlide()
        case .prevSlide: store.prevSlide()
        case .nextSong: store.nextSongInPlan()
        case .prevSong: store.prevSongInPlan()
        case .blackScreen: store.toggleBlackScreen()
        case .clearText: store.toggleClearText()
        case .chorus: store.jumpToChorus()
        case .verse(let number): store.jumpToVerse(number: number)
        case .zoomIn: store.zoomInUI()
        case .zoomOut: store.zoomOutUI()
        case .zoomReset: store.resetZoomUI()
        case .quickText:
            NotificationCenter.default.post(name: NSNotification.Name("OpenQuickTextSheet"), object: nil)
        case .startPresentation:
            if let song = store.selectedSong {
                store.present(song: song, slideIndex: 0)
            }
        case .stopPresentation:
            // Na jednym ekranie albo z fokusem w oknie projekcji Esc zamyka okno projekcji;
            // przy dwóch ekranach z okna głównego tylko gasi tekst (projektor pokazuje planszę).
            if screenManager.isPresentationActive,
               NSScreen.screens.count == 1 || context == .presentationWindow {
                screenManager.stopPresentation()
            }
            store.stopLive()
        }
    }
}
