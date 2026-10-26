import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Pliki wzorcowe (shared/fixtures)

/// `shared/fixtures/*.json` opisują wejście i oczekiwany wynik kluczowej logiki (podział na slajdy, wyszukiwanie,
/// transpozycja, Auto-Fit, skróty, kopie, importy) niezależnie od kodu, który ją implementuje.
@Suite("Wspólne pliki testowe")
struct SharedFixturesTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures")

    static func load(_ name: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("Podział tekstu na slajdy")
    func lyrics() throws {
        for fixture in try Self.load("lyrics.json") {
            let name = fixture["name"] as? String ?? "?"
            let expected = try #require(fixture["expected"] as? [[String: Any]])
            let slides = Song.parseLyrics(try #require(fixture["input"] as? String))
            #expect(slides.count == expected.count, "\(name)")
            for (slide, wanted) in zip(slides, expected) {
                #expect(slide.type.rawValue == wanted["type"] as? String, "\(name)")
                #expect(slide.label == wanted["label"] as? String, "\(name)")
                #expect(slide.text == wanted["text"] as? String, "\(name)")
                #expect(slide.number == wanted["number"] as? Int, "\(name)")
            }
        }
    }

    @Test("Zwijanie tekstu do wyszukiwania")
    func search() throws {
        for fixture in try Self.load("search.json") {
            let input = try #require(fixture["input"] as? String)
            #expect(Song.foldString(input) == fixture["fold"] as? String, "\(input)")
            #expect(Song.searchFold(input) == fixture["searchFold"] as? String, "\(input)")
        }
    }

    @Test("Duplikaty przy imporcie")
    func deduplication() throws {
        func songs(_ value: Any?) throws -> [Song] {
            try (try #require(value as? [[String: String]])).map { item in
                Song(id: try #require(UUID(uuidString: item["id"] ?? "")), title: item["title"] ?? "", author: item["author"] ?? "", rawLyrics: item["rawLyrics"] ?? "")
            }
        }
        for fixture in try Self.load("dedup.json") {
            let name = fixture["name"] as? String ?? "?"
            let expected = try #require(fixture["expected"] as? [String: Any])
            let report = SongDeduplicationService.shared.processAndDeduplicate(incoming: try songs(fixture["incoming"]), existingLibrary: try songs(fixture["existing"]))
            #expect(report.uniqueSongs.map(\.id.uuidString) == expected["unique"] as? [String], "\(name)")
            let duplicates = try #require(expected["duplicates"] as? [[String: Any]])
            #expect(report.duplicateRecords.count == duplicates.count, "\(name)")
            for (record, wanted) in zip(report.duplicateRecords, duplicates) {
                #expect(record.primarySong.id.uuidString == wanted["primary"] as? String, "\(name)")
                #expect(record.duplicateSong.id.uuidString == wanted["duplicate"] as? String, "\(name)")
                #expect(record.similarityScore == wanted["score"] as? Int, "\(name)")
                #expect(record.reason == Lnow(try #require(wanted["reason"] as? String), record.similarityScore), "\(name)")
            }
            let collisions = try #require(expected["collisions"] as? [[String: Any]])
            #expect(report.existingCollisions.count == collisions.count, "\(name)")
            for (record, wanted) in zip(report.existingCollisions, collisions) {
                #expect(record.primarySong.id.uuidString == wanted["library"] as? String, "\(name)")
                #expect(record.duplicateSong.id.uuidString == wanted["incoming"] as? String, "\(name)")
                #expect(record.similarityScore == wanted["score"] as? Int, "\(name)")
                #expect(record.shouldSkipDuplicate == wanted["skip"] as? Bool, "\(name)")
            }
            let defaults = report.songsToCommit(workingSongs: report.uniqueSongs, duplicateSkips: [:], collisionSkips: [:])
            #expect(defaults.map(\.title) == expected["commit"] as? [String], "\(name)")
            let none = report.songsToCommit(workingSongs: report.uniqueSongs,
                                            duplicateSkips: Dictionary(uniqueKeysWithValues: report.duplicateRecords.map { ($0.id, false) }),
                                            collisionSkips: Dictionary(uniqueKeysWithValues: report.existingCollisions.map { ($0.id, false) }))
            #expect(none.map(\.title) == expected["commitNothingSkipped"] as? [String], "\(name)")
        }
    }

    @Test("Transpozycja akordów")
    func transpose() throws {
        for fixture in try Self.load("transpose.json") {
            let sheet = try #require(fixture["sheet"] as? String)
            let semitones = try #require(fixture["semitones"] as? Int)
            #expect(ChordTransposer.transpose(sheet, semitones: semitones) == fixture["expected"] as? String, "\(sheet)")
        }
    }

    /// Wynik zależy od pomiaru tekstu (tu AppKit, we wzorcu stały pomiar z scripts/make_autofit_fixture.py), więc dokładnie
    /// porównujemy tylko przypadki `anyMeasurer`; pozostałe muszą mieścić się w zakresie rozmiarów.
    @Test("Auto-Fit: przypadki niezależne od czcionki")
    func autoFit() throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("autofit.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for fixture in try #require(root["cases"] as? [[String: Any]]) {
            let name = fixture["name"] as? String ?? "?"
            let size = AutoFitEngine.calculateOptimalFontSize(
                for: try #require(fixture["text"] as? String),
                containerSize: CGSize(width: try #require(fixture["width"] as? Double), height: try #require(fixture["height"] as? Double)),
                lineSpacingFactor: fixture["lineSpacingFactor"] as? Double ?? 1.15,
                marginPercent: fixture["marginPercent"] as? Double ?? 0.07
            )
            if fixture["anyMeasurer"] as? Bool == true {
                #expect(Double(size) == fixture["expected"] as? Double, "\(name)")
            } else {
                #expect(size >= 14 && size <= 260, "\(name)")
            }
        }
    }
}

extension SharedFixturesTests {
    static func context(_ object: [String: String]) -> KeyboardRouter.Context {
        guard object["kind"] == "main" else { return .presentationWindow }
        let focus: KeyboardRouter.Focus
        switch object["focus"] {
        case "text": focus = .text
        case "multilineText": focus = .multilineText
        case "list": focus = .list
        default: focus = .other
        }
        return .mainWindow(focus: focus)
    }

    /// Akcja w postaci zapisywanej w keyboard.json: `{"type": "verse", "number": 3}`.
    static func json(_ action: KeyboardAction?) -> [String: Any]? {
        guard let action else { return nil }
        switch action {
        case .verse(let number): return ["type": "verse", "number": number]
        default:
            let name = "\(action)"
            return ["type": name]
        }
    }

    @Test("Skróty klawiszowe")
    func keyboard() throws {
        for fixture in try Self.load("keyboard.json") {
            let action = KeyboardRouter.action(
                keyCode: UInt16(try #require(fixture["macCode"] as? Int)),
                characters: fixture["characters"] as? String,
                command: try #require(fixture["command"] as? Bool),
                shortcuts: ShortcutSettings(),
                context: Self.context(try #require(fixture["context"] as? [String: String]))
            )
            let expected = fixture["expected"] as? [String: Any]
            let actual = Self.json(action)
            #expect(actual?["type"] as? String == expected?["type"] as? String, "\(fixture["note"] ?? "")")
            #expect(actual?["number"] as? Int == expected?["number"] as? Int, "\(fixture["note"] ?? "")")
        }
    }
}

@Suite("Wspólna kopia zapasowa w formacie macOS")
struct SharedBackupFixtureTests {
    @Test("Kopia z shared/fixtures przywraca się i dane się wczytują")
    func restoresSharedBackup() async throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let extracted = dir.url.appendingPathComponent("extracted")
        try await BackupRestorer.unzip(SharedFixturesTests.directory.appendingPathComponent("backup-macos.cantatebackup"), to: extracted)
        let data = dir.url.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let result = try BackupRestorer(dataDirectory: data).restore(fromExtracted: extracted)
        #expect(result.songsCount == 2 && result.plansCount == 1)

        let songs = try JSONFileStore.makeDecoder().decode([Song].self, from: Data(contentsOf: data.appendingPathComponent("songs.json")))
        #expect(songs[0].slides[0].type == .verse && songs[0].ccliNumber == "9999001")
        #expect(songs[1].slides.count == 2)
    }
}

extension SharedFixturesTests {
    @Test("Chwyty dla muzyków: dopasowanie arkusza do slajdu")
    func chordSheet() throws {
        for fixture in try Self.load("chordsheet.json") {
            let name = fixture["name"] as? String ?? "?"
            let slide = try #require(fixture["slide"] as? [String: String])
            let type = try #require(SlideType(rawValue: slide["type"] ?? ""))
            let result = ChordSheet.lines(for: SongSlide(type: type, label: "x", text: slide["text"] ?? ""),
                                          sheet: fixture["sheet"] as? String, semitones: fixture["semitones"] as? Int ?? 0)
            let expected = try #require(fixture["expected"] as? [String: Any])
            let lines = try #require(expected["lines"] as? [[String: Any]])
            #expect(result.lines.map(\.text) == lines.map { $0["text"] as? String ?? "" }, "\(name)")
            #expect(result.lines.map(\.chords) == lines.map { $0["chords"] as? String }, "\(name)")
            #expect(result.borrowedFrom == expected["borrowedFrom"] as? String, "\(name)")
        }
    }

    @Test("Wikiźródła: tekst, licencja, autor, tytuł i adres strony")
    func wikisource() throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("wikisource.json"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]])
        for page in fixture["pages"] ?? [] {
            let html = page["html"] ?? ""
            #expect(WikisourceParser.lyrics(fromHTML: html) == page["lyrics"], "\(page["name"] ?? "?")")
            #expect(WikisourceParser.license(fromHTML: html).rawValue == page["license"], "\(page["name"] ?? "?")")
        }
        for entry in fixture["authors"] ?? [] {
            #expect(WikisourceParser.author(fromWikitext: entry["wikitext"] ?? "") == entry["author"])
        }
        for entry in fixture["titles"] ?? [] {
            #expect(OnlineSearchService.shortTitle(fromPageTitle: entry["page"] ?? "") == entry["title"])
        }
        for entry in fixture["urls"] ?? [] {
            #expect(WikisourceParser.pageURL(title: entry["page"] ?? "", language: entry["language"] ?? "").absoluteString == entry["url"])
        }
    }

    @Test("Import Holyrics: strumień Java (.mufl), tekst ze znacznikami, XML; uszkodzony strumień to błąd")
    func holyrics() throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("holyrics.json"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for file in try #require(fixture["files"] as? [[String: Any]]) {
            let name = try #require(file["file"] as? String)
            let expected = try #require(file["songs"] as? [[String: Any]])
            let songs = HolyricsImporter.readRawSongs(from: Self.directory.appendingPathComponent(name))
            #expect(songs.map(\.title) == expected.map { $0["title"] as? String ?? "" }, "\(name)")
            #expect(songs.map(\.author) == expected.map { $0["author"] as? String ?? "" }, "\(name)")
            #expect(songs.map(\.key) == expected.map { $0["key"] as? String ?? "" }, "\(name)")
            #expect(songs.map(\.tags) == expected.map { $0["tags"] as? [String] ?? [] }, "\(name)")
            #expect(songs.map(\.rawLyrics) == expected.map { $0["rawLyrics"] as? String ?? "" }, "\(name)")
        }
        for name in fixture["invalidStreams"] as? [String] ?? [] {
            let bytes = try Data(contentsOf: Self.directory.appendingPathComponent(name))
            #expect(throws: (any Error).self) { try HolyricsJavaDeserializer(data: bytes).deserializeMusicRecords() }
        }
    }
}
