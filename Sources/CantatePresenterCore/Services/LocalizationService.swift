import Foundation
import Combine
import SwiftUI

public struct CustomLanguage: Codable, Identifiable, Equatable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let flag: String
    public var strings: [String: String]
    
    public init(code: String, name: String, flag: String = "🌐", strings: [String: String]) {
        self.code = code
        self.name = name
        self.flag = flag.isEmpty ? "🌐" : flag
        self.strings = strings
    }
}

public struct TranslationTemplateItem: Codable {
    public let key: String
    public let sourceText: String
    public var translation: String
    public let context: String
    
    public init(key: String, sourceText: String, translation: String, context: String) {
        self.key = key
        self.sourceText = sourceText
        self.translation = translation
        self.context = context
    }
}

public struct TranslationPackage: Codable {
    public let schema: String
    public let sourceLanguage: String
    public var targetLanguageCode: String
    public var targetLanguageName: String
    public var targetLanguageFlag: String
    public let instructionsForAI: String
    public var translations: [TranslationTemplateItem]
    
    public init(
        schema: String = "holyrics-mac-i18n-v1",
        sourceLanguage: String = "pl",
        targetLanguageCode: String = "",
        targetLanguageName: String = "",
        targetLanguageFlag: String = "",
        instructionsForAI: String = "Dla każdego elementu w liście 'translations' przetłumacz wartość w polu 'translation' na język docelowy. Pole 'context' wyjaśnia przeznaczenie tekstu w interfejsie macOS (np. przycisk akcji, zakładka, komunikat), pomagając dobrać właściwą formę gramatyczną. Zachowaj zwięzłość i spójność.",
        translations: [TranslationTemplateItem] = []
    ) {
        self.schema = schema
        self.sourceLanguage = sourceLanguage
        self.targetLanguageCode = targetLanguageCode
        self.targetLanguageName = targetLanguageName
        self.targetLanguageFlag = targetLanguageFlag
        self.instructionsForAI = instructionsForAI
        self.translations = translations
    }
}

@MainActor
public final class LocalizationService: ObservableObject {
    public static let shared = LocalizationService()
    
    /// Języki zaimportowane z JSON; działają jako nakładka na String Catalog (S10).
    @Published public var customLanguages: [CustomLanguage] = [] {
        didSet { applyOverlays() }
    }
    
    /// Klucze starych plików tłumaczeń (sprzed String Catalog) → polski tekst źródłowy.
    static let legacyKeys: [String: String] = [
        "appLanguage": "Język aplikacji",
        "appTitle": "CantatePresenter",
        "blackScreen": "Czarny",
        "bottomBarHeight": "Wysokość dolnego paska",
        "bridge": "Bridge / Mostek",
        "cancel": "Anuluj",
        "chords": "Chwyty gitarowe",
        "chorus": "Refren",
        "clearText": "Czysty",
        "coda": "Coda",
        "dictation": "Dyktowanie głosem",
        "dictationLanguage": "Język dyktowania głosem",
        "editSong": "Edycja pieśni",
        "ending": "Zakończenie",
        "importExport": "Import/Eksport",
        "interlude": "Przejście",
        "libraryTab": "Biblioteka pieśni",
        "newSong": "Nowa pieśń",
        "nextSlide": "Następny",
        "nextSong": "Nast. pieśń",
        "noSongsFound": "Nie znaleziono pieśni",
        "online": "Online",
        "planTab": "Plan nabożeństwa",
        "present": "Prezentuj",
        "prevSlide": "Poprzedni",
        "prevSong": "Poprz. pieśń",
        "projectorActive": "Projektor: Aktywny",
        "rawLyricsHint": "Wskazówka: oddzielaj zwrotki pustą linią",
        "save": "Zapisz",
        "searchLanguage": "Język wyszukiwania pieśni",
        "searchPlaceholder": "Szukaj w tytule, autorze i tekście...",
        "settings": "Ustawienia",
        "songsInLibrary": "pieśni w bibliotece",
        "standby": "Standby",
        "testWindowActive": "Okno testowe",
        "titleAuthor": "Tytuł/Autor",
        "uiScale": "Rozmiar UI",
        "verse": "Zwrotka",
    ]
    
    private let customLanguagesURL: URL
    
    public convenience init() {
        self.init(customLanguagesURL: AppPaths.shared.customLanguagesFile)
    }
    
    init(customLanguagesURL: URL) {
        self.customLanguagesURL = customLanguagesURL
        loadCustomLanguages()
    }
    
    public var availableLanguages: [LanguageChoice] {
        var list: [LanguageChoice] = [
            LanguageChoice("pl", "Polski", "🇵🇱"),
            LanguageChoice("en", "English", "🇬🇧"),
            LanguageChoice("de", "Deutsch", "🇩🇪"),
            LanguageChoice("es", "Español", "🇪🇸"),
            LanguageChoice("uk", "Українська", "🇺🇦")
        ]
        
        for custom in customLanguages {
            if !list.contains(where: { $0.code == custom.code }) {
                list.append(LanguageChoice(custom.code, custom.name, custom.flag))
            }
        }
        
        return list
    }
    
