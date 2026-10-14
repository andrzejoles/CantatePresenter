import Foundation

public struct KeyChoice: Identifiable, Hashable {
    public let id: UInt16
    public let name: String
    
    public init(_ id: UInt16, _ name: String) {
        self.id = id
        self.name = name
    }
}

public struct ShortcutPresets {
    public static let availableKeys: [KeyChoice] = [
        KeyChoice(49, "Spacja (Space)"),
        KeyChoice(124, "Strzałka w prawo (→)"),
        KeyChoice(123, "Strzałka w lewo (←)"),
        KeyChoice(125, "Strzałka w dół (↓)"),
        KeyChoice(126, "Strzałka w górę (↑)"),
        KeyChoice(36, "Enter / Return (↵)"),
        KeyChoice(53, "Escape (Esc)"),
        KeyChoice(48, "Tabulator (Tab)"),
        KeyChoice(51, "Backspace (⌫)"),
        KeyChoice(121, "Page Down (⇟)"),
        KeyChoice(116, "Page Up (⇞)"),
        KeyChoice(11, "Klawisz B"),
        KeyChoice(8, "Klawisz C"),
        KeyChoice(15, "Klawisz R"),
        KeyChoice(45, "Klawisz N"),
        KeyChoice(35, "Klawisz P"),
        KeyChoice(33, "Klawisz [ (Lewy nawias)"),
        KeyChoice(30, "Klawisz ] (Prawy nawias)"),
        KeyChoice(96, "Klawisz F5"),
        KeyChoice(97, "Klawisz F6")
    ]
    
    public static func nameForKeyCode(_ code: UInt16) -> String {
        return availableKeys.first(where: { $0.id == code })?.name ?? "Klawisz (kod: \(code))"
    }
}

public struct ShortcutSettings: Codable, Equatable {
    public var nextSlideKey: UInt16
    public var prevSlideKey: UInt16
    public var prevSongKey: UInt16
    public var nextSongKey: UInt16
    public var startPresentationKey: UInt16
    public var stopPresentationKey: UInt16
    public var blackScreenKey: UInt16
    public var clearTextKey: UInt16
    
    public init(
        nextSlideKey: UInt16 = 49, // Space
        prevSlideKey: UInt16 = 123, // Left arrow
        prevSongKey: UInt16 = 33, // [
        nextSongKey: UInt16 = 30, // ]
        startPresentationKey: UInt16 = 36, // Return
        stopPresentationKey: UInt16 = 53, // Escape
        blackScreenKey: UInt16 = 11, // B
        clearTextKey: UInt16 = 8 // C
    ) {
        self.nextSlideKey = nextSlideKey
        self.prevSlideKey = prevSlideKey
        self.prevSongKey = prevSongKey
        self.nextSongKey = nextSongKey
        self.startPresentationKey = startPresentationKey
        self.stopPresentationKey = stopPresentationKey
        self.blackScreenKey = blackScreenKey
        self.clearTextKey = clearTextKey
    }
}

public struct AppSettings: Codable, Equatable {
    public var selectedScreenIndex: Int
    public var fontFamily: String
    public var isBold: Bool
    public var textColorHex: String
    public var backgroundColorHex: String
    public var hasShadow: Bool
    public var textAlignment: String // "center", "left", "right"
    public var verticalAlignment: String // "center", "top", "bottom"
    public var marginPercent: Double // 0.04 to 0.20
    public var lineSpacingFactor: Double // 1.0 to 1.6
    public var uiScale: Double // 0.85 to 1.6
    public var onlineSearchLanguage: String // "pl", "en", "de", "es", "all"
    public var isWindowedPreviewEnabled: Bool
    public var standbyHtmlPath: String
    public var shortcuts: ShortcutSettings
    public var bottomBarHeight: Double // 52.0 to 160.0, default 72.0
    public var appLanguage: String // "pl", "en", "de", "es", "uk"
    public var dictationLanguage: String // "pl-PL", "en-US", "de-DE", "es-ES", "uk-UA"
    public var activeLogoId: String // "light_of_glory", etc.
    public var googleDrive: GoogleDriveSettings
    
