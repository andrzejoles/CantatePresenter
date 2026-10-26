import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S1: wybór ekranu projekcji i odłączenie projektora

@Suite("Wybór ekranu projekcji (S1)")
struct ScreenSelectionTests {
    private let mac = DisplayDescriptor(id: 1, name: "Wbudowany ekran Retina", isPrimary: true)
    private let projector = DisplayDescriptor(id: 7, name: "EPSON PJ", isPrimary: false)
    private let tv = DisplayDescriptor(id: 9, name: "LG TV", isPrimary: false)

    @Test("Zapamiętany projektor znaleziony po identyfikatorze, także po zmianie kolejności ekranów")
    func resolvesByIDAfterReorder() {
        let saved = ScreenSelection.Saved(id: 7, name: "EPSON PJ", legacyIndex: 1)
        #expect(ScreenSelection.resolve([mac, tv, projector], saved: saved) == 2)
    }

    @Test("Nowy identyfikator po ponownym podłączeniu: projektor znaleziony po nazwie")
    func resolvesByName() {
        let saved = ScreenSelection.Saved(id: 42, name: "EPSON PJ", legacyIndex: 1)
        #expect(ScreenSelection.resolve([mac, projector], saved: saved) == 1)
    }

    @Test("Stare ustawienia (tylko indeks) nadal działają")
    func legacyIndex() {
        let saved = ScreenSelection.Saved(id: nil, name: nil, legacyIndex: 1)
        #expect(ScreenSelection.resolve([mac, projector], saved: saved) == 1)
    }

    @Test("Jeden ekran: projekcja na Macu (tryb jednego ekranu)")
    func singleScreen() {
        let saved = ScreenSelection.Saved(id: 7, name: "EPSON PJ", legacyIndex: 1)
        #expect(ScreenSelection.resolve([mac], saved: saved) == 0)
    }

    @Test("Zapamiętanego ekranu brak, ale jest inny zewnętrzny: wybierany zewnętrzny, nie ekran operatora")
    func prefersExternalWhenSavedMissing() {
        let saved = ScreenSelection.Saved(id: 7, name: "EPSON PJ", legacyIndex: 1)
        #expect(ScreenSelection.resolve([mac, tv], saved: saved) == 1)
    }

    // MARK: Zmiana ekranów w trakcie projekcji

    @Test("Projektor odłączony w trakcie projekcji: okno chowane, nie przenoszone na ekran operatora")
    func hidesWhenProjectorDisappears() {
        let placement = ScreenSelection.placement(after: [mac], presentingOn: projector)
        #expect(placement == .hide)
    }

    @Test("Ten sam projektor wraca: projekcja wraca na niego, nawet pod innym indeksem")
    func returnsWhenProjectorReappears() {
        #expect(ScreenSelection.placement(after: [mac, tv, projector], presentingOn: projector) == .show(2))
    }

    @Test("Projektor wraca z nowym identyfikatorem: rozpoznany po nazwie")
    func returnsByName() {
        let replugged = DisplayDescriptor(id: 55, name: "EPSON PJ", isPrimary: false)
        #expect(ScreenSelection.placement(after: [mac, replugged], presentingOn: projector) == .show(1))
    }

    @Test("Inny zewnętrzny ekran po odłączeniu projektora nie przejmuje projekcji sam")
    func otherExternalDoesNotTakeOver() {
        #expect(ScreenSelection.placement(after: [mac, tv], presentingOn: projector) == .hide)
    }

    @Test("Tryb jednego ekranu: okno zostaje na ekranie Maca")
    func singleScreenModeStays() {
        #expect(ScreenSelection.placement(after: [mac], presentingOn: mac) == .show(0))
    }

    // MARK: Fokus klawiatury (R4-02)

    @Test("Projektor na innym ekranie niż okno główne nie przejmuje klawiatury")
    func projectorOnOtherScreenStaysNonKey() {
        #expect(!ScreenSelection.presentationWindowTakesKeyboard(projector: 2, operatorScreen: 1))
    }

    @Test("Projekcja na ekranie okna głównego (jeden ekran) przejmuje klawiaturę")
    func projectorOnOperatorScreenTakesKeyboard() {
        #expect(ScreenSelection.presentationWindowTakesKeyboard(projector: 1, operatorScreen: 1))
        #expect(ScreenSelection.presentationWindowTakesKeyboard(projector: 1, operatorScreen: nil))
    }
}
