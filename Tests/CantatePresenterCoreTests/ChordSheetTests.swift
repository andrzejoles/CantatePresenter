import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Ekran dla muzyków: chwyty do slajdu

/// Przykłady z wymyślonym tekstem, w formatach spotykanych w bibliotece (akordy nad tekstem, chwyty tylko
/// przy pierwszej zwrotce, nawiasy na końcu wiersza, inne łamanie wierszy niż w slajdach).
@Suite("Chwyty dla muzyków (ChordSheet)")
struct ChordSheetTests {
    private let sheet = """
    Zwrotka 1:
    D            G
    Idziemy razem przez pola,
    A            D
    słońce nad nami świeci.

    Refren:
    G        A
    Śpiewaj radośnie,
    D        h
    niech się niesie.

    Idziemy razem przez lasy,
    wiatr nam przygrywa cicho.
    """

    private func slide(_ text: String, _ type: SlideType = .verse) -> SongSlide {
        SongSlide(type: type, label: "x", text: text)
    }

    @Test("Akordy nad wierszami slajdu, także gdy slajd łamie wiersze inaczej niż arkusz")
    func matchesLines() throws {
        let result = ChordSheet.lines(for: slide("Idziemy razem\nprzez pola,\nsłońce nad nami świeci."), sheet: sheet)
        #expect(result.lines == [
            ChordLine(chords: "D            G", text: "Idziemy razem przez pola,"),
            ChordLine(chords: "A            D", text: "słońce nad nami świeci."),
        ])
        #expect(result.borrowedFrom == nil)
    }

    @Test("Zwrotka bez chwytów w arkuszu dostaje chwyty pierwszej zwrotki, wiersz po wierszu")
    func borrowsFromFirstVerse() {
        let result = ChordSheet.lines(for: slide("Idziemy razem przez lasy,\nwiatr nam przygrywa cicho."), sheet: sheet)
        #expect(result.lines.map(\.chords) == ["D            G", "A            D"])
        #expect(result.borrowedFrom == "Zwrotka 1")
    }

    @Test("Refren dopasowany do refrenu, nie do zwrotki")
    func chorus() {
        let result = ChordSheet.lines(for: slide("Ref. Śpiewaj radośnie, niech się niesie.", .chorus), sheet: sheet)
        #expect(result.lines.map(\.chords) == ["G        A", "D        h"])
    }

    @Test("Inna wersja tekstu: chwyty pierwszej sekcji tego rodzaju, oznaczone jako pożyczone")
    func differentText() {
        let result = ChordSheet.lines(for: slide("Zupełnie inne słowa\nktórych nie ma w arkuszu"), sheet: sheet)
        #expect(result.lines.map(\.text) == ["Zupełnie inne słowa", "których nie ma w arkuszu"])
        #expect(result.lines.first?.chords == "D            G")
        #expect(result.borrowedFrom == "Zwrotka 1")
    }

    @Test("Chwyty w nawiasie na końcu wiersza, także sklejone, i linia samych akordów w nawiasie")
    func parenthesizedChords() {
        let sheet = "(aFCG)\nPierwszy wiersz pieśni (Afis)\nDrugi wiersz pieśni (E)"
        let result = ChordSheet.lines(for: slide("Pierwszy wiersz pieśni\nDrugi wiersz pieśni"), sheet: sheet)
        #expect(result.lines == [ChordLine(chords: "A fis", text: "Pierwszy wiersz pieśni"), ChordLine(chords: "E", text: "Drugi wiersz pieśni")])
        #expect(ChordSheet.splitConcatenatedChords("Afis") == ["A", "fis"])
        #expect(ChordSheet.splitConcatenatedChords("aF") == ["a", "F"])
        #expect(ChordSheet.splitConcatenatedChords("Pan") == nil)
        #expect(ChordSheet.parenthesizedChordLine("(dgCF)") == "d g C F")
    }

    @Test("Transpozycja względem pierwszego akordu pieśni (ten sam zapis na każdym slajdzie)")
    func transposition() {
        let result = ChordSheet.lines(for: slide("Śpiewaj radośnie, niech się niesie.", .chorus), sheet: sheet, semitones: 2)
        #expect(result.lines.map(\.chords) == ["A        H", "E        c#"])
    }

    @Test("Bez arkusza albo bez akordów: sam tekst slajdu")
    func noChords() {
        #expect(ChordSheet.lines(for: slide("A\nB"), sheet: nil).lines == [ChordLine(text: "A"), ChordLine(text: "B")])
        #expect(ChordSheet.lines(for: slide("A\nB"), sheet: "Tylko tekst\nbez akordów").lines.allSatisfy { $0.chords == nil })
    }
}
