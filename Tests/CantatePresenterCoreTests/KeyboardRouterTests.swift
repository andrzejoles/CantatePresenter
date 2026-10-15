import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - K3 + W5: jeden router klawiatury

@Suite("KeyboardRouter (K3, W5)")
struct KeyboardRouterTests {
    private let defaults = ShortcutSettings()
    private let mainWindow = KeyboardRouter.Context.mainWindow(focus: .other)

    private func action(
        _ keyCode: UInt16,
        _ characters: String? = nil,
        command: Bool = false,
        shortcuts: ShortcutSettings = ShortcutSettings(),
        in context: KeyboardRouter.Context
    ) -> KeyboardAction? {
        KeyboardRouter.action(keyCode: keyCode, characters: characters, command: command, shortcuts: shortcuts, context: context)
    }

    // MARK: Kontekst

    @Test("Arkusz otwarty nad oknem głównym: router nie obsługuje klawiszy")
    func sheetBlocksRouting() {
        let state = KeyboardRouter.KeyWindowState(kind: .main, hasAttachedSheet: true, focus: .other)
        #expect(KeyboardRouter.context(for: state) == nil)
    }

    @Test("Fokus w polu tekstowym: router nie obsługuje klawiszy")
    func textFocusBlocksRouting() {
        let state = KeyboardRouter.KeyWindowState(kind: .main, hasAttachedSheet: false, focus: .text)
        #expect(KeyboardRouter.context(for: state) == nil)
    }

    @Test("Inne okna (arkusz, instrukcja, okno testowe): router nie obsługuje klawiszy")
    func otherWindowsAreIgnored() {
        let state = KeyboardRouter.KeyWindowState(kind: .other, hasAttachedSheet: false, focus: .other)
        #expect(KeyboardRouter.context(for: state) == nil)
    }

    @Test("Okno główne bez arkusza i okno projekcji są obsługiwane")
    func mainAndPresentationWindows() {
        #expect(KeyboardRouter.context(for: .init(kind: .main, hasAttachedSheet: false, focus: .list)) == .mainWindow(focus: .list))
        #expect(KeyboardRouter.context(for: .init(kind: .presentation, hasAttachedSheet: false, focus: .other)) == .presentationWindow)
    }

    // MARK: Okno główne

    @Test("Domyślne skróty w oknie głównym")
    func mainWindowDefaults() {
        #expect(action(49, " ", in: mainWindow) == .nextSlide)
        #expect(action(123, in: mainWindow) == .prevSlide)
        #expect(action(124, in: mainWindow) == .nextSlide)
        #expect(action(36, "\r", in: mainWindow) == .startPresentation)
        #expect(action(53, in: mainWindow) == .stopPresentation)
        #expect(action(30, "]", in: mainWindow) == .nextSong)
        #expect(action(33, "[", in: mainWindow) == .prevSong)
        #expect(action(11, "b", in: mainWindow) == .blackScreen)
        #expect(action(8, "c", in: mainWindow) == .clearText)
        #expect(action(15, "r", in: mainWindow) == .chorus)
        #expect(action(20, "3", in: mainWindow) == .verse(3))
        #expect(action(0, "a", in: mainWindow) == nil)
    }

    @Test("Strzałki góra/dół na liście zmieniają zaznaczenie, nie slajd")
    func arrowsInListPassThrough() {
        let list = KeyboardRouter.Context.mainWindow(focus: .list)
        #expect(action(125, in: list) == nil)
        #expect(action(126, in: list) == nil)
        #expect(action(124, in: list) == .nextSlide)
        #expect(action(49, " ", in: list) == .nextSlide)
    }

    @Test("Skróty z ⌘ tylko w oknie głównym")
    func commandShortcuts() {
        #expect(action(17, "t", command: true, in: mainWindow) == .quickText)
        #expect(action(24, "=", command: true, in: mainWindow) == .zoomIn)
        #expect(action(27, "-", command: true, in: mainWindow) == .zoomOut)
        #expect(action(29, "0", command: true, in: mainWindow) == .zoomReset)
        #expect(action(8, "c", command: true, in: mainWindow) == nil)
        #expect(action(17, "t", command: true, in: .presentationWindow) == nil)
    }

    // MARK: Okno projekcji (W5)

    @Test("Okno projekcji: Enter i Page Down przełączają slajd, Esc kończy")
    func presentationWindowDefaults() {
        #expect(action(36, "\r", in: .presentationWindow) == .nextSlide)
        #expect(action(121, in: .presentationWindow) == .nextSlide)
        #expect(action(116, in: .presentationWindow) == .prevSlide)
        #expect(action(53, in: .presentationWindow) == .stopPresentation)
        #expect(action(11, "b", in: .presentationWindow) == .blackScreen)
    }

    @Test("Okno projekcji używa skrótów z ustawień")
    func presentationWindowUsesConfiguredShortcuts() {
        var custom = ShortcutSettings()
        custom.nextSlideKey = 45 // N
        custom.blackScreenKey = 5 // G
        custom.nextSongKey = 2 // D

        #expect(action(45, "n", shortcuts: custom, in: .presentationWindow) == .nextSlide)
        #expect(action(5, "g", shortcuts: custom, in: .presentationWindow) == .blackScreen)
        #expect(action(2, "d", shortcuts: custom, in: .presentationWindow) == .nextSong)
        #expect(action(11, "b", shortcuts: custom, in: .presentationWindow) == nil)
    }

    @Test("Skrót z ustawień ma pierwszeństwo przed stałym R i cyframi")
    func configuredShortcutBeatsFixedKeys() {
        var custom = ShortcutSettings()
        custom.blackScreenKey = 15 // R
        custom.clearTextKey = 18 // 1

        #expect(action(15, "r", shortcuts: custom, in: mainWindow) == .blackScreen)
        #expect(action(18, "1", shortcuts: custom, in: mainWindow) == .clearText)
    }

    @Test("Esc zawsze kończy projekcję, nawet po zmianie klawisza stop")
    func escapeAlwaysStops() {
        var custom = ShortcutSettings()
        custom.stopPresentationKey = 47 // .

        #expect(action(53, shortcuts: custom, in: mainWindow) == .stopPresentation)
        #expect(action(47, ".", shortcuts: custom, in: .presentationWindow) == .stopPresentation)
    }

    // MARK: Konflikty w ustawieniach

    @Test("Wykrywanie konfliktów skrótów")
    func conflicts() {
        #expect(defaults.conflicts.isEmpty)

        var custom = ShortcutSettings()
        custom.prevSongKey = custom.nextSongKey
        custom.blackScreenKey = 15 // R
        let conflicts = custom.conflicts

        #expect(conflicts.contains { $0.contains("Poprzedni utwór") && $0.contains("Następny utwór") })
        #expect(conflicts.contains { $0.contains("refren") })
    }
}
