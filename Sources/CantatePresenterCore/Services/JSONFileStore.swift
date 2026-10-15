import Foundation
import os

// MARK: - Load Result

public enum JSONFileLoadResult<Value> {
    /// Plik nie istnieje (pierwsze uruchomienie).
    case missing
    case loaded(Value)
    /// Plik istnieje, ale nie da się go odczytać ani zdekodować. Jego kopia leży w `quarantinedCopy`.
    case unreadable(error: Error, quarantinedCopy: URL?)
}

// MARK: - JSON File Store

/// Odczyt i zapis plików danych JSON bez ryzyka utraty danych (K1):
/// odróżnia brak pliku od pliku nieczytelnego, kopiuje nieczytelne pliki do kwarantanny
/// i przed każdym zapisem odkłada poprzednią wersję do `history/`.
public struct JSONFileStore {
    public static let historyDirectoryName = "history"

    public var historyLimit: Int
    private let fileManager: FileManager
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "persistence")

    public init(historyLimit: Int = 5, fileManager: FileManager = .default) {
        self.historyLimit = historyLimit
        self.fileManager = fileManager
    }

    // MARK: - Decoder

    /// Dekoder akceptujący daty zarówno jako ISO 8601 (tak zapisuje `DataStore.saveSongs`),
    /// jak i jako liczby (domyślny format `Codable`, używany w `settings.json`).
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nieobsługiwany format daty: \(string)")
        }
        return decoder
    }

    // MARK: - Load

    public func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> JSONFileLoadResult<Value> {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try Self.makeDecoder().decode(type, from: data))
        } catch {
            Self.logger.error("Nie można odczytać \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return .unreadable(error: error, quarantinedCopy: quarantine(url))
        }
    }

    /// Kopiuje nieczytelny plik obok oryginału jako `<nazwa>.corrupt-<data>.json`. Oryginał zostaje na miejscu.
    private func quarantine(_ url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let baseName = url.deletingPathExtension().lastPathComponent
        let stamp = formatter.string(from: Date())

        var candidate = url.deletingLastPathComponent().appendingPathComponent("\(baseName).corrupt-\(stamp).json")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(baseName).corrupt-\(stamp)-\(counter).json")
            counter += 1
        }
        do {
            try fileManager.copyItem(at: url, to: candidate)
            Self.logger.notice("Kopia nieczytelnego pliku: \(candidate.path, privacy: .public)")
            return candidate
        } catch {
            Self.logger.error("Nie można skopiować \(url.lastPathComponent, privacy: .public) do kwarantanny: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Save

    /// Koduje wartość, odkłada poprzednią wersję pliku do `history/` i zapisuje atomowo.
    public func save<Value: Encodable>(_ value: Value, to url: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try rotateHistory(of: url)
            } catch {
                // Brak kopii nie może blokować zapisu bieżących danych.
                Self.logger.error("Nie można utworzyć kopii \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        try data.write(to: url, options: .atomic)
    }

    /// `history/songs.1.json` to wersja sprzed ostatniego zapisu, `songs.<historyLimit>.json` najstarsza.
    private func rotateHistory(of url: URL) throws {
        guard historyLimit > 0 else { return }
        let historyDirectory = url.deletingLastPathComponent().appendingPathComponent(Self.historyDirectoryName)
        try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        let baseName = url.deletingPathExtension().lastPathComponent
        func versionURL(_ index: Int) -> URL {
            historyDirectory.appendingPathComponent("\(baseName).\(index).json")
        }

        let oldest = versionURL(historyLimit)
        if fileManager.fileExists(atPath: oldest.path) {
            try fileManager.removeItem(at: oldest)
        }
        for index in stride(from: historyLimit - 1, through: 1, by: -1) where fileManager.fileExists(atPath: versionURL(index).path) {
            try fileManager.moveItem(at: versionURL(index), to: versionURL(index + 1))
        }
        try fileManager.copyItem(at: url, to: versionURL(1))
    }
}
