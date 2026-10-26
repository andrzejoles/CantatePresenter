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

    @Test("Uszkodzony plik języków trafia do kwarantanny i nie jest nadpisywany przy imporcie (R2-17)")
    func corruptFileQuarantinedAndLocked() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        try dir.write("[{uszkodzony", to: "custom_languages.json")
        let service = LocalizationService(customLanguagesURL: dir.file("custom_languages.json"))

        #expect(service.loadIssue != nil)
        #expect(throws: (any Error).self) {
            try service.importTranslation(data: translation, fallbackFilename: "fr")
        }
        #expect(try String(contentsOf: dir.file("custom_languages.json"), encoding: .utf8) == "[{uszkodzony")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names.contains { $0.hasPrefix("custom_languages.corrupt-") })
    }

    @Test("Szablon bez instructionsForAI i context (np. po tłumaczeniu przez AI) daje wszystkie tłumaczenia (R2-17)")
    func lenientPackage() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        let package = Data(#"""
        {"schema":"cantate-presenter-i18n-v2","sourceLanguage":"pl","targetLanguageCode":"fr","targetLanguageName":"Français",
         "translations":[{"key":"Biblioteka pieśni","translation":"Bibliothèque"},{"key":"Anuluj","sourceText":"Anuluj","translation":"Annuler"}]}
        """#.utf8)

        let result = try LocalizationService(customLanguagesURL: dir.file("custom_languages.json")).importTranslation(data: package, fallbackFilename: "x")

        #expect(result.code == "fr")
        #expect(result.count == 2)
    }

    @Test("Lista tłumaczeń jako tablica w formacie luźnym (R2-17)")
    func translationsArrayFallback() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        let package = Data(#"{"code":"fr","translations":[{"key":"Anuluj","translation":"Annuler"},{"key":"Zapisz","translation":""}]}"#.utf8)

        let result = try LocalizationService(customLanguagesURL: dir.file("custom_languages.json")).importTranslation(data: package, fallbackFilename: "x")

        #expect(result.count == 1)
    }

    @Test("Nieudany zapis nie zostawia języka w pamięci (R2-17)")
    func failedSaveDoesNotChangeMemory() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        try dir.write("plik", to: "zablokowane")
        let service = LocalizationService(customLanguagesURL: dir.file("zablokowane/custom_languages.json"))

        _ = try? service.importTranslation(data: translation, fallbackFilename: "fr")

        #expect(service.customLanguages.isEmpty)
    }

    @Test("Język bez flagi i tekstów w pliku się wczytuje (R2-23)")
    func tolerantCustomLanguageDecoding() throws {
        let languages = try JSONDecoder().decode([CustomLanguage].self, from: Data(#"[{"code":"fr","name":"Français"},{"code":"it"}]"#.utf8))
        #expect(languages.map(\.code) == ["fr", "it"])
        #expect(languages.last?.name == "it")
        #expect(languages.first?.flag == "🌐")
    }

    @Test("Jedna wartość, która nie jest tekstem, nie kasuje pozostałych tłumaczeń języka (R6-09)")
    func nonStringValueKeepsOtherStrings() throws {
        let data = Data(#"[{"code":"fr","name":"Français","strings":{"Zapisz":"Enregistrer","Rozmiar":12}}]"#.utf8)
        let languages = try JSONFileStore.makeDecoder().decode([CustomLanguage].self, from: data)
        #expect(languages.first?.strings == ["Zapisz": "Enregistrer"])
    }

    @Test("Dane z nowszej wersji (tylko odczyt): import języka nie zmienia pliku języków (R6-08)")
    func newerSchemaBlocksImport() throws {
        let dir = try TestDirectory()
        defer { dir.remove(); Localization.setOverlay([:], for: "fr") }
        try dir.write(#"{"schemaVersion": 99}"#, to: "settings.json")
        let original = #"[{"code":"de","name":"Deutsch","strings":{"Zapisz":"Speichern"},"newField":true}]"#
        try dir.write(original, to: "custom_languages.json")
        let service = LocalizationService(customLanguagesURL: dir.file("custom_languages.json"))

        #expect(throws: (any Error).self) {
            try service.importTranslation(data: translation, fallbackFilename: "fr")
        }
        #expect(try String(contentsOf: dir.file("custom_languages.json"), encoding: .utf8) == original)
        #expect(service.customLanguages.map(\.code) == ["de"])
    }
}
