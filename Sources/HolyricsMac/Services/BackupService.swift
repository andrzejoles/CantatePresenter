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
        version: String = "1.0.0",
        appName: String = "HolyricsMac",
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
        let bundleURL = Bundle.main.bundleURL
        let projectFolder: URL
        if bundleURL.pathExtension == "app" {
            projectFolder = bundleURL.deletingLastPathComponent()
        } else {
            projectFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        return projectFolder.appendingPathComponent("data")
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
        
        // 4. Compress staging folder into single .holyricsbackup archive using macOS ditto
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let archiveFileName = "HolyricsMac_Backup_\(timestamp).holyricsbackup"
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
            throw NSError(domain: "HolyricsMacBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nie udało się skompresować archiwum kopii zapasowej (kod ditto: \(process.terminationStatus))"])
        }
        
        return (archiveURL, manifest)
    }
    
    // MARK: - Restore Backup Package
    
    /// Restores complete app state from a `.holyricsbackup` or `.zip` archive.
    public func restoreBackup(from archiveURL: URL) throws -> BackupManifest {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw NSError(domain: "HolyricsMacBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Wskazany plik kopii zapasowej nie istnieje: \(archiveURL.lastPathComponent)"])
        }
        
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("HolyricsRestore_\(UUID().uuidString)")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: extractDir)
        }
        
        // Unpack archive using macOS ditto
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractDir.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "HolyricsMacBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Błąd rozpakowywania archiwum kopii zapasowej (kod ditto: \(process.terminationStatus))"])
        }
        
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
        if fileManager.fileExists(atPath: manifestURL.path),
           let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(BackupManifest.self, from: data)
        }
        
        // Safety Snapshot of current data directory
        let backupSnapshotDir = fileManager.temporaryDirectory.appendingPathComponent("HolyricsDataRollback_\(UUID().uuidString)")
        if fileManager.fileExists(atPath: dataDirectory.path) {
            try? fileManager.copyItem(at: dataDirectory, to: backupSnapshotDir)
        }
        
        // Copy restored files into dataDirectory
        let items = try fileManager.contentsOfDirectory(at: contentRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for item in items {
            let itemName = item.lastPathComponent
            if itemName == "manifest.json" { continue }
            
            let targetURL = dataDirectory.appendingPathComponent(itemName)
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: item, to: targetURL)
        }
        
        // Reload all app stores on MainActor
        let store = DataStore.shared
        store.loadSettings()
        store.loadSongs()
        store.loadPlans()
        store.updateActiveLogo(id: store.settings.activeLogoId)
        LocalizationService.shared.loadCustomLanguages()
        
        return manifest ?? BackupManifest(
            songsCount: 0,
            plansCount: 0,
            activeLogoId: "unknown",
            appLanguage: "pl",
            includedFiles: items.map { $0.lastPathComponent }
        )
    }
    
    // MARK: - Save Dialog Helper
    
    public func exportBackupWithSavePanel() -> Bool {
        do {
            let (tempArchiveURL, _) = try createBackupArchive()
            
            let savePanel = NSSavePanel()
            savePanel.title = "Zapisz pełną kopię zapasową Holyrics Mac"
            savePanel.message = "Wybierz miejsce zapisu pliku kopii zapasowej (.holyricsbackup)"
            savePanel.prompt = "Utwórz kopię"
            savePanel.nameFieldStringValue = tempArchiveURL.lastPathComponent
            savePanel.allowedContentTypes = [
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
            alert.messageText = "Błąd tworzenia kopii zapasowej"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }
    
    // MARK: - Open Dialog Helper
    
    public func restoreBackupWithOpenPanel() -> (success: Bool, message: String) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Wybierz plik kopii zapasowej do przywrócenia"
        openPanel.message = "Wskaż plik .holyricsbackup lub .zip zawierający kopię bazy Holyrics Mac"
        openPanel.prompt = "Przywróć dane"
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "holyricsbackup") ?? .data,
            UTType.zip
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            do {
                let manifest = try restoreBackup(from: selectedURL)
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                let dateStr = dateFormatter.string(from: manifest.createdAt)
                return (true, "Pomyślnie przywrócono stan aplikacji z kopii z dnia \(dateStr) (pieśni: \(manifest.songsCount), plany: \(manifest.plansCount)).")
            } catch {
                return (false, "Błąd przywracania: \(error.localizedDescription)")
            }
        }
        return (false, "Anulowano wybór pliku.")
    }
}
