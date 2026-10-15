import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Tłumaczenia wersji webowej

/// Wersja webowa używa tego samego String Catalog co macOS: kopia w web/i18n musi być aktualna,
/// a każdy tekst `t("…")` z kodu JS musi mieć tłumaczenie w każdym języku.
@Suite("Tłumaczenia wersji webowej")
struct WebTranslationsTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("Kopia katalogu w web/i18n jest taka sama jak w aplikacji (scripts/sync_web_translations.sh)")
    func catalogInSync() throws {
        let source = try Data(contentsOf: Self.repository.appendingPathComponent("Sources/CantatePresenterCore/Resources/Localizable.xcstrings"))
        let copy = try Data(contentsOf: Self.repository.appendingPathComponent("web/i18n/Localizable.xcstrings"))
        #expect(source == copy)
    }

    @Test("Każdy tekst t(\"…\") w JS ma tłumaczenie en, de, es, uk", arguments: ["en", "de", "es", "uk"])
    func everyWebKeyTranslated(language: String) throws {
        let catalogData = try Data(contentsOf: Self.repository.appendingPathComponent("web/i18n/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        func translated(_ key: String) -> Bool {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            return (unit?["value"] as? String)?.isEmpty == false
        }

        let regex = try NSRegularExpression(pattern: #"\bt\("((?:[^"\\]|\\.)*)""#)
        var missing: Set<String> = []
        let sources = Self.repository.appendingPathComponent("web/src")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "js" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[range]).replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\n"#, with: "\n")
                if !translated(key) { missing.insert(key) }
            }
        }
        #expect(missing.isEmpty, "Brak tłumaczeń (\(language)): \(missing.sorted().prefix(15))")
    }
}
