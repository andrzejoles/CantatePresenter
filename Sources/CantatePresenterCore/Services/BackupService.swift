import Foundation
import AppKit
import UniformTypeIdentifiers

public struct BackupManifest: Codable {
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
    
    private init() {}
    
    private var dataDirectory: URL {
        AppPaths.shared.dataDirectory
    }
    
    // MARK: - Create Full Backup Package
    
    /// Creates a complete `.holyricsbackup` archive containing all app settings, standby screen, songs, chords, plans, languages and logos.
    public func createBackupArchive(comment: String? = nil) throws -> (archiveURL: URL, manifest: BackupManifest) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("HolyricsBackupStaging_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up staging directory after compression
            try? fileManager.removeItem(at: tempDir)
        }
        
        let store = DataStore.shared
        var includedFiles: [String] = []
        
        // 1. Copy vital database files
        let filesToInclude = [
            "songs.json",
            "plans.json",
            "settings.json",
            "standby.html",
            "custom_languages.json"
        ]
        
        for fileName in filesToInclude {
            let srcURL = dataDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: srcURL.path) {
                let dstURL = tempDir.appendingPathComponent(fileName)
                try fileManager.copyItem(at: srcURL, to: dstURL)
                includedFiles.append(fileName)
            }
        }
        
        // 2. Copy directories: logos and templates
        let directoriesToInclude = ["logos", "templates"]
        for dirName in directoriesToInclude {
            let srcDir = dataDirectory.appendingPathComponent(dirName)
            if fileManager.fileExists(atPath: srcDir.path) {
                let dstDir = tempDir.appendingPathComponent(dirName)
                try fileManager.copyItem(at: srcDir, to: dstDir)
                includedFiles.append("\(dirName)/")
            }
        }
        
        // 3. Create Manifest
        let manifest = BackupManifest(
            songsCount: store.songs.count,
            plansCount: store.plans.count,
            activeLogoId: store.settings.activeLogoId,
            appLanguage: store.settings.appLanguage,
            includedFiles: includedFiles,
            comment: comment
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))
        
        // 4. Compress staging folder into single .cantatebackup archive using macOS ditto
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let archiveFileName = "CantatePresenter_Backup_\(timestamp).cantatebackup"
        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(archiveFileName)
        
        if fileManager.fileExists(atPath: archiveURL.path) {
            try? fileManager.removeItem(at: archiveURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 && fileManager.fileExists(atPath: archiveURL.path) else {
            throw NSError(domain: "CantateBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: Lnow("Nie udało się skompresować archiwum kopii zapasowej (kod ditto: {0})", process.terminationStatus)])
        }
        
        return (archiveURL, manifest)
    }
    
    // MARK: - Restore Backup Package
    
    /// Restores app data from a `.cantatebackup`, `.holyricsbackup` or `.zip` archive (S5: see `BackupRestorer`).
    /// The archive is unpacked off the main thread, validated, and swapped in as a whole; the previous data
    /// directory is kept so the restore can be undone.
    public func restoreBackup(from archiveURL: URL) async throws -> BackupManifest {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw NSError(domain: "HolyricsMacBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: Lnow("Wskazany plik kopii zapasowej nie istnieje: {0}", archiveURL.lastPathComponent)])
        }
        
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("CantateRestore_\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: extractDir)
        }
        try await BackupRestorer.unzip(archiveURL, to: extractDir)
        
        // Locate manifest.json (in root or nested)
        var manifestURL = extractDir.appendingPathComponent("manifest.json")
        var contentRoot = extractDir
        if !fileManager.fileExists(atPath: manifestURL.path) {
            // Check subfolders
            if let contents = try? fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
               let subfolder = contents.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) {
                let nestedManifest = subfolder.appendingPathComponent("manifest.json")
                if fileManager.fileExists(atPath: nestedManifest.path) {
                    manifestURL = nestedManifest
                    contentRoot = subfolder
                }
            }
        }
        
        var manifest: BackupManifest? = nil
        if let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(BackupManifest.self, from: data)
        }
        
        let result = try BackupRestorer(dataDirectory: dataDirectory).restore(fromExtracted: contentRoot)
        reloadStores()
        
        return manifest ?? BackupManifest(
            songsCount: result.songsCount,
            plansCount: result.plansCount,
            activeLogoId: "unknown",
            appLanguage: "pl",
            includedFiles: BackupRestorer.allowedItems
        )
    }
    
    public var canUndoRestore: Bool {
        BackupRestorer(dataDirectory: dataDirectory).canUndo
    }
    
    /// Wraca do danych sprzed ostatniego przywracania kopii.
    public func undoLastRestore() throws {
        try BackupRestorer(dataDirectory: dataDirectory).undoLastRestore()
        reloadStores()
    }
    
    private func reloadStores() {
        let store = DataStore.shared
        store.loadSettings()
        store.loadSongs()
        store.loadPlans()
        store.updateActiveLogo(id: store.settings.activeLogoId)
        LocalizationService.shared.loadCustomLanguages()
    }
    
    // MARK: - Save Dialog Helper
    
    public func exportBackupWithSavePanel() -> Bool {
        do {
            let (tempArchiveURL, _) = try createBackupArchive()
            
            let savePanel = NSSavePanel()
            savePanel.title = Lnow("Zapisz pełną kopię zapasową CantatePresenter")
            savePanel.message = Lnow("Wybierz miejsce zapisu pliku kopii zapasowej (.cantatebackup)")
            savePanel.prompt = Lnow("Utwórz kopię")
            savePanel.nameFieldStringValue = tempArchiveURL.lastPathComponent
            savePanel.allowedContentTypes = [
                UTType(filenameExtension: "cantatebackup") ?? .data,
                UTType(filenameExtension: "holyricsbackup") ?? .data,
                UTType.zip
            ]
            savePanel.canCreateDirectories = true
            
            if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: tempArchiveURL, to: destinationURL)
                try? FileManager.default.removeItem(at: tempArchiveURL)
                return true
            }
            try? FileManager.default.removeItem(at: tempArchiveURL)
            return false
        } catch {
            let alert = NSAlert()
            alert.messageText = Lnow("Błąd tworzenia kopii zapasowej")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }
    
    // MARK: - Open Dialog Helper
    
    public func restoreBackupWithOpenPanel() async -> (success: Bool, message: String) {
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
        
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            do {
                let manifest = try await restoreBackup(from: selectedURL)
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                let dateStr = dateFormatter.string(from: manifest.createdAt)
                return (true, Lnow("Pomyślnie przywrócono stan aplikacji z kopii z dnia {0} (pieśni: {1}, plany: {2}). Poprzednie dane zachowano: Plik → Cofnij ostatnie przywracanie.", dateStr, manifest.songsCount, manifest.plansCount))
            } catch {
                return (false, Lnow("Błąd przywracania: {0}", error.localizedDescription))
            }
        }
        return (false, Lnow("Anulowano wybór pliku."))
    }
}
