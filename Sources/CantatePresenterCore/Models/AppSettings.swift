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
    public static var availableKeys: [KeyChoice] { [
        KeyChoice(49, Lnow("Spacja (Space)")),
        KeyChoice(124, Lnow("Strzałka w prawo (→)")),
        KeyChoice(123, Lnow("Strzałka w lewo (←)")),
        KeyChoice(125, Lnow("Strzałka w dół (↓)")),
        KeyChoice(126, Lnow("Strzałka w górę (↑)")),
        KeyChoice(36, "Enter / Return (↵)"),
        KeyChoice(53, "Escape (Esc)"),
        KeyChoice(48, "Tabulator (Tab)"),
        KeyChoice(51, "Backspace (⌫)"),
        KeyChoice(121, "Page Down (⇟)"),
        KeyChoice(116, "Page Up (⇞)"),
        KeyChoice(11, Lnow("Klawisz B")),
        KeyChoice(8, Lnow("Klawisz C")),
        KeyChoice(15, Lnow("Klawisz R")),
        KeyChoice(45, Lnow("Klawisz N")),
        KeyChoice(35, Lnow("Klawisz P")),
        KeyChoice(33, Lnow("Klawisz [ (Lewy nawias)")),
        KeyChoice(30, Lnow("Klawisz ] (Prawy nawias)")),
        KeyChoice(96, Lnow("Klawisz F5")),
        KeyChoice(97, Lnow("Klawisz F6"))
    ] }
    
    public static func nameForKeyCode(_ code: UInt16) -> String {
        return availableKeys.first(where: { $0.id == code })?.name ?? Lnow("Klawisz (kod: {0})", code)
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
    
    // Tolerancyjny dekoder (K1): brakujący skrót dostaje wartość domyślną, zamiast odrzucać całe ustawienia.
    private enum CodingKeys: String, CodingKey {
        case nextSlideKey, prevSlideKey, prevSongKey, nextSongKey, startPresentationKey, stopPresentationKey, blackScreenKey, clearTextKey
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ShortcutSettings()
        func key(_ codingKey: CodingKeys, _ fallback: UInt16) -> UInt16 {
            (try? container.decodeIfPresent(UInt16.self, forKey: codingKey)) ?? fallback
        }
        self.init(
            nextSlideKey: key(.nextSlideKey, defaults.nextSlideKey),
            prevSlideKey: key(.prevSlideKey, defaults.prevSlideKey),
            prevSongKey: key(.prevSongKey, defaults.prevSongKey),
            nextSongKey: key(.nextSongKey, defaults.nextSongKey),
            startPresentationKey: key(.startPresentationKey, defaults.startPresentationKey),
            stopPresentationKey: key(.stopPresentationKey, defaults.stopPresentationKey),
            blackScreenKey: key(.blackScreenKey, defaults.blackScreenKey),
            clearTextKey: key(.clearTextKey, defaults.clearTextKey)
        )
    }
}

// MARK: - Text Alignment (N2)

/// Wyrównanie poziome tekstu slajdu. W JSON te same napisy co wcześniej; stare „lewo”/„prawo”
/// i nieznane wartości są przyjmowane bez błędu.
public enum HorizontalTextAlignment: String, Codable, CaseIterable {
    case left, center, right
    
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        switch value {
        case "left", "lewo": self = .left
        case "right", "prawo": self = .right
        default: self = .center
        }
    }
}

public enum VerticalTextAlignment: String, Codable, CaseIterable {
    case top, center, bottom
    
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = VerticalTextAlignment(rawValue: value) ?? .center
    }
}

/// Gdzie pokazywać informację o prawach autorskich (©, numer CCLI) przy pieśniach z numerem CCLI.
public enum CopyrightNoticePlacement: String, Codable, CaseIterable {
    case none, firstSlide, lastSlide, allSlides
    
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = CopyrightNoticePlacement(rawValue: value) ?? .firstSlide
    }
}

public struct AppSettings: Codable, Equatable {
    public var selectedScreenIndex: Int
    /// Ekran projekcji po identyfikatorze i nazwie (S1); `selectedScreenIndex` tylko dla starych plików.
    public var selectedScreenID: UInt32?
    public var selectedScreenName: String?
    public var fontFamily: String
    public var isBold: Bool
    public var textColorHex: String
    public var backgroundColorHex: String
    public var hasShadow: Bool
    public var textAlignment: HorizontalTextAlignment
    public var verticalAlignment: VerticalTextAlignment
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
    /// Rozpoznawanie mowy tylko na tym Macu, bez wysyłania nagrań do Apple (N4). Domyślnie wyłączone:
    /// wymaga pobranego modelu mowy i włączonego dyktowania w systemie.
    public var dictationOnDeviceOnly: Bool = false
    public var activeLogoId: String // "light_of_glory", etc.
    /// Numer licencji CCLI parafii (CCLI License #), dopisywany do informacji o prawach na slajdzie.
    public var ccliLicenseNumber: String = ""
    public var copyrightNoticePlacement: CopyrightNoticePlacement = .firstSlide
    /// Ekran dla muzyków na Macu: wielkość czcionki i transpozycja (np. pod capo).
    public var musicianFontSize: Double = 30
    public var musicianTranspose: Int = 0
    public var googleDrive: GoogleDriveSettings
    
