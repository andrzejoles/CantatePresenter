import Foundation
import AppKit
import UniformTypeIdentifiers
import os

public struct BackupManifest: Codable, Sendable {
    public let version: String
    public let appName: String
    public let createdAt: Date
    public let deviceName: String
    public let songsCount: Int
    public let plansCount: Int
    public let activeLogoId: String
    public let appLanguage: String
    public let includedFiles: [String]
    public let comment: String?
    /// Wersja formatu danych w kopii (`DataSchema`); starsze kopie nie mają pola.
    public var schemaVersion: Int? = DataSchema.current

    public init(
        version: String = AppVersion.current,
        appName: String = "CantatePresenter",
        createdAt: Date = Date(),
        deviceName: String = Host.current().localizedName ?? "Mac",
        songsCount: Int,
        plansCount: Int,
        activeLogoId: String,
        appLanguage: String,
        includedFiles: [String],
        comment: String? = nil
    ) {
        self.version = version
        self.appName = appName
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.songsCount = songsCount
        self.plansCount = plansCount
        self.activeLogoId = activeLogoId
        self.appLanguage = appLanguage
        self.includedFiles = includedFiles
        self.comment = comment
    }
}

@MainActor
public final class BackupService {
    public static let shared = BackupService()

    /// Wynik okna przywracania (R2-12): anulowanie rozpoznawane bez porównywania tłumaczonego tekstu.
    public enum RestoreOutcome: Equatable, Sendable {
        case cancelled
        case restored(message: String)
        case failed(message: String)

        public var isSuccess: Bool {
            if case .restored = self { return true }
            return false
        }

        /// Tekst dla użytkownika; `nil` przy anulowaniu.
        public var message: String? {
            switch self {
            case .cancelled: return nil
            case .restored(let message), .failed(let message): return message
            }
        }
    }

