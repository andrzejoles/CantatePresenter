import Foundation
import os

// MARK: - App Paths

/// Jedyne miejsce, które wyznacza katalog danych aplikacji (K2).
///
/// Dane leżą w `~/Library/Application Support/CantatePresenter`. Przy pierwszym uruchomieniu
/// nowej wersji dane ze starej lokalizacji (`data/` obok pakietu .app albo w bieżącym katalogu
/// przy `swift run`) są tam kopiowane; stary katalog zostaje nietknięty jako kopia.
/// Zmienna środowiskowa `CANTATE_DATA_DIR` wskazuje inny katalog (testy, praca na kopii danych).
public struct AppPaths: Equatable {
    public enum Migration: Equatable {
        case notNeeded
        case migrated(from: URL)
        /// Kopiowanie się nie udało; `dataDirectory` wskazuje wtedy stary katalog.
        case failed(from: URL, error: String)
    }

    public static let environmentKey = "CANTATE_DATA_DIR"
    public static let applicationFolderName = "CantatePresenter"

    /// Pliki i katalogi przenoszone ze starej lokalizacji. Bez `holyrics_samples/` (próbki testowe w repozytorium).
    static let migratedItems = [
        "songs.json", "plans.json", "settings.json", "custom_languages.json",
        "standby.html", "logos", "templates", JSONFileStore.historyDirectoryName
    ]
    /// Obecność któregokolwiek z tych plików oznacza, że nowa lokalizacja jest już w użyciu.
    static let dataFiles = ["songs.json", "plans.json", "settings.json"]

    public let dataDirectory: URL
    public let migration: Migration

    public init(dataDirectory: URL, migration: Migration = .notNeeded) {
        self.dataDirectory = dataDirectory
        self.migration = migration
    }

    public var songsFile: URL { dataDirectory.appendingPathComponent("songs.json") }
    public var plansFile: URL { dataDirectory.appendingPathComponent("plans.json") }
    public var settingsFile: URL { dataDirectory.appendingPathComponent("settings.json") }
    public var customLanguagesFile: URL { dataDirectory.appendingPathComponent("custom_languages.json") }
    public var standbyFile: URL { dataDirectory.appendingPathComponent("standby.html") }

    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "persistence")

    // MARK: - Shared

    public static let shared: AppPaths = {
        let fileManager = FileManager.default
        return resolve(
            environment: ProcessInfo.processInfo.environment,
            bundleURL: Bundle.main.bundleURL,
            currentDirectory: URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            applicationSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            fileManager: fileManager
        )
    }()

    // MARK: - Resolution

    static func resolve(
        environment: [String: String],
        bundleURL: URL,
        currentDirectory: URL,
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> AppPaths {
        if let override = environment[environmentKey], !override.isEmpty {
            let directory = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            createDirectory(directory, fileManager: fileManager)
            return AppPaths(dataDirectory: directory)
        }

        let target = applicationSupport.appendingPathComponent(applicationFolderName, isDirectory: true)
        let legacy = legacyDataDirectory(bundleURL: bundleURL, currentDirectory: currentDirectory)

        guard !containsData(target, fileManager: fileManager), containsData(legacy, fileManager: fileManager) else {
            createDirectory(target, fileManager: fileManager)
            return AppPaths(dataDirectory: target)
        }

        do {
            try migrateLegacyData(from: legacy, to: target, fileManager: fileManager)
            logger.notice("Przeniesiono dane z \(legacy.path, privacy: .public) do \(target.path, privacy: .public)")
            return AppPaths(dataDirectory: target, migration: .migrated(from: legacy))
        } catch {
            // Start z pustą biblioteką zablokowałby migrację przy kolejnym uruchomieniu, więc zostajemy przy starym katalogu.
            logger.error("Migracja danych z \(legacy.path, privacy: .public) nie powiodła się: \(String(describing: error), privacy: .public)")
            return AppPaths(dataDirectory: legacy, migration: .failed(from: legacy, error: error.localizedDescription))
        }
    }

    /// Stara lokalizacja: `data/` obok pakietu .app, a bez pakietu (`swift run`) w bieżącym katalogu.
    static func legacyDataDirectory(bundleURL: URL, currentDirectory: URL) -> URL {
        let projectFolder = bundleURL.pathExtension == "app" ? bundleURL.deletingLastPathComponent() : currentDirectory
        return projectFolder.appendingPathComponent("data", isDirectory: true)
    }

    // MARK: - Migration

    /// Kopiuje dane do katalogu tymczasowego obok celu, a dopiero potem przenosi je na miejsce,
    /// żeby przerwana migracja nie zostawiła niepełnych danych uznanych za gotowe.
    static func migrateLegacyData(from legacy: URL, to target: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let staging = target.appendingPathComponent(".migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let items = migratedItems.filter { fileManager.fileExists(atPath: legacy.appendingPathComponent($0).path) }
        for item in items {
            try fileManager.copyItem(at: legacy.appendingPathComponent(item), to: staging.appendingPathComponent(item))
        }
        // Pliki danych na końcu: dopiero ich obecność oznacza zakończoną migrację.
        let ordered = items.filter { !dataFiles.contains($0) } + items.filter { dataFiles.contains($0) }
        for item in ordered {
            // Pozostałość po przerwanej wcześniejszej migracji (pliki danych nigdy tu nie trafiają, patrz `containsData`).
            if fileManager.fileExists(atPath: target.appendingPathComponent(item).path) {
                try fileManager.removeItem(at: target.appendingPathComponent(item))
            }
            try fileManager.moveItem(at: staging.appendingPathComponent(item), to: target.appendingPathComponent(item))
        }
    }

    private static func containsData(_ directory: URL, fileManager: FileManager) -> Bool {
        dataFiles.contains { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private static func createDirectory(_ directory: URL, fileManager: FileManager) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Nie można utworzyć katalogu danych \(directory.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - User Guide File

extension AppPaths {
    /// `INSTRUKCJA.md` dołączona do aplikacji przez `build_app.sh` (S11); przy `swift run` plik z bieżącego katalogu.
    public static var userGuideFile: URL? {
        if let bundled = Bundle.main.url(forResource: "INSTRUKCJA", withExtension: "md") {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("INSTRUKCJA.md")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}
