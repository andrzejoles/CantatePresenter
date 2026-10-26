import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S10: tłumaczenia z String Catalog

@Suite("Lokalizacja (S10)", .serialized)
struct LocalizationTests {
    @Test("Paczka zasobów z katalogiem jest znajdowana")
    func resourceBundleFound() {
        #expect(Localization.resourceBundle != nil)
    }

    @Test("Tłumaczenie z katalogu dla wybranego języka")
    func catalogTranslation() {
        #expect(Localization.string("Biblioteka pieśni", language: "en") == "Song library")
    }

    @Test("Polski i brakujące tłumaczenia zwracają tekst źródłowy")
    func fallbackToSource() {
        #expect(Localization.string("Biblioteka pieśni", language: "pl") == "Biblioteka pieśni")
        #expect(Localization.string("Tekst, którego nie ma w katalogu", language: "en") == "Tekst, którego nie ma w katalogu")
        #expect(Localization.string("Biblioteka pieśni", language: "xx") == "Biblioteka pieśni")
    }

    @Test("Własne tłumaczenie z JSON ma pierwszeństwo przed katalogiem")
    func overlayWins() {
        Localization.setOverlay(["Biblioteka pieśni": "Bibliothèque"], for: "fr")
        Localization.setOverlay(["Biblioteka pieśni": "Library (custom)"], for: "en")
        defer {
            Localization.setOverlay([:], for: "fr")
            Localization.setOverlay([:], for: "en")
        }

        #expect(Localization.string("Biblioteka pieśni", language: "fr") == "Bibliothèque")
        #expect(Localization.string("Biblioteka pieśni", language: "en") == "Library (custom)")
    }

    @Test("Znaczniki {0}, {1} są zastępowane wartościami, także po przestawieniu w tłumaczeniu")
    func placeholders() {
        #expect(Localization.format("Zaimportowano {0} z {1} pieśni", [3, 10]) == "Zaimportowano 3 z 10 pieśni")
        #expect(Localization.format("{1} songs, {0} imported", [3, 10]) == "10 songs, 3 imported")
        #expect(Localization.format("Bez znaczników", []) == "Bez znaczników")
    }
}

// MARK: - Strażnik kompletności katalogu

@Suite("Katalog tłumaczeń jest kompletny (S10)")
struct LocalizationCatalogCompletenessTests {
    /// Klucze z `L("…")` i `Lnow("…")` w kodzie źródłowym.
    private static func sourceKeys() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CantatePresenterCore")
        let regex = try NSRegularExpression(pattern: #"\bL(?:now)?\("((?:[^"\\]|\\.)*)""#)
        var keys: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let unescaped = String(text[range])
                    .replacingOccurrences(of: #"\n"#, with: "\n")
                    .replacingOccurrences(of: #"\""#, with: "\"")
                keys.insert(unescaped)
            }
        }
        return keys
    }

    @Test("Każdy tekst interfejsu ma tłumaczenie w każdym języku", arguments: ["en", "de", "es", "uk"])
    func everyKeyTranslated(language: String) throws {
        let catalog = Localization.catalogKeys(referenceLanguage: language)
        let missing = try Self.sourceKeys().filter { catalog[$0] == nil }.sorted()

        #expect(missing.isEmpty, "Brak tłumaczeń (\(language)): \(missing.prefix(10))")
    }

    @Test("Tłumaczenie z wartościami: znaczniki są podstawiane")
    func formattedTranslation() {
        let text = Localization.format(Localization.string("Slajd {0}/{1}", language: "en"), [3, 5])
        #expect(text == "Slide 3/5")
    }
}

// MARK: - R8-06: zastępczy autor w języku interfejsu

@Suite("Zastępczy autor „Nieznany” (R8-06)")
struct DisplayAuthorTests {
    @Test("Zapisany „Nieznany” jest wyświetlany w języku interfejsu")
    func placeholderTranslated() {
        #expect(SongEnrichmentService.displayAuthor("Nieznany", language: "en") == "Unknown")
        #expect(SongEnrichmentService.displayAuthor("Nieznany", language: "de") == "Unbekannt")
        #expect(SongEnrichmentService.displayAuthor("Nieznany", language: "pl") == "Nieznany")
    }

    @Test("Tłumaczenie zapisane przez starszą wersję też jest wyświetlane w bieżącym języku")
    func legacyTranslatedPlaceholder() {
        #expect(SongEnrichmentService.displayAuthor("Unknown", language: "pl") == "Nieznany")
    }

    @Test("Prawdziwi autorzy i wpisy typu „Tradycyjna” bez zmian")
    func realAuthorsUnchanged() {
        #expect(SongEnrichmentService.displayAuthor("Jan Kowalski", language: "en") == "Jan Kowalski")
        #expect(SongEnrichmentService.displayAuthor("Tradycyjna", language: "en") == "Tradycyjna")
        #expect(SongEnrichmentService.displayAuthor("", language: "en") == "")
    }
}
