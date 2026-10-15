import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - W7: transpozycja akordów

@Suite("ChordTransposer (W7)")
struct ChordTransposerTests {
    private func transpose(_ sheet: String, _ semitones: Int) -> String {
        GuitarChordsService.shared.transpose(chordsSheet: sheet, semitones: semitones)
    }

    @Test("Molowe akordy pisane małą literą są transponowane")
    func lowercaseMinorChords() {
        #expect(transpose("a e d", 2) == "h f# e")
        #expect(transpose("C G a F", 2) == "D A h G")
    }

    @Test("Krzyżyk nie gubi granicy słowa: F# G o +1 to G G#")
    func sharpKeepsBoundary() {
        // G# zostaje w kolumnie, w której stało G (nad tą samą sylabą).
        #expect(transpose("F# G", 1) == "G  G#")
    }

    @Test("Bemole, polskie B i zapis is/es")
    func flatsAndPolishB() {
        #expect(transpose("Bb Eb", 2) == "C  F")
        #expect(transpose("B F", 2) == "C G")
        #expect(transpose("Fis cis", 1) == "G   d")
        #expect(transpose("Es As", 2) == "F  B")
    }

    @Test("Zapis bemolowy w tonacjach bemolowych, krzyżykowy w krzyżykowych")
    func spellingFollowsTargetKey() {
        #expect(transpose("C G a", 5) == "F C d")
        #expect(transpose("C F G", 3) == "Eb Ab B")
        #expect(transpose("C F G", 4) == "E A H")
        #expect(transpose("Fis H", -1) == "F   B")
        #expect(transpose("C G", 1) == "Db Ab")
        #expect(transpose("C Fis", 1) == "Des G")
        #expect(transpose("C G", -1) == "H F#")
    }

    @Test("Wszystkie 12 przesunięć zachowują wysokość dźwięku")
    func allTwelveShifts() throws {
        let roots = ["C", "C#", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "B", "H"]
        for root in roots {
            let pitch = try #require(ChordTransposer.pitch(of: root))
            for shift in -12...12 {
                let result = transpose(root, shift)
                #expect(ChordTransposer.pitch(of: result) == (pitch + shift % 12 + 12) % 12, "\(root) \(shift) -> \(result)")
            }
        }
    }

    @Test("Przyrostki i bas po ukośniku")
    func suffixesAndBass() {
        #expect(transpose("Cmaj7 Dm7 G7sus4 Fadd9", 2) == "Dmaj7 Em7 A7sus4 Gadd9")
        #expect(transpose("C/E G/H", 2) == "D/F# A/C#")
    }

    @Test("Linie tekstu nie są zmieniane, akordy w nawiasach tak")
    func lyricsLinesUntouched() {
        let sheet = """
        C       G
        A gdy przyjdzie Pan
        [C]Pan [G]jest pasterzem
        Pan kiedyś stanął (D A)
        [Refren]
        """
        let expected = """
        D       A
        A gdy przyjdzie Pan
        [D]Pan [A]jest pasterzem
        Pan kiedyś stanął (E H)
        [Refren]
        """
        #expect(transpose(sheet, 2) == expected)
    }

    @Test("Kolumny akordów nad tekstem są zachowane")
    func keepsColumns() {
        #expect(transpose("C    G    a", 1) == "Db   Ab   b")
        #expect(transpose("E  H  E", 1) == "F  C  F")
        #expect(transpose("F G", 1) == "F# G#")
    }

    @Test("Wykrywanie linii akordowych")
    func chordLineDetection() {
        #expect(ChordTransposer.isChordLine("C   G   a   F"))
        #expect(ChordTransposer.isChordLine("e H7 C D | x2"))
        #expect(ChordTransposer.isChordLine("Fis  cis  H"))
        #expect(!ChordTransposer.isChordLine("A gdy przyjdzie Pan"))
        #expect(!ChordTransposer.isChordLine("Ave Maria"))
        #expect(!ChordTransposer.isChordLine(""))
    }
}
