import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Tworzenie archiwum kopii i zabezpieczenia przywracania (R2-12, R2-13, R2-14, R2-15, R2-19)

@Suite("Archiwum kopii zapasowej")
struct BackupArchiveTests {
    private func makeDataDirectory(in dir: TestDirectory) throws -> URL {
        let data = dir.url.appendingPathComponent("dane")
        try FileManager.default.createDirectory(at: data.appendingPathComponent("logos"), withIntermediateDirectories: true)
        let songs = try JSONEncoder().encode([Song(title: "Barka", rawLyrics: "Pan kiedyś stanął nad brzegiem")])
        try songs.write(to: data.appendingPathComponent("songs.json"))
        try Data("[]".utf8).write(to: data.appendingPathComponent("plans.json"))
        try Data("png".utf8).write(to: data.appendingPathComponent("logos/stare.png"))
        return data
    }

    private func archive(_ data: URL, in dir: TestDirectory, date: Date = Date()) async throws -> URL {
        try await BackupService.makeArchive(
            of: data, songsCount: 1, plansCount: 0, activeLogoId: "logo", appLanguage: "pl",
            comment: nil, date: date, temporaryDirectory: dir.url
        ).archiveURL
    }

    @Test("Archiwum powstaje poza wątkiem głównym, z unikalną ścieżką i stałym formatem nazwy (R2-13, R2-19)")
    func createsArchiveWithUniquePaths() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataDirectory(in: dir)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        async let first = archive(data, in: dir, date: date)
        async let second = archive(data, in: dir, date: date)
        let (a, b) = try await (first, second)

        #expect(a != b)
        #expect(a.lastPathComponent == b.lastPathComponent)
        #expect(a.lastPathComponent.wholeMatch(of: /CantatePresenter_Backup_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.cantatebackup/) != nil)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))

        BackupService.removeTemporaryArchive(a)
        #expect(!FileManager.default.fileExists(atPath: a.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test("Kopia i przywracanie: pliki danych wracają, logos/ nie trafia już do kopii (R2-15)")
    func archiveRoundTrip() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataDirectory(in: dir)
        let archiveURL = try await archive(data, in: dir)

        let extracted = dir.url.appendingPathComponent("rozpakowane")
        try await BackupRestorer.unzip(archiveURL, to: extracted)
        let root = BackupRestorer.contentRoot(in: extracted)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("songs.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("logos").path))

        let target = dir.url.appendingPathComponent("przywrócone/CantatePresenter")
        let result = try BackupRestorer(dataDirectory: target).restore(fromExtracted: root)
        #expect(result.songsCount == 1)
    }

    @Test("Folder danych spakowany w Finderze (bez manifest.json) jest rozpoznawany (R2-14)")
    func findsPlainZippedDataFolder() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let extracted = dir.url.appendingPathComponent("rozpakowane")
        let nested = extracted.appendingPathComponent("CantatePresenter")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extracted.appendingPathComponent("__MACOSX"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: nested.appendingPathComponent("songs.json"))

        #expect(BackupRestorer.contentRoot(in: extracted).resolvingSymlinksInPath().path == nested.resolvingSymlinksInPath().path)
    }

    @Test("Dowiązanie symboliczne w kopii odrzuca przywracanie (R2-14)")
    func rejectsSymlinks() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataDirectory(in: dir)
        let root = dir.url.appendingPathComponent("kopia")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: data.appendingPathComponent("songs.json"), to: root.appendingPathComponent("songs.json"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("standby.html").path, withDestinationPath: "/etc/hosts")

        let target = dir.url.appendingPathComponent("cel/CantatePresenter")
        #expect(throws: BackupRestorer.RestoreError.self) {
            try BackupRestorer(dataDirectory: target).restore(fromExtracted: root)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Dowiązanie w katalogu starej kopii nie trafia do danych: logos/ nie jest przywracane (R2-14, R11-03)")
    func ignoresNestedSymlinks() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataDirectory(in: dir)
        try FileManager.default.createSymbolicLink(atPath: data.appendingPathComponent("logos/link.png").path, withDestinationPath: "/etc/hosts")
        let target = dir.url.appendingPathComponent("cel/CantatePresenter")

        _ = try BackupRestorer(dataDirectory: target).restore(fromExtracted: data)
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("logos").path))
    }

    @Test("Rozmiar po rozpakowaniu z zipinfo (R2-14)")
    func readsDeclaredSize() async throws {
        #expect(ZipArchive.parseTotals("2 files, 1234 bytes uncompressed, 567 bytes compressed:  54.1%") == 1234)
        #expect(ZipArchive.parseTotals("coś innego") == nil)

        let dir = try TestDirectory()
        defer { dir.remove() }
        let archiveURL = try await archive(try makeDataDirectory(in: dir), in: dir)
        let size = try #require(ZipArchive.declaredUncompressedSize(of: archiveURL))
        #expect(size > 0 && size < ZipArchive.maxUncompressedSize)
        try Data("to nie zip".utf8).write(to: dir.file("zły.zip"))
        #expect(ZipArchive.declaredUncompressedSize(of: dir.file("zły.zip")) == nil)
    }

    @Test("Anulowany wybór pliku to .cancelled, bez tekstu do porównywania (R2-12)")
    @MainActor
    func cancelledRestoreIsAnOutcome() async {
        let outcome = await BackupService.shared.restoreOutcome(from: nil)
        #expect(outcome == .cancelled)
        #expect(outcome.message == nil)
        #expect(!outcome.isSuccess)
    }

    @Test("Lokalne kopie przy zamykaniu: usuwane najstarsze według daty utworzenia, nie nazwy (R2-19)")
    @MainActor
    func keepsNewestByCreationDate() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let backups = dir.url.appendingPathComponent("backups")
        // Nazwa z innego kalendarza sortuje się po nowszych, choć jest najstarsza.
        let names = ["CantatePresenter_Backup_2569-01-01_10-00-00.cantatebackup",
                     "CantatePresenter_Backup_2026-02-01_10-00-00.cantatebackup",
                     "CantatePresenter_Backup_2026-03-01_10-00-00.cantatebackup"]
        for (index, name) in names.enumerated() {
            let file = dir.file(name)
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: Double(1_700_000_000 + index * 1000))], ofItemAtPath: file.path)
            _ = try ExitBackupCoordinator.keepLocally(file, in: backups, limit: 2)
        }

        let kept = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        #expect(kept == names.dropFirst().sorted())
    }
}

