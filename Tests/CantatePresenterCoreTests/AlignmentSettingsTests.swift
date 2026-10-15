import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N2: wyrównanie jako typy wyliczeniowe

@Suite("Ustawienia wyrównania (N2)")
struct AlignmentSettingsTests {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test("Stare polskie wartości i wielkość liter są rozpoznawane")
    func legacyValues() throws {
        #expect(try decode(#"{"textAlignment":"lewo","verticalAlignment":"top"}"#).textAlignment == .left)
        #expect(try decode(#"{"textAlignment":"prawo"}"#).textAlignment == .right)
        #expect(try decode(#"{"textAlignment":"LEFT","verticalAlignment":"Bottom"}"#).verticalAlignment == .bottom)
    }

    @Test("Nieznana wartość daje środek, a nie błąd wczytania ustawień")
    func unknownValue() throws {
        let settings = try decode(#"{"textAlignment":"justify","verticalAlignment":"srodek"}"#)
        #expect(settings.textAlignment == .center)
        #expect(settings.verticalAlignment == .center)
    }

    @Test("Zapis używa tych samych wartości co wcześniej")
    func encodesSameStrings() throws {
        var settings = AppSettings()
        settings.textAlignment = .left
        settings.verticalAlignment = .bottom
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(json.contains(#""textAlignment":"left""#))
        #expect(json.contains(#""verticalAlignment":"bottom""#))
    }
}
