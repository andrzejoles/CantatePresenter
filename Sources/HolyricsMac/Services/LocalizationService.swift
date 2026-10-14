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
    
    public enum Key: String, CaseIterable, Codable {
        case appTitle
        case libraryTab
        case planTab
        case searchPlaceholder
        case newSong
        case editSong
        case importExport
        case online
        case titleAuthor
        case present
        case standby
        case blackScreen
        case clearText
        case prevSlide
        case nextSlide
        case prevSong
        case nextSong
        case chorus
        case verse
        case bridge
        case coda
        case interlude
        case ending
        case chords
        case settings
        case dictation
        case appLanguage
        case searchLanguage
        case dictationLanguage
        case projectorActive
        case testWindowActive
        case uiScale
        case bottomBarHeight
        case songsInLibrary
        case noSongsFound
        case rawLyricsHint
        case save
        case cancel
        
        public var contextDescription: String {
            switch self {
            case .appTitle:
                return "Główny tytuł okna programu na pasku tytułu i w nagłówkach aplikacji"
            case .libraryTab:
                return "Nazwa pierwszej zakładki bocznej: Biblioteka wszystkich zapisanych pieśni"
            case .planTab:
                return "Nazwa drugiej zakładki bocznej: Aktywny plan pieśni na nabożeństwo/mszę"
            case .searchPlaceholder:
                return "Tekst podpowiedzi (placeholder) w pasku wyszukiwarki pieśni"
            case .newSong:
                return "Przycisk dodania nowej pieśni do bazy danych (+ Nowa pieśń)"
            case .editSong:
                return "Przycisk edycji tekstu, zwrotek i chwytów wybranej pieśni (Edycja pieśni)"
            case .importExport:
                return "Przycisk otwierający okno importu plików (.mufl, .txt) i eksportu pieśni"
            case .online:
                return "Przycisk otwierający wyszukiwarkę pieśni w internecie"
            case .titleAuthor:
                return "Przycisk wyszukiwarki i uzupełniania brakującego autora/tytułu utworu"
            case .present:
                return "Główny przycisk prezentacji: wyświetla slajd pieśni na żywo na projektorze"
            case .standby:
                return "Przycisk planszy czuwania / wygaszacza z logo programu"
            case .blackScreen:
                return "Przycisk natychmiastowego zaciemnienia całego ekranu projekcji"
            case .clearText:
                return "Przycisk ukrycia tekstu pieśni z zachowaniem tła projekcji"
            case .prevSlide:
                return "Przycisk nawigacji: przejście do poprzedniego slajdu pieśni"
            case .nextSlide:
                return "Przycisk nawigacji: przejście do następnego slajdu pieśni"
            case .prevSong:
                return "Przycisk nawigacji: przejście do poprzedniej pieśni z planu"
            case .nextSong:
                return "Przycisk nawigacji: przejście do kolejnej pieśni z planu"
            case .chorus:
                return "Przycisk szybkiego skoku do Refrenu pieśni"
            case .verse:
                return "Etykieta oznaczająca Zwrotkę pieśni"
            case .bridge:
                return "Etykieta sekcji muzycznej Bridge / Mostek"
            case .coda:
                return "Etykieta sekcji muzycznej Coda / Koda (zwieńczenie utworu)"
            case .interlude:
                return "Etykieta sekcji muzycznej Przejście / Solo instrumentalne"
            case .ending:
                return "Etykieta sekcji muzycznej Zakończenie / Outro"
            case .chords:
                return "Etykieta i przycisk zakładki akordów i chwytów gitarowych"
            case .settings:
                return "Przycisk otwierający okno preferencji i konfiguracji programu"
            case .dictation:
                return "Przycisk dyktowania głosem (zamiana mowy na tekst)"
            case .appLanguage:
                return "Etykieta wyboru języka interfejsu programu w ustawieniach"
            case .searchLanguage:
                return "Etykieta wyboru domyślnego języka przeszukiwania pieśni w sieci"
            case .dictationLanguage:
                return "Etykieta wyboru języka rozpoznawania mowy dla dyktowania"
            case .projectorActive:
                return "Status informujący, że zewnętrzny ekran projekcji jest podłączony"
            case .testWindowActive:
                return "Przycisk otwarcia podglądu projekcji w osobnym oknie testowym"
            case .uiScale:
                return "Etykieta suwaka powiększenia całego interfejsu (skalowanie UI)"
            case .bottomBarHeight:
                return "Etykieta suwaka wysokości dolnego paska sterowania"
            case .songsInLibrary:
                return "Tekst w stopce biblioteki: liczba pieśni w bibliotece"
            case .noSongsFound:
                return "Komunikat wyświetlany, gdy żadna pieśń nie pasuje do wyszukiwania"
            case .rawLyricsHint:
                return "Podpowiedź formatowania w edytorze tekstu pieśni"
            case .save:
                return "Przycisk zatwierdzenia i zapisu danych"
            case .cancel:
                return "Przycisk anulowania zmian i zamknięcia okna"
            }
        }
    }
    
    @Published public var customLanguages: [CustomLanguage] = []
    
    private let builtInTranslations: [String: [Key: String]] = [
        "pl": [
            .appTitle: "Prezenter Pieśni",
            .libraryTab: "Biblioteka pieśni",
            .planTab: "Plan nabożeństwa",
            .searchPlaceholder: "Szukaj w tytule, autorze i tekście...",
            .newSong: "Nowa pieśń",
            .editSong: "Edycja pieśni",
            .importExport: "Import/Eksport",
            .online: "Online",
            .titleAuthor: "Tytuł/Autor",
            .present: "Prezentuj",
            .standby: "Standby",
            .blackScreen: "Czarny",
            .clearText: "Czysty",
            .prevSlide: "Poprzedni",
            .nextSlide: "Następny",
            .prevSong: "Poprz. pieśń",
            .nextSong: "Nast. pieśń",
            .chorus: "Refren",
            .verse: "Zwrotka",
            .bridge: "Bridge / Mostek",
            .coda: "Coda",
            .interlude: "Przejście",
            .ending: "Zakończenie",
            .chords: "Chwyty gitarowe",
            .settings: "Ustawienia",
            .dictation: "Dyktowanie głosem",
            .appLanguage: "Język aplikacji",
            .searchLanguage: "Język wyszukiwania pieśni",
            .dictationLanguage: "Język dyktowania głosem",
            .projectorActive: "Projektor: Aktywny",
            .testWindowActive: "Okno testowe",
            .uiScale: "Rozmiar UI",
            .bottomBarHeight: "Wysokość dolnego paska",
            .songsInLibrary: "pieśni w bibliotece",
            .noSongsFound: "Nie znaleziono pieśni",
            .rawLyricsHint: "Wskazówka: oddzielaj zwrotki pustą linią",
            .save: "Zapisz",
            .cancel: "Anuluj"
        ],
        "en": [
            .appTitle: "Holyrics Presenter",
            .libraryTab: "Song Library",
            .planTab: "Service Plan",
            .searchPlaceholder: "Search in title, author and lyrics...",
            .newSong: "New Song",
            .editSong: "Edit Song",
            .importExport: "Import/Export",
            .online: "Online",
            .titleAuthor: "Title/Author",
            .present: "Present",
            .standby: "Standby",
            .blackScreen: "Black Screen",
            .clearText: "Clear Text",
            .prevSlide: "Previous",
            .nextSlide: "Next",
            .prevSong: "Prev Song",
            .nextSong: "Next Song",
            .chorus: "Chorus",
            .verse: "Verse",
            .bridge: "Bridge",
            .coda: "Coda",
            .interlude: "Interlude",
            .ending: "Ending",
            .chords: "Guitar Chords",
            .settings: "Settings",
            .dictation: "Voice Dictation",
            .appLanguage: "App Interface Language",
            .searchLanguage: "Online Song Search Language",
            .dictationLanguage: "Voice Dictation Language",
            .projectorActive: "Projector: Active",
            .testWindowActive: "Test Window",
            .uiScale: "UI Scale",
            .bottomBarHeight: "Bottom Bar Height",
            .songsInLibrary: "songs in library",
            .noSongsFound: "No songs found",
            .rawLyricsHint: "Tip: separate verses with an empty blank line",
            .save: "Save",
            .cancel: "Cancel"
        ],
        "de": [
            .appTitle: "Lieder-Präsentator",
            .libraryTab: "Liederbibliothek",
            .planTab: "Gottesdienstplan",
            .searchPlaceholder: "In Titel, Autor und Text suchen...",
            .newSong: "Neues Lied",
            .editSong: "Lied bearbeiten",
            .importExport: "Import/Export",
            .online: "Online",
            .titleAuthor: "Titel/Autor",
            .present: "Präsentieren",
            .standby: "Standby",
            .blackScreen: "Schwarz",
            .clearText: "Ausblenden",
            .prevSlide: "Zurück",
            .nextSlide: "Weiter",
            .prevSong: "Vorh. Lied",
            .nextSong: "Nächst. Lied",
            .chorus: "Refrain",
            .verse: "Strophe",
            .bridge: "Bridge",
            .coda: "Coda",
            .interlude: "Zwischenspiel",
            .ending: "Schluss / Outro",
            .chords: "Gitarrenakkorde",
            .settings: "Einstellungen",
            .dictation: "Sprachdiktat",
            .appLanguage: "Sprache der Anwendung",
            .searchLanguage: "Sprache der Liedersuche",
            .dictationLanguage: "Sprache für Diktat",
            .projectorActive: "Beamer: Aktiv",
            .testWindowActive: "Testfenster",
            .uiScale: "UI-Skalierung",
            .bottomBarHeight: "Höhe der Steuerleiste",
            .songsInLibrary: "Lieder in Bibliothek",
            .noSongsFound: "Keine Lieder gefunden",
            .rawLyricsHint: "Tipp: Verse durch Leerzeile trennen",
            .save: "Speichern",
            .cancel: "Abbrechen"
        ],
        "es": [
            .appTitle: "Presentador de Canciones",
            .libraryTab: "Biblioteca de canciones",
            .planTab: "Plan de culto",
            .searchPlaceholder: "Buscar en título, autor y letra...",
            .newSong: "Nueva canción",
            .editSong: "Editar canción",
            .importExport: "Importar/Exportar",
            .online: "En línea",
            .titleAuthor: "Título/Autor",
            .present: "Presentar",
            .standby: "En espera",
            .blackScreen: "Pantalla negra",
            .clearText: "Borrar texto",
            .prevSlide: "Anterior",
            .nextSlide: "Siguiente",
            .prevSong: "Canción ant.",
            .nextSong: "Canción sig.",
            .chorus: "Coro",
            .verse: "Estrofa",
            .bridge: "Puente / Bridge",
            .coda: "Coda",
            .interlude: "Interludio",
            .ending: "Final / Outro",
            .chords: "Acordes de guitarra",
            .settings: "Ajustes",
            .dictation: "Dictado por voz",
            .appLanguage: "Idioma de la aplicación",
            .searchLanguage: "Idioma de búsqueda de canciones",
            .dictationLanguage: "Idioma de dictado por voz",
            .projectorActive: "Proyector: Activo",
            .testWindowActive: "Ventana de prueba",
            .uiScale: "Escala de UI",
            .bottomBarHeight: "Altura de barra inferior",
            .songsInLibrary: "canciones en biblioteca",
            .noSongsFound: "No se encontraron canciones",
            .rawLyricsHint: "Consejo: separa las estrofas con una línea vacía",
            .save: "Guardar",
            .cancel: "Cancelar"
        ],
        "uk": [
            .appTitle: "Презентер Пісень",
            .libraryTab: "Бібліотека пісень",
            .planTab: "План служіння",
            .searchPlaceholder: "Шукати в назві, авторі та тексті...",
            .newSong: "Нова пісня",
            .editSong: "Редагувати пісню",
            .importExport: "Імпорт/Експорт",
            .online: "Онлайн",
            .titleAuthor: "Назва/Автор",
            .present: "Презентувати",
            .standby: "Очікування",
            .blackScreen: "Чорний",
            .clearText: "Очистити",
            .prevSlide: "Попередній",
            .nextSlide: "Наступний",
            .prevSong: "Попер. пісня",
            .nextSong: "Наст. пісня",
            .chorus: "Приспів",
            .verse: "Куплет",
            .bridge: "Брідж",
            .coda: "Кода",
            .interlude: "Програш / Інтерлюдія",
            .ending: "Закінчення",
            .chords: "Акорди для гітари",
            .settings: "Налаштування",
            .dictation: "Голосовий диктант",
            .appLanguage: "Мова інтерфейсу",
            .searchLanguage: "Мова пошуку пісень",
            .dictationLanguage: "Мова голосового диктанту",
            .projectorActive: "Проєктор: Активний",
            .testWindowActive: "Тестове вікно",
            .uiScale: "Масштаб UI",
            .bottomBarHeight: "Висота нижньої панелі",
            .songsInLibrary: "пісень у бібліотеці",
            .noSongsFound: "Пісень не знайдено",
            .rawLyricsHint: "Порада: розділяйте куплети порожнім рядком",
            .save: "Зберегти",
            .cancel: "Скасувати"
        ]
    ]
    
    private let customLanguagesURL: URL
    
    public init() {
        let bundleURL = Bundle.main.bundleURL
        let projectFolder: URL
        if bundleURL.pathExtension == "app" {
            projectFolder = bundleURL.deletingLastPathComponent()
        } else {
            projectFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        self.customLanguagesURL = projectFolder.appendingPathComponent("data/custom_languages.json")
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
    
    public func text(_ key: Key, lang: String? = nil) -> String {
        let code = lang ?? DataStore.shared.settings.appLanguage
        
        // 1. Check custom imported languages
        if let custom = customLanguages.first(where: { $0.code == code }),
           let customStr = custom.strings[key.rawValue],
           !customStr.trimmingCharacters(in: .whitespaces).isEmpty {
            return customStr
        }
        
        // 2. Check built-in translations
        if let dict = builtInTranslations[code], let str = dict[key] {
            return str
        }
        
        // 3. Fallback to Polish
        return builtInTranslations["pl"]?[key] ?? ""
    }
    
    // MARK: - Export Translation Template (for AI and Human Translators)
    public func generateExportPackage(sourceLanguage: String = "pl") -> TranslationPackage {
        let sourceDict = builtInTranslations[sourceLanguage] ?? builtInTranslations["pl"]!
        
        var items: [TranslationTemplateItem] = []
        for key in Key.allCases {
            let src = sourceDict[key] ?? ""
            items.append(TranslationTemplateItem(
                key: key.rawValue,
                sourceText: src,
                translation: "",
                context: key.contextDescription
            ))
        }
        
        return TranslationPackage(
            schema: "holyrics-mac-i18n-v1",
            sourceLanguage: sourceLanguage,
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
            throw NSError(domain: "LocalizationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy format pliku JSON tłumaczenia"])
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
        
        saveCustomLanguages()
        
        return (code: targetCode, name: targetName, count: parsedStrings.count)
    }
    
    private func saveCustomLanguages() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(customLanguages) {
            try? data.write(to: customLanguagesURL)
        }
    }
    
    private func loadCustomLanguages() {
        guard FileManager.default.fileExists(atPath: customLanguagesURL.path),
              let data = try? Data(contentsOf: customLanguagesURL) else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([CustomLanguage].self, from: data) {
            self.customLanguages = loaded
        }
    }
}

@MainActor
public func loc(_ key: LocalizationService.Key) -> String {
    return LocalizationService.shared.text(key)
}
