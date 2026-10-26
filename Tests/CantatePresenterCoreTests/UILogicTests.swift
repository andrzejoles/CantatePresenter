import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-10: uchwyt paska skrótów

@Suite("Zmiana wysokości paska skrótów (R4-10)")
struct BottomBarResizeTests {
    @Test("Przeciąganie liczy się od wysokości z początku ruchu, nie przyspiesza")
    func dragIsLinear() {
        var height = 72.0
        // Kolejne zdarzenia onChanged z narastającym przesunięciem (o 4 px w górę).
        for step in 1...5 {
            height = MainView.resizedBarHeight(start: 72, dragTranslation: -4 * Double(step))
        }
        #expect(height == 92)
    }

    @Test("Wysokość w granicach 52–160 px")
    func clamped() {
        #expect(MainView.resizedBarHeight(start: 72, dragTranslation: 500) == 52)
        #expect(MainView.resizedBarHeight(start: 72, dragTranslation: -500) == 160)
    }
}
