import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - W2: kopia przy zamykaniu

@MainActor
@Suite("Kopia przy zamykaniu (W2)")
struct ExitBackupTests {
    private struct UploadFailed: Error {}

    private func makeArchive(in dir: TestDirectory, name: String = "kopia.zip") throws -> URL {
        let url = dir.file(name)
        try Data("zip".utf8).write(to: url)
        return url
    }

    @Test("Operacje na głównym aktorze kończą się bez zakleszczenia; po wysyłce archiwum jest usuwane")
    func uploadsAndRemovesArchive() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let archive = try makeArchive(in: dir)
        var uploaded: URL?

        let outcome = await ExitBackupCoordinator().run(
            operations: .init(
                createArchive: { archive },
                upload: { uploaded = $0 },
                keepLocally: { archive in Issue.record("nie powinno być wywołane"); return archive }
            ),
            timeout: .seconds(5)
        )

        #expect(outcome == .uploaded)
        #expect(uploaded == archive)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("Nieudana wysyłka: archiwum zostaje zachowane lokalnie")
    func failedUploadKeepsArchive() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let archive = try makeArchive(in: dir)
        let kept = dir.file("backups/kopia.zip")

        let outcome = await ExitBackupCoordinator().run(
            operations: .init(
                createArchive: { archive },
                upload: { _ in throw UploadFailed() },
                keepLocally: { _ in kept }
            ),
            timeout: .seconds(5)
        )

        #expect(outcome == .keptLocally(kept))
    }

    @Test("Zawieszona wysyłka kończy się po limicie czasu")
    func hangingUploadTimesOut() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let archive = try makeArchive(in: dir)
        let start = ContinuousClock.now

        let outcome = await ExitBackupCoordinator().run(
            operations: .init(
                createArchive: { archive },
                upload: { _ in try await Task.sleep(for: .seconds(30)) },
                keepLocally: { $0 }
            ),
            timeout: .milliseconds(200)
        )

        #expect(outcome == .timedOut)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Pomiń kończy czekanie od razu")
    func skipEndsImmediately() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let archive = try makeArchive(in: dir)
        let coordinator = ExitBackupCoordinator()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            coordinator.skip()
        }
        let outcome = await coordinator.run(
            operations: .init(
                createArchive: { archive },
                upload: { _ in try await Task.sleep(for: .seconds(30)) },
                keepLocally: { $0 }
            ),
            timeout: .seconds(30)
        )

        #expect(outcome == .skipped)
    }

    @Test("Lokalne kopie: zostaje 5 najnowszych")
    func localBackupsArePruned() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let backups = dir.url.appendingPathComponent("backups")

        for index in 1...7 {
            let archive = try makeArchive(in: dir, name: "exit-2026-10-0\(index).cantatebackup")
            _ = try ExitBackupCoordinator.keepLocally(archive, in: backups, limit: 5)
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        #expect(names == (3...7).map { "exit-2026-10-0\($0).cantatebackup" })
    }
}