    /// Klucze starych plików zamieniane na polskie teksty, żeby dawne tłumaczenia nadal działały.
    static func normalizedStrings(_ strings: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in strings {
            result[legacyKeys[key] ?? key] = value
        }
        return result
    }
    
    private func applyOverlays() {
        for language in customLanguages {
            Localization.setOverlay(Self.normalizedStrings(language.strings), for: language.code)
        }
    }
    
    // MARK: - Export Translation Template (for AI and Human Translators)
    
    /// Szablon: kluczem i tekstem źródłowym jest polski tekst z katalogu, a kontekstem tłumaczenie angielskie.
    /// `{0}`, `{1}` to wstawiane wartości i muszą zostać w tłumaczeniu.
    public func generateExportPackage(sourceLanguage: String = "pl") -> TranslationPackage {
        let reference = Localization.catalogKeys(referenceLanguage: "en")
        let items = reference.keys.sorted().map { key in
            TranslationTemplateItem(
                key: key,
                sourceText: key,
                translation: "",
                context: "English: \(reference[key] ?? "")"
            )
        }
        return TranslationPackage(
            schema: "cantate-presenter-i18n-v2",
            sourceLanguage: Localization.sourceLanguage,
            targetLanguageCode: "wpisz_kod_np_fr",
            targetLanguageName: "Wpisz nazwę języka (np. Français)",
            targetLanguageFlag: "🇫🇷",
            translations: items
        )
    }
    
    public func exportTemplateJSON(sourceLanguage: String = "pl") -> String? {
        let package = generateExportPackage(sourceLanguage: sourceLanguage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(package) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Import Translation Package
    public func importTranslation(from url: URL) throws -> (code: String, name: String, count: Int) {
        let data = try Data(contentsOf: url)
        return try importTranslation(data: data, fallbackFilename: url.deletingPathExtension().lastPathComponent)
    }
    
    public func importTranslation(data: Data, fallbackFilename: String = "custom") throws -> (code: String, name: String, count: Int) {
        let decoder = JSONDecoder()
        
        var targetCode = ""
        var targetName = ""
        var targetFlag = "🌐"
        var parsedStrings: [String: String] = [:]
        
        if let package = try? decoder.decode(TranslationPackage.self, from: data) {
            targetCode = package.targetLanguageCode.trimmingCharacters(in: .whitespaces)
            targetName = package.targetLanguageName.trimmingCharacters(in: .whitespaces)
            targetFlag = package.targetLanguageFlag.trimmingCharacters(in: .whitespaces)
            
            for item in package.translations {
                let trans = item.translation.trimmingCharacters(in: .whitespaces)
                if !trans.isEmpty {
                    parsedStrings[item.key] = trans
                }
            }
        } else if let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Flexible format (flat key-value or wrapped)
            if let stringsObj = rawDict["translations"] as? [String: String] {
                parsedStrings = stringsObj
            } else if let stringsObj = rawDict["strings"] as? [String: String] {
                parsedStrings = stringsObj
            } else {
                for (k, v) in rawDict {
                    if let str = v as? String {
                        parsedStrings[k] = str
                    }
                }
            }
            
            targetCode = (rawDict["targetLanguageCode"] as? String) ?? (rawDict["code"] as? String) ?? fallbackFilename
            targetName = (rawDict["targetLanguageName"] as? String) ?? (rawDict["name"] as? String) ?? fallbackFilename.capitalized
            targetFlag = (rawDict["targetLanguageFlag"] as? String) ?? (rawDict["flag"] as? String) ?? "🌐"
        } else {
            throw NSError(domain: "LocalizationService", code: 400, userInfo: [NSLocalizedDescriptionKey: Lnow("Nieprawidłowy format pliku JSON tłumaczenia")])
        }
        
        if targetCode.isEmpty || targetCode == "wpisz_kod_np_fr" {
            targetCode = fallbackFilename.lowercased()
        }
        if targetName.isEmpty || targetName.contains("Wpisz") {
            targetName = fallbackFilename.capitalized
        }
        if targetFlag.isEmpty {
            targetFlag = "🌐"
        }
        
        let customLang = CustomLanguage(code: targetCode, name: targetName, flag: targetFlag, strings: parsedStrings)
        
        // Remove existing with same code if updating
        customLanguages.removeAll(where: { $0.code == targetCode })
        customLanguages.append(customLang)
        
        try saveCustomLanguages()
        
        return (code: targetCode, name: targetName, count: parsedStrings.count)
    }
    
    /// Zapis przez `JSONFileStore` (kopie przed zapisem); błąd trafia do wywołującego, nie jest połykany (N7).
    private func saveCustomLanguages() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try JSONFileStore().save(customLanguages, to: customLanguagesURL, encoder: encoder)
    }
    
    /// Nieczytelny plik jest kopiowany do kwarantanny, zanim kolejny import go nadpisze.
    public func loadCustomLanguages() {
        if case .loaded(let loaded) = JSONFileStore().load([CustomLanguage].self, from: customLanguagesURL) {
            self.customLanguages = loaded
        }
    }
}
