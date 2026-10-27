import Foundation
import os

// MARK: - Exit Backup Coordinator

/// Kopia zapasowa przy zamykaniu aplikacji (W2).
///
/// Działa na głównym aktorze bez blokowania wątku głównego: `AppDelegate` zwraca `.terminateLater`,
/// czeka na `run` i dopiero wtedy kończy aplikację. Pierwsze z trzech zdarzeń kończy czekanie:
/// zakończona praca, limit czasu albo „Pomiń”.
@MainActor
public final class ExitBackupCoordinator {
    public enum Outcome: Equatable, Sendable {
        case uploaded
        /// Wysyłka się nie udała; archiwum zostało zachowane w tym miejscu.
        case keptLocally(URL)
        case timedOut
        case skipped
        case failed(String)
    }

    public struct Operations {
        public var createArchive: @MainActor () async throws -> URL
        public var upload: @MainActor (URL) async throws -> Void
        public var keepLocally: @MainActor (URL) throws -> URL

        public init(
            createArchive: @escaping @MainActor () async throws -> URL,
            upload: @escaping @MainActor (URL) async throws -> Void,
            keepLocally: @escaping @MainActor (URL) throws -> URL
        ) {
            self.createArchive = createArchive
            self.upload = upload
            self.keepLocally = keepLocally
        }
    }

    public static let localBackupsDirectoryName = "backups"
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "backup")

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var workTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    // MARK: - Run

    public func run(operations: Operations, timeout: Duration) async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            workTask = Task { @MainActor in
                let outcome = await Self.perform(operations)
                self.finish(outcome)
            }
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled {
                    self.finish(.timedOut)
                }
            }
        }
    }

    public func skip() {
        finish(.skipped)
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        workTask?.cancel()
        timeoutTask?.cancel()
        Self.logger.notice("Kopia przy zamykaniu: \(String(describing: outcome), privacy: .public)")
        continuation.resume(returning: outcome)
    }

    private static func perform(_ operations: Operations) async -> Outcome {
        let archive: URL
        do {
            archive = try await operations.createArchive()
        } catch {
            logger.error("Nie można utworzyć archiwum kopii: \(String(describing: error), privacy: .public)")
            return .failed(error.localizedDescription)
        }
        do {
            try await operations.upload(archive)
            BackupService.removeTemporaryArchive(archive)
            return .uploaded
        } catch {
            logger.error("Wysyłka kopii nie powiodła się: \(String(describing: error), privacy: .public)")
            do {
                return .keptLocally(try operations.keepLocally(archive))
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Local Copies

    /// Przenosi archiwum do `directory` i zostawia `limit` najnowszych (bez `prune` nie usuwa żadnej).
    /// Kolejność według daty utworzenia, a przy równej według nazwy (nazwy mogły powstać w innym formacie, R2-19).
    public static func keepLocally(_ archive: URL, in directory: URL, limit: Int = 5, prune: Bool = true) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(archive.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: archive, to: destination)
        BackupService.removeTemporaryArchive(archive)
        guard prune else {
            logger.notice("Kopia przy zamykaniu z nieczytelnych danych: starsze kopie lokalne zostają")
            return destination
        }

        let existing = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { (url: $0, created: (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { ($0.created, $0.url.lastPathComponent) < ($1.created, $1.url.lastPathComponent) }
        for entry in existing.dropLast(limit) {
            do {
                try fileManager.removeItem(at: entry.url)
            } catch {
                logger.error("Nie można usunąć starej kopii \(entry.url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return destination
    }

    /// Przy nieczytelnym pliku danych albo danych z nowszej wersji kopia przy zamykaniu nie pokazuje
    /// prawdziwej biblioteki; kolejne zamknięcia nie mogą wtedy wyprzeć dobrych kopii lokalnych (R6-10).
    /// Decyduje stan magazynu, nie lista alertów: alert znika po kliknięciu OK, a plik zostaje zablokowany (R10-01).
    static func shouldPruneLocalCopies(store: DataStore) -> Bool {
        !store.hasUnreadableData
    }

    // MARK: - Live Operations

    public static func liveOperations(dataDirectory: URL = AppPaths.shared.dataDirectory) -> Operations {
        Operations(
            createArchive: {
                try await BackupService.shared.createBackupArchive(comment: "Automatyczny backup przy zamykaniu CantatePresenter").archiveURL
            },
            upload: { archive in
                _ = try await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archive)
            },
            keepLocally: { archive in
                try keepLocally(archive, in: dataDirectory.appendingPathComponent(localBackupsDirectoryName),
                                prune: shouldPruneLocalCopies(store: DataStore.shared))
            }
        )
    }
}