    /// Pliki danych w kopii. Katalogi `logos/` i `templates/` nie są już tworzone ani czytane
    /// (logo są wbudowane, R2-15); przywracanie pomija je także w starych kopiach (R11-03).
    nonisolated static let archivedFiles = [
        "songs.json",
        "plans.json",
        "settings.json",
        "standby.html",
        "custom_languages.json",
        "ccli_usage.json"
    ]
    /// Prefiks katalogów tymczasowych z gotowym archiwum; każde wywołanie ma własny (R2-13).
    nonisolated static let archiveDirectoryPrefix = "CantateBackupArchive_"

    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "backup")

    private init() {}

    private var dataDirectory: URL {
        AppPaths.shared.dataDirectory
    }

    // MARK: - Create Full Backup Package

    /// Tworzy archiwum `.cantatebackup` (pieśni z chwytami, plany, ustawienia, własne języki, raport CCLI).
    /// Kopiowanie i kompresja `ditto` idą poza wątkiem głównym (R2-13). Archiwum leży we własnym
    /// katalogu tymczasowym; po użyciu usuń je przez `removeTemporaryArchive(_:)`.
    public func createBackupArchive(comment: String? = nil) async throws -> (archiveURL: URL, manifest: BackupManifest) {
        try await Self.createBackupArchive(of: DataStore.shared, in: dataDirectory, comment: comment)
    }

    /// Ustawienia z arkusza są tylko w pamięci, dopóki arkusz jest otwarty; przyciski kopii leżą w tym samym
    /// arkuszu, więc przed kopiowaniem plików zmienione ustawienia są zapisywane (R6-03).
    static func createBackupArchive(
        of store: DataStore,
        in dataDirectory: URL,
        comment: String?,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> (archiveURL: URL, manifest: BackupManifest) {
        store.saveSettingsIfChanged()
        return try await makeArchive(
            of: dataDirectory,
            songsCount: store.songs.count,
            plansCount: store.plans.count,
            activeLogoId: store.settings.activeLogoId,
            appLanguage: store.settings.appLanguage,
            comment: comment,
            temporaryDirectory: temporaryDirectory
        )
    }

    nonisolated static func makeArchive(
        of dataDirectory: URL,
        songsCount: Int,
        plansCount: Int,
        activeLogoId: String,
        appLanguage: String,
        comment: String?,
        date: Date = Date(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> (archiveURL: URL, manifest: BackupManifest) {
        let fileManager = FileManager.default
        let staging = temporaryDirectory.appendingPathComponent("CantateBackupStaging_\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: staging)
        }

        var includedFiles: [String] = []
        for fileName in archivedFiles {
            let source = dataDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: staging.appendingPathComponent(fileName))
                includedFiles.append(fileName)
            }
        }

        let manifest = BackupManifest(
            createdAt: date,
            songsCount: songsCount,
            plansCount: plansCount,
            activeLogoId: activeLogoId,
            appLanguage: appLanguage,
            includedFiles: includedFiles,
            comment: comment
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))

        // Nazwę z datą widać w oknie zapisu i na Dysku; unikalność daje osobny katalog.
        let archiveDirectory = temporaryDirectory.appendingPathComponent(archiveDirectoryPrefix + UUID().uuidString)
        try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let archiveURL = archiveDirectory.appendingPathComponent(archiveFileName(for: date))

        let status: Int32
        do {
            status = try await runDitto(["-c", "-k", "--sequesterRsrc", staging.path, archiveURL.path])
        } catch {
            removeTemporaryArchive(archiveURL)
            throw error
        }
        guard status == 0, fileManager.fileExists(atPath: archiveURL.path) else {
            removeTemporaryArchive(archiveURL)
            throw NSError(domain: "CantateBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: Lnow("Nie udało się skompresować archiwum kopii zapasowej (kod ditto: {0})", status)])
        }
        return (archiveURL, manifest)
    }

    /// Nazwa pliku kopii: stały format niezależny od ustawień regionu (R2-19).
    nonisolated static func archiveFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "CantatePresenter_Backup_\(formatter.string(from: date)).cantatebackup"
    }

    /// Usuwa archiwum z `createBackupArchive` razem z jego katalogiem tymczasowym.
    nonisolated public static func removeTemporaryArchive(_ archiveURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: archiveURL)
        let directory = archiveURL.deletingLastPathComponent()
        if directory.lastPathComponent.hasPrefix(archiveDirectoryPrefix),
           (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty ?? false {
            try? fileManager.removeItem(at: directory)
        }
    }

    /// `ditto` z `terminationHandler`, bez `waitUntilExit` (zagnieżdżona pętla zdarzeń na wątku głównym).
    nonisolated private static func runDitto(_ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = arguments
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Restore Backup Package

    /// Restores app data from a `.cantatebackup`, `.holyricsbackup` or `.zip` archive (S5: see `BackupRestorer`).
    /// The archive is unpacked off the main thread, validated, and swapped in as a whole; the previous data
    /// directory is kept so the restore can be undone.
    public func restoreBackup(from archiveURL: URL) async throws -> BackupManifest {
        let manifest = try await Self.restoreBackup(from: archiveURL, into: DataStore.shared, dataDirectory: dataDirectory)
        LocalizationService.shared.loadCustomLanguages()
        return manifest
    }

    /// Przywracanie dla wskazanego magazynu i katalogu. Ustawienia zmienione w otwartym arkuszu Ustawień
    /// (skąd zwykle przywracamy) są najpierw zapisywane, żeby trafiły do zachowanego stanu
    /// „przed przywróceniem”, do którego wraca „Cofnij ostatnie przywracanie” (R10-03, jak R6-03).
    static func restoreBackup(from archiveURL: URL, into store: DataStore, dataDirectory: URL) async throws -> BackupManifest {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw NSError(domain: "CantateBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: Lnow("Wskazany plik kopii zapasowej nie istnieje: {0}", archiveURL.lastPathComponent)])
        }

        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("CantateRestore_\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: extractDir)
        }
        try await BackupRestorer.unzip(archiveURL, to: extractDir)

        let contentRoot = BackupRestorer.contentRoot(in: extractDir)
        var manifest: BackupManifest? = nil
        if let data = try? Data(contentsOf: contentRoot.appendingPathComponent("manifest.json")) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(BackupManifest.self, from: data)
        }

        // Folder danych spakowany w Finderze nie ma manifestu: datą kopii jest stan plików, nie chwila przywracania (R6-13).
        let fallbackDate = Self.dataDate(in: contentRoot) ?? Date()
        store.saveSettingsIfChanged()
        let result = try BackupRestorer(dataDirectory: dataDirectory).restore(fromExtracted: contentRoot)
        reload(store)

        return manifest ?? BackupManifest(
            createdAt: fallbackDate,
            songsCount: result.songsCount,
            plansCount: result.plansCount,
            activeLogoId: "unknown",
            appLanguage: "pl",
            includedFiles: BackupRestorer.allowedItems
        )
    }

    /// Najnowsza data zmiany plików danych w katalogu (`unzip` i `ditto` zachowują daty z archiwum); `nil` bez plików.
    nonisolated static func dataDate(in directory: URL) -> Date? {
        archivedFiles
            .compactMap { try? directory.appendingPathComponent($0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    public var canUndoRestore: Bool {
        BackupRestorer(dataDirectory: dataDirectory).canUndo
    }

    /// Stan, do którego wróci `undoLastRestore` (do potwierdzenia z datą, R2-01).
    public var latestPreviousState: BackupRestorer.PreviousState? {
        BackupRestorer(dataDirectory: dataDirectory).previousStateDetails().first
    }

    /// Wraca do najnowszego zachowanego stanu; obecne dane zostają obok (R2-01).
    /// - Returns: folder z danymi sprzed cofnięcia.
    @discardableResult
    public func undoLastRestore() throws -> URL {
        let kept = try Self.undoLastRestore(of: DataStore.shared, dataDirectory: dataDirectory)
        LocalizationService.shared.loadCustomLanguages()
        return kept
    }

    /// Jak przy przywracaniu: niezapisane ustawienia trafiają do danych zachowanych przy cofnięciu (R10-03).
    static func undoLastRestore(of store: DataStore, dataDirectory: URL) throws -> URL {
        store.saveSettingsIfChanged()
        let kept = try BackupRestorer(dataDirectory: dataDirectory).undoLastRestore()
        reload(store)
        return kept
    }

    private static func reload(_ store: DataStore) {
        store.reloadAll()
        store.updateActiveLogo(id: store.settings.activeLogoId)
    }

    // MARK: - Save Dialog Helper

    /// Najpierw miejsce zapisu, potem archiwum (R4-08): anulowanie niczego nie kompresuje.
    public func exportBackupWithSavePanel() async -> Bool {
        let savePanel = NSSavePanel()
        savePanel.title = Lnow("Zapisz pełną kopię zapasową CantatePresenter")
        savePanel.message = Lnow("Wybierz miejsce zapisu pliku kopii zapasowej (.cantatebackup)")
        savePanel.prompt = Lnow("Utwórz kopię")
        savePanel.nameFieldStringValue = Self.archiveFileName(for: Date())
        savePanel.allowedContentTypes = [
            UTType(filenameExtension: "cantatebackup") ?? .data,
            UTType(filenameExtension: "holyricsbackup") ?? .data,
            UTType.zip
        ]
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return false }

        do {
            let (tempArchiveURL, _) = try await createBackupArchive()
            defer { Self.removeTemporaryArchive(tempArchiveURL) }
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: tempArchiveURL, to: destinationURL)
            return true
        } catch {
            Self.logger.error("Nie można zapisać kopii zapasowej: \(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = Lnow("Błąd tworzenia kopii zapasowej")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    // MARK: - Open Dialog Helper

    public func restoreBackupWithOpenPanel() async -> RestoreOutcome {
        let openPanel = NSOpenPanel()
        openPanel.title = Lnow("Wybierz plik kopii zapasowej do przywrócenia")
        openPanel.message = Lnow("Wskaż plik .cantatebackup, .holyricsbackup lub .zip zawierający kopię bazy CantatePresenter")
        openPanel.prompt = Lnow("Przywróć dane")
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "cantatebackup") ?? .data,
            UTType(filenameExtension: "holyricsbackup") ?? .data,
            UTType.zip
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        let selectedURL = openPanel.runModal() == .OK ? openPanel.url : nil
        return await restoreOutcome(from: selectedURL)
    }

    /// `nil` = anulowany wybór pliku.
    func restoreOutcome(from selectedURL: URL?) async -> RestoreOutcome {
        guard let selectedURL else { return .cancelled }
        do {
            let manifest = try await restoreBackup(from: selectedURL)
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: manifest.createdAt)
            return .restored(message: Lnow("Pomyślnie przywrócono stan aplikacji z kopii z dnia {0} (pieśni: {1}, plany: {2}). Poprzednie dane zachowano: Plik → Cofnij ostatnie przywracanie.", dateStr, manifest.songsCount, manifest.plansCount))
        } catch {
            Self.logger.error("Przywracanie kopii nie powiodło się: \(String(describing: error), privacy: .public)")
            return .failed(message: Lnow("Błąd przywracania: {0}", error.localizedDescription))
        }
    }
}
