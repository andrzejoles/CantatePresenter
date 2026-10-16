import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Logo planszy w wersji webowej

/// `web/logos.json` to eksport `LogoCatalog` (scripts/export_web_logos.py): ta sama lista i te same SVG.
@Suite("Logo w wersji webowej")
struct WebLogosTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("web/logos.json jest aktualny (python3 -I scripts/export_web_logos.py)")
    func logosMatchCatalog() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("web/logos.json"))
        let exported = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(exported.map { $0["id"] ?? "" } == LogoCatalog.all.map(\.id))
        #expect(exported.map { $0["name"] ?? "" } == LogoCatalog.all.map(\.name))
        // W testach zasób PNG bywa niedostępny (pusty base64): wtedy porównanie z plikiem z repozytorium.
        let png = try Data(contentsOf: Self.root.appendingPathComponent("Sources/CantatePresenterCore/Resources/end_logo.png"))
            .base64EncodedString()
        for (json, logo) in zip(exported, LogoCatalog.all) {
            var expected = logo.svgContent
            if ENDLogoAsset.base64PNG.isEmpty {
                expected = expected.replacingOccurrences(of: "base64,\"", with: "base64,\(png)\"")
            }
            #expect(json["svg"] == expected, "\(logo.id)")
        }
    }
}
