import Foundation
import os

// MARK: - Backup Restorer

/// Przywracanie kopii zapasowej z walidacją i możliwością wycofania (S5).
///
/// 1. Do katalogu danych trafiają tylko znane pliki z kopii (`allowedItems`).
/// 2. `songs.json` musi istnieć i się dekodować; `plans.json` i `settings.json`, jeśli są, też.
/// 3. Nowy katalog danych powstaje obok obecnego (kopia obecnego + pliki z kopii zapasowej),
///    a potem zastępuje go jedną operacją. Błąd w trakcie nie zostawia mieszanki plików.
/// 4. Poprzedni katalog zostaje obok jako „przed przywróceniem” (najwyżej `previousStatesLimit`).
public struct BackupRestorer {
    public struct Result {
        public let songsCount: Int
        public let plansCount: Int
        public let previousState: URL
    }

    public enum RestoreError: LocalizedError {
        case missingSongs
        case invalidFile(String, Error)
        case unzipFailed(Int32)
        case nothingToUndo

        public var errorDescription: String? {
            switch self {
            case .missingSongs:
                return Lnow("Kopia zapasowa nie zawiera pliku songs.json.")
            case .invalidFile(let name, let error):
                return Lnow("Plik {0} w kopii zapasowej jest uszkodzony: {1}", name, error.localizedDescription)
            case .unzipFailed(let status):
                return Lnow("Błąd rozpakowywania archiwum kopii zapasowej (kod ditto: {0}).", status)
            case .nothingToUndo:
                return Lnow("Brak poprzedniego stanu do przywrócenia.")
            }
        }
    }

    public static let allowedItems = [
        "songs.json", "plans.json", "settings.json", "custom_languages.json", "standby.html", "logos", "templates",
        "ccli_usage.json"
    ]
    public static let previousStatesLimit = 3
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "backup")

    public let dataDirectory: URL
    private let fileManager: FileManager

    public init(dataDirectory: URL, fileManager: FileManager = .default) {
        self.dataDirectory = dataDirectory
        self.fileManager = fileManager
    }

    private var parentDirectory: URL { dataDirectory.deletingLastPathComponent() }
    private var previousStatePrefix: String { "\(dataDirectory.lastPathComponent) przed przywróceniem " }

    // MARK: - Unzip

    /// Rozpakowuje archiwum przez `ditto` bez blokowania wątku głównego.
    public static func unzip(_ archive: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, directory.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw RestoreError.unzipFailed(status) }
    }

    // MARK: - Restore

    public func restore(fromExtracted contentRoot: URL) throws -> Result {
        let (songsCount, plansCount) = try validate(contentRoot)

        let staging = parentDirectory.appendingPathComponent(".\(dataDirectory.lastPathComponent)-przywracanie-\(UUID().uuidString)")
        do {
            // Obecne dane (np. history/, backups/) zostają, podmieniane są tylko pliki z kopii.
            if fileManager.fileExists(atPath: dataDirectory.path) {
                try fileManager.copyItem(at: dataDirectory, to: staging)
            } else {
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            }
            for item in Self.allowedItems where fileManager.fileExists(atPath: contentRoot.appendingPathComponent(item).path) {
                let target = staging.appendingPathComponent(item)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: contentRoot.appendingPathComponent(item), to: target)
            }

            let previousName = previousStatePrefix + Self.timestamp()
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            _ = try fileManager.replaceItemAt(
                dataDirectory,
                withItemAt: staging,
                backupItemName: previousName,
                options: .withoutDeletingBackupItem
            )
            pruneOldStates()
            Self.logger.notice("Przywrócono kopię; poprzedni stan: \(previousName, privacy: .public)")
            return Result(songsCount: songsCount, plansCount: plansCount, previousState: parentDirectory.appendingPathComponent(previousName))
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func validate(_ contentRoot: URL) throws -> (songs: Int, plans: Int) {
        let decoder = JSONFileStore.makeDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
            let url = contentRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            do {
                return try decoder.decode(type, from: Data(contentsOf: url))
            } catch {
                throw RestoreError.invalidFile(name, error)
            }
        }
        guard let songs = try decode([Song].self, "songs.json") else {
            throw RestoreError.missingSongs
        }
        let plans = try decode([ServicePlan].self, "plans.json")
        _ = try decode(AppSettings.self, "settings.json")
        return (songs.count, plans?.count ?? 0)
    }

    // MARK: - Undo

    /// Poprzednie stany, od najnowszego.
    public func previousStates() -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: parentDirectory.path)) ?? []
        return names
            .filter { $0.hasPrefix(previousStatePrefix) }
            .sorted(by: >)
            .map { parentDirectory.appendingPathComponent($0) }
    }

    public var canUndo: Bool { !previousStates().isEmpty }

    /// Wraca do stanu sprzed ostatniego przywracania; przywrócone dane są usuwane.
    public func undoLastRestore() throws {
        guard let previous = previousStates().first else { throw RestoreError.nothingToUndo }
        _ = try fileManager.replaceItemAt(dataDirectory, withItemAt: previous)
        Self.logger.notice("Cofnięto przywracanie do \(previous.lastPathComponent, privacy: .public)")
    }

    private func pruneOldStates() {
        for state in previousStates().dropFirst(Self.previousStatesLimit) {
            try? fileManager.removeItem(at: state)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Milisekundy: kilka przywróceń w tej samej sekundzie nie może mieć tej samej nazwy.
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss-SSS"
        return formatter.string(from: Date())
    }
}
