import Foundation
import SwiftUI
import Testing
@testable import CantatePresenterCore

// MARK: - N1: wspólny renderer slajdu

@Suite("SlideTextView (N1)")
struct SlideTextViewTests {
    @Test("Wyrównanie z ustawień, także polskie wartości", arguments: [
        ("left", TextAlignment.leading), ("lewo", .leading), ("LEFT", .leading),
        ("right", .trailing), ("prawo", .trailing),
        ("center", .center), ("", .center), ("cokolwiek", .center)
    ])
    func alignment(value: String, expected: TextAlignment) {
        #expect(SlideAlignment(value).text == expected)
    }

    @MainActor
    @Test("Projekcja i podgląd w tej samej skali dają ten sam obraz")
    func previewMatchesProjection() throws {
        let settings = AppSettings()
        let size = CGSize(width: 640, height: 360)
        let text = "Pan kiedyś stanął nad brzegiem,\nSzukał ludzi gotowych pójść za Nim"
        let fontSize = AutoFitEngine.calculateOptimalFontSize(for: text, containerSize: size, fontFamily: settings.fontFamily, isBold: settings.isBold, lineSpacingFactor: settings.lineSpacingFactor, marginPercent: settings.marginPercent)

        func render<V: View>(_ view: V) throws -> Data {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }

        let projection = try render(ZStack {
            Color(hex: settings.backgroundColorHex)
            SlideTextView(text: text, settings: settings, fontSize: fontSize, containerSize: size)
        })
        let preview = try render(PresentationSlidePreviewCanvas(text: text, targetScreenSize: size, settings: settings))

        #expect(projection == preview)
    }
}
