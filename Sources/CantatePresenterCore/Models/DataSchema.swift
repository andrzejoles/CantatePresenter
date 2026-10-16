import Foundation

// MARK: - Data Schema

/// Wersja formatu katalogu danych: pole `schemaVersion` w `settings.json` (i w `manifest.json` kopii zapasowej).
///
/// `songs.json`, `plans.json` i pozostałe pliki zostają w dotychczasowym kształcie (tablice JSON), więc są zgodne
/// z wersją webową, kopiami i starszymi wersjami aplikacji. Wersja opisuje cały katalog naraz:
/// - brak pola (pliki sprzed jego wprowadzenia) to wersja 0, ten sam format co 1;
/// - starsza wersja: `migrate` przeprowadza kolejne kroki, a zapis ustawień podbija numer;
/// - nowsza niż `current`: dane z nowszej aplikacji; ta wersja tylko je czyta i niczego nie zapisuje,
///   żeby nie zgubić pól, których nie zna.
public enum DataSchema {
    public static let current = 1
    
    /// Wersja zapisana w `settings.json`; `nil`, gdy pliku nie ma albo nie jest obiektem JSON.
    public static func version(ofSettingsAt url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return version(in: object)
    }
    
    /// Wersja z obiektu JSON (ustawienia albo manifest kopii); brak pola to 0.
    public static func version(in object: [String: Any]) -> Int {
        (object["schemaVersion"] as? NSNumber)?.intValue ?? 0
    }
    
    /// Kroki migracji od `version` do `current`. Zwraca opisy wykonanych kroków (do dziennika).
    /// 0 → 1: format bez zmian, tylko numer w `settings.json` (zapisywany przez `DataStore`).
    @discardableResult
    public static func migrate(from version: Int, in directory: URL) throws -> [String] {
        var steps: [String] = []
        var version = version
        while version < current {
            switch version {
            case 0:
                steps.append("0→1: schemaVersion w settings.json")
            default:
                break
            }
            version += 1
        }
        return steps
    }
}