// MARK: - R6-13: data kopii bez manifest.json (folder danych spakowany w Finderze)

@Suite("Data kopii bez manifestu")
struct BackupFallbackDateTests {
    @Test("Data to najnowsza data zmiany plików danych, a nie chwila przywracania (R6-13)")
    func newestDataFileDate() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_750_000_000)
        try dir.write("[]", to: "songs.json")
        try dir.write("{}", to: "settings.json")
        try dir.write("x", to: "inny.txt")
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: dir.file("songs.json").path)
        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: dir.file("settings.json").path)

        #expect(BackupService.dataDate(in: dir.url) == newer)
        #expect(BackupService.dataDate(in: dir.url.appendingPathComponent("brak")) == nil)
    }
}

// MARK: - R6-03: kopia z arkusza Ustawień zawiera zmiany z tego arkusza

@Suite("Kopia zapasowa z niezapisanymi ustawieniami")
@MainActor
struct BackupUnsavedSettingsTests {
    @Test("Archiwum zawiera ustawienia zmienione w pamięci, a nie tylko te zapisane na dysku (R6-03)")
    func archiveContainsInMemorySettings() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = dir.url.appendingPathComponent("dane")
        let store = DataStore(dataDirectory: data)
        store.settings.fontFamily = "R6-03 Font"

        let archive = try await BackupService.createBackupArchive(of: store, in: data, comment: nil, temporaryDirectory: dir.url).archiveURL
        defer { BackupService.removeTemporaryArchive(archive) }
        let extracted = dir.url.appendingPathComponent("rozpakowane")
        try await BackupRestorer.unzip(archive, to: extracted)
        let settingsData = try Data(contentsOf: BackupRestorer.contentRoot(in: extracted).appendingPathComponent("settings.json"))
        let settings = try JSONFileStore.makeDecoder().decode(AppSettings.self, from: settingsData)
        #expect(settings.fontFamily == "R6-03 Font")
    }

    private func savedSettings(in directory: URL) throws -> AppSettings {
        let data = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
        return try JSONFileStore.makeDecoder().decode(AppSettings.self, from: data)
    }

    @Test("Przywracanie i cofnięcie z arkusza Ustawień zachowują ustawienia zmienione w pamięci (R10-03)")
    func restoreKeepsInMemorySettings() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let source = dir.url.appendingPathComponent("kopia")
        let sourceStore = DataStore(dataDirectory: source)
        sourceStore.settings.ccliLicenseNumber = "z kopii"
        sourceStore.saveSettings()
        let archive = try await BackupService.createBackupArchive(of: sourceStore, in: source, comment: nil, temporaryDirectory: dir.url).archiveURL
        defer { BackupService.removeTemporaryArchive(archive) }

        let data = dir.url.appendingPathComponent("dane")
        let store = DataStore(dataDirectory: data)
        store.settings.ccliLicenseNumber = "przed przywróceniem"

        _ = try await BackupService.restoreBackup(from: archive, into: store, dataDirectory: data)

        #expect(store.settings.ccliLicenseNumber == "z kopii")
        let previous = try #require(BackupRestorer(dataDirectory: data).previousStateDetails().first)
        #expect(try savedSettings(in: previous.url).ccliLicenseNumber == "przed przywróceniem")

        store.settings.ccliLicenseNumber = "przed cofnięciem"
        let kept = try BackupService.undoLastRestore(of: store, dataDirectory: data)

        #expect(store.settings.ccliLicenseNumber == "przed przywróceniem")
        #expect(try savedSettings(in: kept).ccliLicenseNumber == "przed cofnięciem")
    }
}
