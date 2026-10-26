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
    /// Opuszczenie pola wyszukiwania (Esc), żeby kolejne klawisze sterowały slajdami.
    case endTextEditing
}

// MARK: - Keyboard Router

/// Jedyne miejsce obsługi skrótów prezentacji (K3, W5).
///
/// Działa wyłącznie w oknie głównym bez otwartego arkusza i bez fokusu w polu tekstowym
/// oraz w oknie projekcji. W pozostałych przypadkach klawisz trafia normalnie do okna,
/// więc np. Esc zamyka arkusz Ustawień zamiast przerywać projekcję.
public enum KeyboardRouter {
    public enum Focus: Equatable {
        /// Jednowierszowe pole (np. wyszukiwanie): klawisze do pisania trafiają do pola.
        case text
        /// Wielowierszowy tekst: wszystkie klawisze trafiają do pola.
        case multilineText
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
        /// Klawisze, które nie piszą w polu tekstowym: Page Up/Down (piloty do prezentacji), Home/End, F1–F12.
        static let nonTyping: Set<UInt16> = [116, 121, 115, 119, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    }

    // MARK: - Context

    public static func context(for state: KeyWindowState) -> Context? {
        guard !state.hasAttachedSheet else { return nil }
        switch state.kind {
        case .main:
            return state.focus == .multilineText ? nil : .mainWindow(focus: state.focus)
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
        // W polu wyszukiwania obsługujemy tylko klawisze, które nic nie piszą, i Esc do wyjścia z pola.
        if context == .mainWindow(focus: .text) {
            if keyCode == Key.escape && !command {
                return .endTextEditing
            }
            guard !command, Key.nonTyping.contains(keyCode) else { return nil }
        }
        
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

// MARK: - Stop Presentation

extension KeyboardRouter {
    /// Czy zatrzymanie projekcji (Esc) ma też zamknąć okno projekcji (R4-02).
    ///
    /// Jeden ekran: tak, bo okno projekcji zasłania okno główne. Dwa ekrany: z okna głównego nigdy
    /// (projektor pokazuje planszę); w oknie projekcji dopiero drugie Esc, gdy tekst jest już zgaszony,
    /// żeby jedno przypadkowe Esc nie pokazało zgromadzeniu pulpitu projektora.
    public static func stopClosesPresentationWindow(screenCount: Int, context: Context, isLive: Bool) -> Bool {
        if screenCount <= 1 { return true }
        return context == .presentationWindow && !isLive
    }
}

// MARK: - Slide Keys

extension Song {
    /// Slajd wybierany cyfrą: zwrotka o tym numerze (po numerze, nie po polskiej etykiecie, S10).
    /// Tylko w pieśni bez numerowanych zwrotek cyfra wybiera slajd na tej pozycji; wcześniej np. 4 w pieśni
    /// z trzema zwrotkami przechodziło do czwartego slajdu, czyli do refrenu albo Cody (R4-03).
    public func slideIndex(forVerse number: Int) -> Int? {
        if let index = slides.firstIndex(where: { $0.type == .verse && $0.number == number }) {
            return index
        }
        guard !slides.contains(where: { $0.type == .verse && $0.number != nil }) else { return nil }
        return slides.indices.contains(number - 1) ? number - 1 : nil
    }

    /// Slajd wybierany klawiszem R: pierwszy refren.
    public var chorusSlideIndex: Int? {
        slides.firstIndex(where: { $0.type == .chorus })
    }

    /// Klawisz pokazywany na karcie slajdu: dokładnie ten, który do niej przechodzi (R4-03).
    /// Karty, do których nie prowadzi ani R, ani cyfra 1–9, nie mają znaczka.
    public var slideShortcutHints: [Int: String] {
        var hints: [Int: String] = [:]
        if let chorus = chorusSlideIndex {
            hints[chorus] = "R"
        }
        for number in 1...9 {
            if let index = slideIndex(forVerse: number), hints[index] == nil {
                hints[index] = String(number)
            }
        }
        return hints
    }
}

// MARK: - Fixed Keys Help

extension KeyboardRouter {
    /// Klawisze, których nie zmienia się w Ustawieniach; pokazywane w Ustawieniach i w instrukcji.
    public static var fixedKeysHelp: [(keys: String, action: String)] {
        fixedKeysHelp(language: Localization.currentLanguage)
    }

    static func fixedKeysHelp(language: String) -> [(keys: String, action: String)] {
        func t(_ key: String) -> String { Localization.string(key, language: language) }
        return [
            ("← / ↑", t("Poprzedni slajd (↑ na liście pieśni: poprzednia pieśń)")),
            ("→ / ↓", t("Następny slajd (↓ na liście pieśni: następna pieśń)")),
            ("Page Up / Page Down", t("Poprzedni / następny slajd (pilot), także w polu wyszukiwania")),
            (t("Enter w oknie projekcji"), t("Następny slajd")),
            ("Esc", t("Zakończenie projekcji; w polu wyszukiwania: wyjście z pola")),
            ("R", t("Refren")),
            ("1 – 9", t("Zwrotka o tym numerze")),
            ("⌘F", t("Szukaj pieśni (Enter: wybór pierwszego wyniku)")),
            ("⌘T", t("Szybki tekst na żywo")),
            ("⌘+ / ⌘− / ⌘0", t("Powiększenie / pomniejszenie / domyślna skala interfejsu"))
        ]
    }

    public static var shortcutsNote: String { Lnow("Skróty działają, gdy pole wyszukiwania jest nieaktywne (po starcie albo po Esc). Klawisz wybrany powyżej ma pierwszeństwo przed klawiszem stałym, np. R przypisane do czarnego ekranu przestaje włączać refren.") }
}

// MARK: - Shortcut Conflicts

extension ShortcutSettings {
    /// Opisy konfliktów do pokazania w Ustawieniach (W5).
    public var conflicts: [String] {
        conflicts(language: Localization.currentLanguage)
    }

    /// Akcje porównywane po wartości, a nazwy tłumaczone dopiero do wyświetlenia (R4-28).
    func conflicts(language: String) -> [String] {
        func t(_ key: String, _ args: Any...) -> String {
            Localization.format(Localization.string(key, language: language), args)
        }
        let entries: [(action: KeyboardAction, name: String, code: UInt16)] = [
            (.prevSlide, t("Poprzedni slajd"), prevSlideKey),
            (.nextSlide, t("Następny slajd"), nextSlideKey),
            (.prevSong, t("Poprzedni utwór"), prevSongKey),
            (.nextSong, t("Następny utwór"), nextSongKey),
            (.startPresentation, t("Uruchomienie prezentacji"), startPresentationKey),
            (.stopPresentation, t("Zatrzymanie prezentacji"), stopPresentationKey),
            (.blackScreen, t("Czarny ekran"), blackScreenKey),
            (.clearText, t("Ukrycie tekstu"), clearTextKey)
        ]
        var result: [String] = []

        let grouped = Dictionary(grouping: entries, by: { $0.code })
        for (code, group) in grouped.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            let names = group.map(\.name).joined(separator: ", ")
            result.append(t("{0}: {1}. Zadziała tylko pierwsza akcja.", ShortcutPresets.nameForKeyCode(code), names))
        }
        for entry in entries {
            if entry.code == KeyboardRouter.Key.r {
                result.append(t("{0} na klawiszu R: klawisz przestanie przechodzić do refrenu.", entry.name))
            } else if KeyboardRouter.Key.digits.contains(entry.code) {
                result.append(t("{0} na klawiszu cyfry: cyfra przestanie przechodzić do zwrotki.", entry.name))
            } else if entry.code == KeyboardRouter.Key.escape, entry.action != .stopPresentation {
                result.append(t("{0} na klawiszu Esc: Esc przestanie kończyć projekcję.", entry.name))
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
        if action == .endTextEditing {
            window.makeFirstResponder(nil)
            return true
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
        case let textView as NSTextView:
            // Pole jednowierszowe edytuje współdzielony „field editor”.
            focus = textView.isFieldEditor ? .text : .multilineText
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
        case .endTextEditing:
            break
        case .quickText:
            NotificationCenter.default.post(name: NSNotification.Name("OpenQuickTextSheet"), object: nil)
        case .startPresentation:
            if let song = store.selectedSong {
                store.present(song: song, slideIndex: 0)
            }
        case .stopPresentation:
            if screenManager.isPresentationActive,
               KeyboardRouter.stopClosesPresentationWindow(screenCount: NSScreen.screens.count, context: context, isLive: store.isLive) {
                screenManager.stopPresentation()
            }
            store.stopLive()
        }
    }
}
