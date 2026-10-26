import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-05 / R2-22: ustawienia zmienione w arkuszu bez „Gotowe”

@MainActor
@Suite("Zapis ustawień przy zamykaniu arkusza i aplikacji (R4-05)")
struct SettingsSavingTests {
    private func savedSettings(_ dir: TestDirectory) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: dir.contents(of: "settings.json"))
    }

    @Test("Zmiana przez powiązanie (bez „Gotowe”) trafia do pliku przy zamknięciu arkusza lub aplikacji")
    func unsavedChangeIsWritten() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.settings.ccliLicenseNumber = "123456"
        #expect(try savedSettings(dir).ccliLicenseNumber != "123456")

        store.saveSettingsIfChanged()

        #expect(try savedSettings(dir).ccliLicenseNumber == "123456")
    }

    @Test("Bez zmian nic nie jest zapisywane, więc historia K1 nie zapełnia się kopiami")
    func noChangeNoWrite() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.settings.ccliLicenseNumber = "1"
        store.saveSettings()
        let history = dir.url.appendingPathComponent("history")
        let before = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []

        store.saveSettingsIfChanged()
        store.saveSettingsIfChanged()

        let after = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []
        #expect(before.sorted() == after.sorted())
        let reloaded = DataStore(dataDirectory: dir.url)
        reloaded.saveSettingsIfChanged()
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []).sorted() == after.sorted())
    }
}
