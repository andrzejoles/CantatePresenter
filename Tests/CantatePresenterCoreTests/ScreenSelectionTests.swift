import AppKit
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

// MARK: - R8-01: stan projekcji po starcie

@MainActor
private final class FakePresentationHost: PresentationWindowHost {
    var window: NSWindow? { nil }
    var operatorScreenID: UInt32?
    var isOpen = false
    var isHidden = false
    var isLowered = false
    var openedTakingKeyboard: Bool?
    var frame: CGRect = .zero

    init(operatorScreenID: UInt32?) {
        self.operatorScreenID = operatorScreenID
    }

    func open(on screen: NSScreen?, frame: CGRect, takesKeyboard: Bool) {
        isOpen = true
        isHidden = false
        openedTakingKeyboard = takesKeyboard
        self.frame = frame
    }
    func close() { isOpen = false }
    func setFrame(_ frame: CGRect) { self.frame = frame }
    func hide() { isHidden = true }
    func show() { isHidden = false }
    func setLowered(_ lowered: Bool) { isLowered = lowered }
    func focusMainWindow(excluding other: NSWindow?) {}
}

@MainActor
@Suite("Stan projekcji po starcie (R8-01)")
struct PresentationSessionTests {
    private let mac = DisplayDescriptor(id: 1, name: "Wbudowany ekran Retina", isPrimary: true)
    private let projector = DisplayDescriptor(id: 7, name: "EPSON PJ", isPrimary: false)
    private let macFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let projectorFrame = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    private func start(on display: DisplayDescriptor, frame: CGRect, operatorScreen: UInt32?) -> (ScreenManager, FakePresentationHost) {
        let host = FakePresentationHost(operatorScreenID: operatorScreen)
        let manager = ScreenManager(windowHost: host, observesScreens: false)
        manager.startPresentation(on: display, screen: nil, frame: frame)
        return (manager, host)
    }

    @Test("Po starcie zapamiętany jest ekran projekcji (wcześniej zerowany przez zamknięcie starego okna)")
    func keepsPresentingDisplay() {
        let (manager, host) = start(on: projector, frame: projectorFrame, operatorScreen: mac.id)
        #expect(manager.presentingDisplay == projector)
        #expect(manager.isPresentationActive)
        #expect(host.isOpen)
        // Ponowny start (drugi raz „Prezentuj na pełnym ekranie”) też zostawia ekran.
        manager.startPresentation(on: projector, screen: nil, frame: projectorFrame)
        #expect(manager.presentingDisplay == projector)
    }

    @Test("Jeden ekran: okno projekcji przejmuje klawiaturę i zasłania okno główne (R4-02, R8-02)")
    func singleScreenTakesKeyboard() {
        let (manager, host) = start(on: mac, frame: macFrame, operatorScreen: mac.id)
        #expect(host.openedTakingKeyboard == true)
        #expect(manager.presentationCoversMainWindow)
    }

    @Test("Osobny projektor: klawiatura zostaje w oknie głównym")
    func separateProjectorKeepsKeyboardInMainWindow() {
        let (manager, host) = start(on: projector, frame: projectorFrame, operatorScreen: mac.id)
        #expect(host.openedTakingKeyboard == false)
        #expect(!manager.presentationCoversMainWindow)
    }

    @Test("Odłączenie projektora chowa okno, ponowne podłączenie je przywraca (S1)")
    func disconnectAndReconnect() {
        let (manager, host) = start(on: projector, frame: projectorFrame, operatorScreen: mac.id)
        manager.screensDidChange([(mac, macFrame)])
        #expect(manager.isWaitingForDisplay)
        #expect(host.isHidden)
        #expect(manager.isPresentationActive)

        let moved = CGRect(x: 0, y: 982, width: 1280, height: 720)
        manager.screensDidChange([(mac, macFrame), (projector, moved)])
        #expect(!manager.isWaitingForDisplay)
        #expect(!host.isHidden)
        #expect(host.frame == moved)
    }

    @Test("Zatrzymanie czyści stan projekcji")
    func stopClearsState() {
        let (manager, host) = start(on: projector, frame: projectorFrame, operatorScreen: mac.id)
        manager.stopPresentation(restoringMainWindow: false)
        #expect(manager.presentingDisplay == nil)
        #expect(!manager.isPresentationActive)
        #expect(!host.isOpen)
        manager.screensDidChange([(mac, macFrame)])
        #expect(!manager.isWaitingForDisplay)
    }

    @Test("Pytanie przy projekcji na ekranie operatora obniża na ten czas okno projekcji (R8-02)")
    func lowersForAlert() {
        let (manager, host) = start(on: mac, frame: macFrame, operatorScreen: mac.id)
        let wasLowered = manager.withPresentationLowered { host.isLowered }
        #expect(wasLowered)
        #expect(!host.isLowered)

        let (separate, separateHost) = start(on: projector, frame: projectorFrame, operatorScreen: mac.id)
        #expect(!separate.withPresentationLowered { separateHost.isLowered })
    }
}
