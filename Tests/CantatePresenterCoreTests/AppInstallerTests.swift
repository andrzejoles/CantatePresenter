import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Instalacja w folderze Programy

@Suite("Instalacja w folderze Programy")
struct AppInstallerTests {
    @Test("Zainstalowana: /Applications i ~/Applications; DMG, App Translocation i podobne nazwy nie")
    func installedLocations() {
        let home = "/Users/test"
        #expect(AppInstallerService.isInstalled(bundlePath: "/Applications/CantatePresenter.app", home: home))
        #expect(AppInstallerService.isInstalled(bundlePath: "/Users/test/Applications/CantatePresenter.app", home: home))
        #expect(!AppInstallerService.isInstalled(bundlePath: "/Volumes/CantatePresenter/CantatePresenter.app", home: home))
        #expect(!AppInstallerService.isInstalled(
            bundlePath: "/private/var/folders/x/AppTranslocation/1234/d/CantatePresenter.app", home: home))
        #expect(!AppInstallerService.isInstalled(bundlePath: "/ApplicationsOld/CantatePresenter.app", home: home))
        #expect(!AppInstallerService.isInstalled(bundlePath: "/Volumes/X/Applications/CantatePresenter.app", home: home))
    }

    @Test("Nowa kopia zastępuje poprzednią, bez pozostałości i bez kwarantanny")
    func replacesPreviousVersion() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let source = try makeBundle(dir.file("source/CantatePresenter.app"), version: "new")
        let destination = try makeBundle(dir.file("Applications/CantatePresenter.app"), version: "old")
        try setQuarantine(on: source)

        try AppInstallerService.install(from: source, to: destination)

        #expect(try version(in: destination) == "new")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.file("Applications").path) == ["CantatePresenter.app"])
        #expect(!hasQuarantine(destination))
    }

    @Test("Nieudane kopiowanie przywraca poprzednią wersję")
    func failedCopyRestoresPrevious() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let destination = try makeBundle(dir.file("Applications/CantatePresenter.app"), version: "old")

        #expect(throws: (any Error).self) {
            try AppInstallerService.install(from: dir.file("missing/CantatePresenter.app"), to: destination)
        }
        #expect(try version(in: destination) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.file("Applications").path) == ["CantatePresenter.app"])
    }

    // MARK: - Helpers

    private func makeBundle(_ url: URL, version: String) throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(version.utf8).write(to: contents.appendingPathComponent("version.txt"))
        return url
    }

    private func version(in bundle: URL) throws -> String {
        try String(contentsOf: bundle.appendingPathComponent("Contents/version.txt"), encoding: .utf8)
    }

    private func setQuarantine(on url: URL) throws {
        let value = Data("0083;00000000;Safari;".utf8)
        let result = value.withUnsafeBytes { setxattr(url.path, "com.apple.quarantine", $0.baseAddress, value.count, 0, 0) }
        try #require(result == 0)
    }

    private func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }
}
