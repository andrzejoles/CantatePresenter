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
/// 5. Cofnięcie też niczego nie usuwa: obecny katalog zostaje obok jako „przed cofnięciem” (R2-01).
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
        case newerSchema(Int)
        case unsafeItem(String)
        case archiveTooLarge(Int64)

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
            case .newerSchema(let version):
                return Lnow("Kopię zapisała nowsza wersja CantatePresenter (format danych {0}, ta wersja obsługuje {1}). Zaktualizuj aplikację przed przywróceniem.", version, DataSchema.current)
            case .unsafeItem(let name):
                return Lnow("Kopia zapasowa zawiera niedozwolony element {0} (dowiązanie symboliczne lub plik specjalny).", name)
            case .archiveTooLarge(let size):
                return Lnow("Archiwum po rozpakowaniu zajęłoby {0}; to nie jest kopia CantatePresenter.", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
        }
    }

    /// `logos/` i `templates/` tylko ze starych kopii: aplikacja ich już nie tworzy ani nie czyta (R2-15).
    public static let allowedItems = [
        "songs.json", "plans.json", "settings.json", "custom_languages.json", "standby.html", "logos", "templates",
        "ccli_usage.json"
    ]

    /// Katalog z danymi w rozpakowanym archiwum: korzeń albo jedyny (lub pierwszy pasujący) podfolder
    /// z `manifest.json` lub `songs.json`, np. folder danych spakowany w Finderze (R2-14).
    public static func contentRoot(in extracted: URL, fileManager: FileManager = .default) -> URL {
        func hasData(_ directory: URL) -> Bool {
            ["manifest.json", "songs.json"].contains { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
        }
        if hasData(extracted) { return extracted }
        let subfolders = ((try? fileManager.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return subfolders.first(where: hasData) ?? extracted
    }
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
    /// Archiwum, które po rozpakowaniu zajęłoby ponad `ZipArchive.maxUncompressedSize`, jest odrzucane (R2-14).
    public static func unzip(_ archive: URL, to directory: URL) async throws {
        if let size = ZipArchive.declaredUncompressedSize(of: archive), size > ZipArchive.maxUncompressedSize {
            throw RestoreError.archiveTooLarge(size)
        }
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

    /// Do danych trafiają tylko zwykłe pliki i katalogi: dowiązanie (np. `standby.html` → plik spoza kopii)
    /// albo plik specjalny odrzuca całą kopię (R2-14).
    private func rejectUnsafeItems(in contentRoot: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        func check(_ values: URLResourceValues, name: String) throws {
            if values.isSymbolicLink == true || (values.isRegularFile != true && values.isDirectory != true) {
                throw RestoreError.unsafeItem(name)
            }
        }
        for item in Self.allowedItems {
            // Wartości samego elementu (bez podążania za dowiązaniem); brak elementu = pomijamy.
            guard let values = try? contentRoot.appendingPathComponent(item).resourceValues(forKeys: keys) else { continue }
            try check(values, name: item)
            guard values.isDirectory == true else { continue }
            let enumerator = fileManager.enumerator(at: contentRoot.appendingPathComponent(item), includingPropertiesForKeys: Array(keys))
            while let child = enumerator?.nextObject() as? URL {
                try check(try child.resourceValues(forKeys: keys), name: item + "/" + child.lastPathComponent)
            }
        }
    }

    private func validate(_ contentRoot: URL) throws -> (songs: Int, plans: Int) {
        try rejectUnsafeItems(in: contentRoot)
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
        // Kopia z nowszej aplikacji: pola, których ta wersja nie zna, zginęłyby przy pierwszym zapisie.
        for name in ["manifest.json", "settings.json"] {
            if let version = DataSchema.version(ofSettingsAt: contentRoot.appendingPathComponent(name)), version > DataSchema.current {
                throw RestoreError.newerSchema(version)
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

    /// Zachowany katalog danych obok obecnego (R2-01).
    public struct PreviousState: Equatable, Sendable {
        public enum Kind: Sendable {
            /// Stan sprzed przywrócenia kopii zapasowej.
            case beforeRestore
            /// Stan sprzed cofnięcia przywracania; ponowne „cofnięcie” wraca do niego.
            case beforeUndo
        }

        public let url: URL
        public let kind: Kind
        /// Chwila, w której ten stan został zastąpiony (z nazwy folderu).
        public let date: Date?
    }

    private var undoStatePrefix: String { "\(dataDirectory.lastPathComponent) przed cofnięciem " }

    /// Poprzednie stany obu rodzajów, od najnowszego.
    public func previousStateDetails() -> [PreviousState] {
        let names = (try? fileManager.contentsOfDirectory(atPath: parentDirectory.path)) ?? []
        let prefixes: [(String, PreviousState.Kind)] = [(previousStatePrefix, .beforeRestore), (undoStatePrefix, .beforeUndo)]
        let states: [(stamp: String, state: PreviousState)] = names.compactMap { name in
            guard let (prefix, kind) = prefixes.first(where: { name.hasPrefix($0.0) }) else { return nil }
            let stamp = String(name.dropFirst(prefix.count))
            let state = PreviousState(url: parentDirectory.appendingPathComponent(name), kind: kind, date: Self.date(fromTimestamp: stamp))
            return (stamp, state)
        }
        // Znacznik czasu ma stały format, więc porządek napisów jest chronologiczny.
        return states.sorted { $0.stamp > $1.stamp }.map(\.state)
    }

    /// Poprzednie stany, od najnowszego.
    public func previousStates() -> [URL] {
        previousStateDetails().map(\.url)
    }

    public var canUndo: Bool { !previousStates().isEmpty }

    /// Wraca do najnowszego zachowanego stanu. Obecne dane nie są usuwane: zostają obok jako
    /// „przed cofnięciem” (R2-01), więc ponowne wywołanie wraca do nich.
    /// - Returns: folder z danymi sprzed cofnięcia.
    @discardableResult
    public func undoLastRestore() throws -> URL {
        guard let previous = previousStates().first else { throw RestoreError.nothingToUndo }
        let keptName = undoStatePrefix + Self.timestamp()
        let kept = parentDirectory.appendingPathComponent(keptName)
        if fileManager.fileExists(atPath: dataDirectory.path) {
            _ = try fileManager.replaceItemAt(
                dataDirectory,
                withItemAt: previous,
                backupItemName: keptName,
                options: .withoutDeletingBackupItem
            )
        } else {
            try fileManager.moveItem(at: previous, to: dataDirectory)
        }
        pruneOldStates()
        Self.logger.notice("Cofnięto przywracanie do \(previous.lastPathComponent, privacy: .public); obecne dane: \(keptName, privacy: .public)")
        return kept
    }

    private func pruneOldStates() {
        for state in previousStates().dropFirst(Self.previousStatesLimit) {
            do {
                try fileManager.removeItem(at: state)
            } catch {
                Self.logger.error("Nie można usunąć starego stanu \(state.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static let timestampFormat = "yyyy-MM-dd HH-mm-ss-SSS"

    private static func date(fromTimestamp stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = timestampFormat
        return formatter.date(from: stamp)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // Milisekundy: kilka przywróceń w tej samej sekundzie nie może mieć tej samej nazwy.
        formatter.dateFormat = timestampFormat
        return formatter.string(from: Date())
    }
}

// MARK: - Zip Archive

/// Sprawdzenie archiwum ZIP przed rozpakowaniem (R2-14). Wywołania czekają na proces: nie na wątku głównym.
enum ZipArchive {
    /// Kopia danych to kilka MB; 2 GB to bezpieczny górny limit (bomba ZIP nie zapełni dysku).
    static let maxUncompressedSize: Int64 = 2 * 1024 * 1024 * 1024

    /// Suma rozmiarów po rozpakowaniu z katalogu archiwum (`zipinfo -t`); `nil`, gdy to nie ZIP albo nie da się odczytać.
    static func declaredUncompressedSize(of archive: URL) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-t", archive.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseTotals(String(decoding: data, as: UTF8.self))
    }

    /// Czy plik zaczyna się sygnaturą ZIP (`PK\u{3}\u{4}`, pusty ZIP `PK\u{5}\u{6}`, `PK\u{7}\u{8}`).
    /// Ucięte archiwum też ją ma, więc `.hly` z sygnaturą nie jest czytany jako tekst (R6-02).
    static func hasSignature(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let bytes = [UInt8](head)
        guard bytes[0] == 0x50, bytes[1] == 0x4B else { return false }
        return [(3, 4), (5, 6), (7, 8)].contains { bytes[2] == $0.0 && bytes[3] == $0.1 }
    }

    /// „2 files, 1234 bytes uncompressed, 567 bytes compressed: 54.1%”
    static func parseTotals(_ text: String) -> Int64? {
        guard let match = text.firstMatch(of: /([0-9]+) bytes uncompressed/) else { return nil }
        return Int64(match.1)
    }
}
