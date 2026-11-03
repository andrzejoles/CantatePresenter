import Foundation
import Testing
@testable import CantatePresenterCore

@Suite("Arkusze ze zmiennym rozmiarem")
struct ResizableSheetTests {
    private let minimum = CGSize(width: 740, height: 580)
    private let fallback = CGSize(width: 900, height: 700)

    @Test("Bez zapisu domyślny rozmiar, z zapisem ostatni, nigdy mniej niż minimum")
    func idealSize() {
        #expect(ResizableSheetFrame.idealSize(stored: "", minSize: minimum, defaultSize: fallback) == fallback)
        #expect(ResizableSheetFrame.idealSize(stored: "1200x820", minSize: minimum, defaultSize: fallback) == CGSize(width: 1200, height: 820))
        #expect(ResizableSheetFrame.idealSize(stored: "300x200", minSize: minimum, defaultSize: fallback) == minimum)
        #expect(ResizableSheetFrame.idealSize(stored: "zepsute", minSize: minimum, defaultSize: fallback) == fallback)
    }

    @Test("Zapisywany jest tylko zmierzony rozmiar arkusza")
    func storedValue() {
        #expect(ResizableSheetFrame.storedValue(for: CGSize(width: 1000.4, height: 699.6), minSize: minimum) == "1000x700")
        #expect(ResizableSheetFrame.storedValue(for: .zero, minSize: minimum) == nil)
    }
}
