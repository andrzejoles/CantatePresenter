import Foundation

// MARK: - Localization

/// Tłumaczenia interfejsu (S10).
///
/// Kluczem jest polski tekst źródłowy. Kolejność wyszukiwania: własne tłumaczenie zaimportowane z JSON,
/// String Catalog (`Resources/Localizable.xcstrings`) dla wybranego języka, a na końcu sam polski tekst.
/// Język wybiera się w Ustawieniach, niezależnie od języka systemu.
public enum Localization {
    public static let sourceLanguage = "pl"
    static let bundleName = "CantatePresenter_CantatePresenterCore"
    
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _currentLanguage = sourceLanguage
    nonisolated(unsafe) private static var overlays: [String: [String: String]] = [:]
    nonisolated(unsafe) private static var languageBundles: [String: Bundle] = [:]
    
    /// Język do tekstów tworzonych poza widokami (komunikaty usług); ustawiany przez `DataStore`.
    public static var currentLanguage: String {
        get { lock.withLock { _currentLanguage } }
        set { lock.withLock { _currentLanguage = newValue } }
    }
    
    public static func setOverlay(_ strings: [String: String], for language: String) {
        lock.withLock { overlays[language] = strings.isEmpty ? nil : strings }
    }
    
    // MARK: - Resource Bundle
    
    private final class BundleFinder {}
    
    /// Paczka zasobów pakietu. W przeciwieństwie do `Bundle.module` brak paczki nie zatrzymuje aplikacji:
    /// interfejs zostaje wtedy po polsku.
    public static let resourceBundle: Bundle? = {
        let ownBundle = Bundle(for: BundleFinder.self)
        var candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            ownBundle.resourceURL,
            ownBundle.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent()
        ]
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.insert(URL(fileURLWithPath: override), at: 0)
        }
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName + ".bundle"), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }()
    
    private static func bundle(for language: String) -> Bundle? {
        if let cached = lock.withLock({ languageBundles[language] }) {
            return cached
        }
        guard let url = resourceBundle?.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            return nil
        }
        lock.withLock { languageBundles[language] = bundle }
        return bundle
    }
    
    // MARK: - Lookup
    
    public static func string(_ key: String, language: String) -> String {
        if let custom = lock.withLock({ overlays[language]?[key] }),
           !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }
        if language != sourceLanguage, let bundle = bundle(for: language) {
            let translated = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if !translated.isEmpty {
                return translated
            }
        } else if language != sourceLanguage, let translated = rawCatalog[language]?[key], !translated.isEmpty {
            return translated
        }
        return key
    }
    
    /// Zastępuje `{0}`, `{1}`… kolejnymi wartościami. Tłumacz może przestawić znaczniki.
    public static func format(_ template: String, _ args: [Any]) -> String {
        guard !args.isEmpty else { return template }
        var result = template
        for (index, value) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: "\(value)")
        }
        return result
    }
    
    /// Wszystkie klucze katalogu (polskie teksty źródłowe), np. do szablonu tłumaczenia.
    public static func catalogKeys(referenceLanguage: String = "en") -> [String: String] {
        guard let url = resourceBundle?.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: referenceLanguage),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return rawCatalog[referenceLanguage] ?? [:]
        }
        return dictionary
    }
    
    /// Starsze SwiftPM (np. Xcode 26) kopiują `Localizable.xcstrings` bez kompilacji do `.lproj`;
    /// wtedy tłumaczenia czytane są wprost z katalogu (JSON), żeby interfejs nie został po polsku.
    static let rawCatalog: [String: [String: String]] = {
        guard let url = resourceBundle?.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return [:]
        }
        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            guard let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] else { continue }
            for (language, value) in localizations {
                if let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                    result[language, default: [:]][key] = text
                }
            }
        }
        return result
    }()
}

// MARK: - L()

/// Tekst interfejsu w języku wybranym w Ustawieniach. Wywołane w `body` widoku rejestruje zależność
/// od ustawień (`@Observable`), więc zmiana języka odświeża widok.
@MainActor
public func L(_ key: String, _ args: Any...) -> String {
    Localization.format(Localization.string(key, language: DataStore.shared.settings.appLanguage), args)
}

/// Wersja dla kodu poza głównym aktorem (komunikaty błędów usług).
public func Lnow(_ key: String, _ args: Any...) -> String {
    Localization.format(Localization.string(key, language: Localization.currentLanguage), args)
}

// MARK: - Slide Labels

extension SongSlide {
    /// Etykieta do wyświetlenia: domyślne etykiety („Zwrotka 2”, „Refren”) w wybranym języku,
    /// własne etykiety (np. „Wstęp”) bez zmian.
    @MainActor
    public var displayLabel: String {
        let base = type.polishName
        if label == base {
            return L(base)
        }
        if let number, label == "\(base) \(number)" {
            return "\(L(base)) \(number)"
        }
        return label
    }
}

extension Notification.Name {
    /// Zmiana języka interfejsu w Ustawieniach; AppKit (menu, tytuły okien) przebudowuje się po niej.
    public static let appLanguageDidChange = Notification.Name("AppLanguageDidChange")
}