    public init(
        selectedScreenIndex: Int = 1,
        fontFamily: String = "Helvetica Neue",
        isBold: Bool = true,
        textColorHex: String = "#FFFFFF",
        backgroundColorHex: String = "#000000",
        hasShadow: Bool = true,
        textAlignment: String = "center",
        verticalAlignment: String = "center",
        marginPercent: Double = 0.07,
        lineSpacingFactor: Double = 1.15,
        uiScale: Double = 1.0,
        onlineSearchLanguage: String = "pl",
        isWindowedPreviewEnabled: Bool = false,
        standbyHtmlPath: String = "",
        shortcuts: ShortcutSettings = ShortcutSettings(),
        bottomBarHeight: Double = 72.0,
        appLanguage: String = "pl",
        dictationLanguage: String = "pl-PL",
        activeLogoId: String = "light_of_glory",
        googleDrive: GoogleDriveSettings = GoogleDriveSettings()
    ) {
        self.selectedScreenIndex = selectedScreenIndex
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.textColorHex = textColorHex
        self.backgroundColorHex = backgroundColorHex
        self.hasShadow = hasShadow
        self.textAlignment = textAlignment
        self.verticalAlignment = verticalAlignment
        self.marginPercent = marginPercent
        self.lineSpacingFactor = lineSpacingFactor
        self.uiScale = uiScale
        self.onlineSearchLanguage = onlineSearchLanguage
        self.isWindowedPreviewEnabled = isWindowedPreviewEnabled
        self.standbyHtmlPath = standbyHtmlPath
        self.shortcuts = shortcuts
        self.bottomBarHeight = bottomBarHeight
        self.appLanguage = appLanguage
        self.dictationLanguage = dictationLanguage
        self.activeLogoId = activeLogoId
        self.googleDrive = googleDrive
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedScreenIndex = try container.decodeIfPresent(Int.self, forKey: .selectedScreenIndex) ?? 1
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Helvetica Neue"
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? true
        self.textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FFFFFF"
        self.backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#000000"
        self.hasShadow = try container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? true
        self.textAlignment = try container.decodeIfPresent(String.self, forKey: .textAlignment) ?? "center"
        self.verticalAlignment = try container.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "center"
        self.marginPercent = try container.decodeIfPresent(Double.self, forKey: .marginPercent) ?? 0.07
        self.lineSpacingFactor = try container.decodeIfPresent(Double.self, forKey: .lineSpacingFactor) ?? 1.15
        self.uiScale = try container.decodeIfPresent(Double.self, forKey: .uiScale) ?? 1.0
        self.onlineSearchLanguage = try container.decodeIfPresent(String.self, forKey: .onlineSearchLanguage) ?? "pl"
        self.isWindowedPreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .isWindowedPreviewEnabled) ?? false
        self.standbyHtmlPath = try container.decodeIfPresent(String.self, forKey: .standbyHtmlPath) ?? ""
        self.shortcuts = try container.decodeIfPresent(ShortcutSettings.self, forKey: .shortcuts) ?? ShortcutSettings()
        self.bottomBarHeight = try container.decodeIfPresent(Double.self, forKey: .bottomBarHeight) ?? 72.0
        self.appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "pl"
        self.dictationLanguage = try container.decodeIfPresent(String.self, forKey: .dictationLanguage) ?? "pl-PL"
        self.activeLogoId = try container.decodeIfPresent(String.self, forKey: .activeLogoId) ?? "light_of_glory"
        self.googleDrive = try container.decodeIfPresent(GoogleDriveSettings.self, forKey: .googleDrive) ?? GoogleDriveSettings()
    }
}

public struct GoogleDriveSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var accountEmail: String
    public var clientId: String
    public var clientSecret: String
    public var accessToken: String
    public var refreshToken: String
    public var targetFolder: String
    public var autoBackupOnExit: Bool
    public var lastBackupDate: Date?
    
    public init(
        isEnabled: Bool = false,
        accountEmail: String = "andrzej.oles.tel@gmail.com",
        clientId: String = "",
        clientSecret: String = "",
        accessToken: String = "",
        refreshToken: String = "",
        targetFolder: String = "HolyricsMac_Backups",
        autoBackupOnExit: Bool = false,
        lastBackupDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.accountEmail = accountEmail
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.targetFolder = targetFolder
        self.autoBackupOnExit = autoBackupOnExit
        self.lastBackupDate = lastBackupDate
    }
}

public struct LanguageChoice: Identifiable, Hashable {
    public let code: String
    public let name: String
    public let flag: String
    public var id: String { code }
    
    public init(_ code: String, _ name: String, _ flag: String = "") {
        self.code = code
        self.name = name
        self.flag = flag
    }
}

public struct LanguagePresets {
    @MainActor
    public static var appLanguages: [LanguageChoice] {
        return LocalizationService.shared.availableLanguages
    }
    
    public static let searchLanguages: [LanguageChoice] = [
        LanguageChoice("pl", "Polski (pieśni w j. polskim)", "🇵🇱"),
        LanguageChoice("en", "Angielski / English", "🇬🇧"),
        LanguageChoice("de", "Niemiecki / Deutsch", "🇩🇪"),
        LanguageChoice("es", "Hiszpański / Español", "🇪🇸"),
        LanguageChoice("all", "Wszystkie języki (bez filtra)", "🌐")
    ]
    
    public static let dictationLanguages: [LanguageChoice] = [
        LanguageChoice("pl-PL", "Polski (Polska)", "🇵🇱"),
        LanguageChoice("en-US", "English (United States)", "🇺🇸"),
        LanguageChoice("en-GB", "English (United Kingdom)", "🇬🇧"),
        LanguageChoice("de-DE", "Deutsch (Deutschland)", "🇩🇪"),
        LanguageChoice("es-ES", "Español (España)", "🇪🇸"),
        LanguageChoice("uk-UA", "Українська (Україна)", "🇺🇦"),
        LanguageChoice("it-IT", "Italiano (Italia)", "🇮🇹"),
        LanguageChoice("fr-FR", "Français (France)", "🇫🇷")
    ]
}
