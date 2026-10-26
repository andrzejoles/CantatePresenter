import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-12: chwyty tylko z wbudowanej bazy (decyzja S9)

@Suite("Wyszukiwanie chwytów: wbudowana baza, bez internetu")
struct GuitarChordsSearchTests {
    @Test("Tytuł z bazy: wynik z bazy; nieznany tytuł: brak wyników zamiast fragmentów z wyszukiwarki")
    func curatedOnly() throws {
        let service = GuitarChordsService()
        let barka = service.searchChords(for: "barka")
        let first = try #require(barka.first)
        #expect(first.title == "Barka" && !first.chordsSheet.isEmpty)
        #expect(barka.allSatisfy { $0.source == "Biblioteka Chwytów Holyrics" })
        #expect(service.searchChords(for: "Pieśń, której nie ma w żadnej bazie 7781").isEmpty)
    }
}
