import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N7: zapis własnych języków nie może po cichu zawieść

@MainActor
@Suite("Własne języki: zapis (N7)", .serialized)
struct CustomLanguagesTests {
    private let translation = Data(#"{"targetLanguageCode":"fr","targetLanguageName":"Français","translations":{"Biblioteka pieśni":"Bibliothèque"}}"#.utf8)

    @Test("Błąd zapisu jest zgłaszany, a nie połykany")
    func saveErrorIsReported() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        // Plik w miejscu katalogu uniemożliwia zapis.
        try dir.write("plik", to: "zablokowane")
        let service = LocalizationService(customLanguagesURL: dir.file("zablokowane/custom_languages.json"))

        #expect(throws: (any Error).self) {
            try service.importTranslation(data: translation, fallbackFilename: "fr")
        }
    }

    @Test("Zaimportowany język jest zapisany i wczytuje się ponownie")
    func savedAndReloaded() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        let url = dir.file("custom_languages.json")

        _ = try LocalizationService(customLanguagesURL: url).importTranslation(data: translation, fallbackFilename: "fr")
        let reloaded = LocalizationService(customLanguagesURL: url)

        #expect(reloaded.customLanguages.map(\.code) == ["fr"])
    }

    @Test("Uszkodzony plik języków trafia do kwarantanny przed nadpisaniem")
    func corruptFileQuarantined() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        try dir.write("[{uszkodzony", to: "custom_languages.json")

        _ = try LocalizationService(customLanguagesURL: dir.file("custom_languages.json")).importTranslation(data: translation, fallbackFilename: "fr")

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names.contains { $0.hasPrefix("custom_languages.corrupt-") })
    }
}
