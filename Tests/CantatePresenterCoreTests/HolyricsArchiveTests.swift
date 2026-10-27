import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R3-08: archiwum Holyrics z dowiązaniem symbolicznym

@Suite("Import archiwum Holyrics (.zip/.hly)")
struct HolyricsArchiveTests {
    /// Archiwum ZIP z katalogu (`ditto` zapisuje dowiązania symboliczne jako dowiązania).
    private func zip(_ folder: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", folder.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Dowiązanie symboliczne w archiwum nie wczytuje pliku spoza archiwum (R3-08)")
    func symlinkIsNotFollowed() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("TAJNE HASŁO 1234\nsekretna linia", to: "sekret.txt")
        let pack = dir.file("paczka")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("Pan jest pasterzem moim\nniczego mi nie braknie".utf8).write(to: pack.appendingPathComponent("pasterz.txt"))
        try FileManager.default.createSymbolicLink(atPath: pack.appendingPathComponent("a.txt").path,
                                                   withDestinationPath: dir.file("sekret.txt").path)
        try FileManager.default.createSymbolicLink(atPath: pack.appendingPathComponent("b.txt").path,
                                                   withDestinationPath: "../../sekret.txt")
        let archive = dir.file("paczka.hly")
        try zip(pack, to: archive)

        let songs = HolyricsImporter.readRawSongs(from: archive)
        let text = songs.map { $0.title + "\n" + $0.rawLyrics }.joined(separator: "\n")
        #expect(text.contains("Pan jest pasterzem"))
        #expect(!text.contains("TAJNE"))
    }

    @Test("Uszkodzone archiwum .hly: brak pieśni z bajtów ZIP i problem z rozpakowaniem (R6-02)")
    func truncatedHlyArchive() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let folder = dir.file("src")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<40 {
            let song = Song(title: "Pieśń \(index)", rawLyrics: String(repeating: "Zażółć gęślą jaźń \(index) ", count: 50))
            try SongExporter.songToText(song).write(to: folder.appendingPathComponent("s\(index).txt"), atomically: true, encoding: .utf8)
        }
        let full = dir.file("full.zip")
        try zip(folder, to: full)
        let data = try Data(contentsOf: full)
        for name in ["broken.hly", "broken.holyrics", "broken.zip"] {
            try data.prefix(data.count / 2).write(to: dir.file(name))
            let outcome = TextImporter.importFile(dir.file(name))
            #expect(!outcome.songs.contains { $0.rawLyrics.hasPrefix("PK") }, "\(name)")
            #expect(!outcome.problems.isEmpty, "\(name)")
        }
    }

    @Test("Plik .hly z danymi binarnymi (nie ZIP) nie staje się pieśnią (R6-02)")
    func binaryHlyIsNotASong() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let bytes = (0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        try Data(bytes).write(to: dir.file("binary.hly"))
        let outcome = TextImporter.importFile(dir.file("binary.hly"))
        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
    }

    @Test("Archiwum w archiwum nie jest rozpakowywane, ale jest zgłaszane; pieśni obok wczytują się")
    func nestedArchiveIsReported() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let inner = dir.file("wewnętrzne")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("Barka\n\nPan kiedyś stanął nad brzegiem".utf8).write(to: inner.appendingPathComponent("barka.txt"))
        let outer = dir.file("zewnętrzne")
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        try zip(inner, to: outer.appendingPathComponent("środek.zip"))
        try Data("Pasterz\n\nPan jest pasterzem moim".utf8).write(to: outer.appendingPathComponent("pasterz.txt"))
        try zip(outer, to: dir.file("paczka.zip"))

        let outcome = TextImporter.importFile(dir.file("paczka.zip"))
        #expect(outcome.songs.map(\.title) == ["Pasterz"])
        #expect(outcome.problems.count == 1)
        #expect(outcome.problems.first?.fileName.hasSuffix("środek.zip") == true)
    }

    @Test("Plik .hly z tekstem Holyrics (nie ZIP) nadal się wczytuje")
    func textHlyStillImports() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("@title: Barka\n##(Verse 1)\nPan kiedyś stanął nad brzegiem", to: "barka.hly")
        let outcome = TextImporter.importFile(dir.file("barka.hly"))
        #expect(outcome.songs.map(\.title) == ["Barka"])
        #expect(outcome.problems.isEmpty)
    }

    @Test("Tekstowy .hly w archiwum ZIP się wczytuje; prawdziwy ZIP nazwany .hly jest archiwum w archiwum (R10-04)")
    func textHlyInsideZip() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let pack = dir.file("paczka")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("@nome: Barka\n##(Verse 1)\nPan kiedyś stanął".utf8).write(to: pack.appendingPathComponent("barka.hly"))
        let inner = dir.file("wewnętrzne")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("Pasterz\n\nPan jest pasterzem moim".utf8).write(to: inner.appendingPathComponent("pasterz.txt"))
        try zip(inner, to: pack.appendingPathComponent("środek.hly"))
        try zip(pack, to: dir.file("paczka.zip"))

        let outcome = TextImporter.importFile(dir.file("paczka.zip"))

        #expect(outcome.songs.map(\.title) == ["Barka"])
        #expect(outcome.problems.count == 1)
        #expect(outcome.problems.first?.fileName.hasSuffix("środek.hly") == true)
    }

    @Test("XML bez pieśni (np. plist) nie staje się pieśnią z surowym XML; pieśni XML wczytują się dalej (R10-05)")
    func xmlWithoutSongs() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleName</key><string>Foo</string></dict></plist>"#, to: "Info.xml")
        try dir.write("<song><title>Barka</title><lyrics>Pan kiedyś stanął</lyrics></song>", to: "barka.xml")

        let plist = TextImporter.importFile(dir.file("Info.xml"))
        let song = TextImporter.importFile(dir.file("barka.xml"))

        #expect(plist.songs.isEmpty)
        #expect(plist.problems.map(\.fileName) == ["Info.xml"])
        #expect(song.songs.map(\.title) == ["Barka"])
        #expect(song.problems.isEmpty)
    }

    /// Kopia folderu danych CantatePresenter: tylko `songs.json` zawiera pieśni.
    private func makeDataFolder(in dir: TestDirectory) throws -> URL {
        let data = dir.file("dane")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let files = [
            "songs.json": #"[{"title":"A","rawLyrics":"x"}]"#,
            "plans.json": #"[{"name":"Plan","items":[]}]"#,
            "settings.json": #"{"fontFamily":"X","schemaVersion":1}"#,
            "ccli_usage.json": "[]",
            "custom_languages.json": #"[{"code":"xx","name":"Test","flag":"🌐","strings":{"Tak":"Ja"}}]"#,
            "manifest.json": #"{"appName":"CantatePresenter","songsCount":1,"plansCount":1}"#
        ]
        for (name, text) in files {
            try Data(text.utf8).write(to: data.appendingPathComponent(name))
        }
        return data
    }

    @Test("Folder i ZIP z danymi aplikacji: pliki bez pieśni są pomijane bez komunikatu (R10-07)")
    func dataFolderFilesAreSkippedSilently() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataFolder(in: dir)
        try zip(data, to: dir.file("dane.zip"))

        for url in [data, dir.file("dane.zip")] {
            let outcome = TextImporter.importFile(url)
            #expect(outcome.songs.map(\.title) == ["A"], "\(url.lastPathComponent)")
            #expect(outcome.problems.isEmpty, "\(url.lastPathComponent): \(outcome.problems)")
        }
    }

    @Test("Folder: nieczytelny JSON jest zgłaszany, a plik bez pieśni wybrany wprost też (R10-07)")
    func brokenJSONInFolderIsReported() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataFolder(in: dir)
        try Data("{ zepsuty".utf8).write(to: data.appendingPathComponent("broken.json"))

        let folder = TextImporter.importFile(data)
        let plans = TextImporter.importFile(data.appendingPathComponent("plans.json"))

        #expect(folder.songs.map(\.title) == ["A"])
        #expect(folder.problems.map(\.fileName) == ["broken.json"])
        #expect(plans.songs.isEmpty)
        #expect(plans.problems.map(\.fileName) == ["plans.json"])
    }

    @Test("ZIP bez żadnej pieśni wybrany wprost jest zgłaszany")
    func zipWithoutSongsIsReported() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = try makeDataFolder(in: dir)
        try FileManager.default.removeItem(at: data.appendingPathComponent("songs.json"))
        try zip(data, to: dir.file("bez-piesni.zip"))

        let outcome = TextImporter.importFile(dir.file("bez-piesni.zip"))

        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.map(\.fileName) == ["bez-piesni.zip"])
    }
}