    public init(
        selectedScreenIndex: Int = 1,
        fontFamily: String = "Helvetica Neue",
        isBold: Bool = true,
        textColorHex: String = "#FFFFFF",
        backgroundColorHex: String = "#000000",
        hasShadow: Bool = true,
        textAlignment: HorizontalTextAlignment = .center,
        verticalAlignment: VerticalTextAlignment = .center,
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
        self.selectedScreenID = try container.decodeIfPresent(UInt32.self, forKey: .selectedScreenID)
        self.selectedScreenName = try container.decodeIfPresent(String.self, forKey: .selectedScreenName)
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Helvetica Neue"
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? true
        self.textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FFFFFF"
        self.backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#000000"
        self.hasShadow = try container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? true
        self.textAlignment = try container.decodeIfPresent(HorizontalTextAlignment.self, forKey: .textAlignment) ?? .center
        self.verticalAlignment = try container.decodeIfPresent(VerticalTextAlignment.self, forKey: .verticalAlignment) ?? .center
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
        self.dictationOnDeviceOnly = try container.decodeIfPresent(Bool.self, forKey: .dictationOnDeviceOnly) ?? false
        self.activeLogoId = try container.decodeIfPresent(String.self, forKey: .activeLogoId) ?? "light_of_glory"
        self.ccliLicenseNumber = try container.decodeIfPresent(String.self, forKey: .ccliLicenseNumber) ?? ""
        self.copyrightNoticePlacement = try container.decodeIfPresent(CopyrightNoticePlacement.self, forKey: .copyrightNoticePlacement) ?? .firstSlide
        self.musicianFontSize = min(80, max(14, (try? container.decodeIfPresent(Double.self, forKey: .musicianFontSize)) ?? 30))
        self.musicianTranspose = ((try? container.decodeIfPresent(Int.self, forKey: .musicianTranspose)) ?? 0) % 12
        self.googleDrive = try container.decodeIfPresent(GoogleDriveSettings.self, forKey: .googleDrive) ?? GoogleDriveSettings()
    }
}

public struct GoogleDriveSettings: Codable, Equatable {
    public var isEnabled: Bool
    /// Adres konta ustawiany po zalogowaniu; tylko do wyświetlenia.
    public var accountEmail: String
    /// Tokeny są w Pęku kluczy (`GoogleCredentialStore`, W4), klient OAuth jest wbudowany w aplikację.
    public var targetFolder: String
    public var autoBackupOnExit: Bool
    public var lastBackupDate: Date?
    
    /// Sekrety odczytane ze starego `settings.json`; do przeniesienia do Pęku kluczy, nigdy nie zapisywane.
    private var legacySecrets: GoogleCredentials?
    
    public init(
        isEnabled: Bool = false,
        accountEmail: String = "",
        targetFolder: String = "CantatePresenter_Backups",
        autoBackupOnExit: Bool = false,
        lastBackupDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.accountEmail = accountEmail
        self.targetFolder = targetFolder
        self.autoBackupOnExit = autoBackupOnExit
        self.lastBackupDate = lastBackupDate
    }
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case isEnabled, accountEmail, targetFolder, autoBackupOnExit, lastBackupDate
        // Tylko odczyt starych plików (własny klient użytkownika, clientId/clientSecret, jest pomijany)
        case accessToken, refreshToken
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail) ?? ""
        self.targetFolder = try container.decodeIfPresent(String.self, forKey: .targetFolder) ?? "CantatePresenter_Backups"
        self.autoBackupOnExit = try container.decodeIfPresent(Bool.self, forKey: .autoBackupOnExit) ?? false
        self.lastBackupDate = try container.decodeIfPresent(Date.self, forKey: .lastBackupDate)
        
        let legacy = GoogleCredentials(
            accessToken: try container.decodeIfPresent(String.self, forKey: .accessToken) ?? "",
            refreshToken: try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        )
        self.legacySecrets = legacy == GoogleCredentials() ? nil : legacy
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(accountEmail, forKey: .accountEmail)
        try container.encode(targetFolder, forKey: .targetFolder)
        try container.encode(autoBackupOnExit, forKey: .autoBackupOnExit)
        try container.encodeIfPresent(lastBackupDate, forKey: .lastBackupDate)
    }
    
    // MARK: - Legacy Secrets Migration (W4)
    
    public var hasLegacySecrets: Bool { legacySecrets != nil }
    
    /// Przenosi sekrety ze starego `settings.json` do Pęku kluczy, nie nadpisując niepustych wartości.
    public mutating func migrateLegacySecrets(into store: GoogleCredentialStore) throws {
        guard let legacy = legacySecrets else { return }
        try store.update { credentials in
            if credentials.refreshToken.isEmpty { credentials.refreshToken = legacy.refreshToken }
            if credentials.accessToken.isEmpty {
                credentials.accessToken = legacy.accessToken
                credentials.expiresAt = nil
            }
        }
        legacySecrets = nil
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
    
    public static var searchLanguages: [LanguageChoice] { [
        LanguageChoice("pl", Lnow("Polski (pieśni w j. polskim)"), "🇵🇱"),
        LanguageChoice("en", "Angielski / English", "🇬🇧"),
        LanguageChoice("de", "Niemiecki / Deutsch", "🇩🇪"),
        LanguageChoice("es", Lnow("Hiszpański / Español"), "🇪🇸"),
        LanguageChoice("all", Lnow("Wszystkie języki (bez filtra)"), "🌐")
    ] }
    
    public static var dictationLanguages: [LanguageChoice] { [
        LanguageChoice("pl-PL", "Polski (Polska)", "🇵🇱"),
        LanguageChoice("en-US", "English (United States)", "🇺🇸"),
        LanguageChoice("en-GB", "English (United Kingdom)", "🇬🇧"),
        LanguageChoice("de-DE", "Deutsch (Deutschland)", "🇩🇪"),
        LanguageChoice("es-ES", "Español (España)", "🇪🇸"),
        LanguageChoice("uk-UA", "Українська (Україна)", "🇺🇦"),
        LanguageChoice("it-IT", "Italiano (Italia)", "🇮🇹"),
        LanguageChoice("fr-FR", "Français (France)", "🇫🇷")
    ] }
}
