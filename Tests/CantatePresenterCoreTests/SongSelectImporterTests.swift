import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - CCLI SongSelect: import plików

/// Przykłady w formatach SongSelect z wymyślonym tekstem (bez prawdziwych pieśni objętych prawem autorskim).
@Suite("Import z CCLI SongSelect")
struct SongSelectImporterTests {
    private let lyricsText = """
    Morning Light

    Verse 1
    Morning light is breaking
    Over hills and sea

    Chorus
    Sing a song of morning
    Sing it out with me

    Verse 2
    Every voice is waking
    Every heart is free

    CCLI Song # 9999001
    Anna Example | John Sample
    © 2024 Example Music Publishing (Admin. by Example Admin)
    For use solely with the SongSelect® Terms of Use.  All rights reserved. www.ccli.com
    CCLI License # 1234567
    """

    @Test("Tekst z SongSelect: tytuł, autorzy, ©, numer CCLI i sekcje jako znaczniki programu")
    func lyricsTextFile() throws {
        #expect(SongSelectImporter.isSongSelectText(lyricsText))
        let song = try #require(SongSelectImporter.parseText(lyricsText))

        #expect(song.title == "Morning Light")
        #expect(song.author == "Anna Example, John Sample")
        #expect(song.copyright == "© 2024 Example Music Publishing (Admin. by Example Admin)")
        #expect(song.ccliNumber == "9999001")
        #expect(song.source == "https://songselect.ccli.com/songs/9999001")
        #expect(!song.rawLyrics.contains("CCLI"))
        #expect(song.rawLyrics.hasPrefix("[Zwrotka 1]\nMorning light is breaking"))

        let types = song.slides.map(\.type)
        #expect(types == [.verse, .chorus, .verse])
        #expect(song.slides.first?.text == "Morning light is breaking\nOver hills and sea")
    }

    @Test("Zwykły plik tekstowy nie jest brany za plik SongSelect")
    func plainTextNotSongSelect() {
        #expect(!SongSelectImporter.isSongSelectText("Barka\n\nPan kiedyś stanął nad brzegiem"))
    }

    @Test("Plik .usr: sekcje z Fields/Words, tonacja, numer z nagłówka sekcji")
    func usrFile() throws {
        let usr = """
        [File]
        Type=SongSelect Import File
        Version=3.0
        [S A9999002]
        Title=Evening Song
        Author=Anna Example | John Sample
        Copyright=2023 Example Music
        Admin=Example Admin
        Keys=D
        Fields=Verse 1/tChorus
        Words=Evening falls/nStars appear/tRest now/nPeace is near
        """
        let song = try #require(SongSelectImporter.parseUSR(usr))

        #expect(song.title == "Evening Song")
        #expect(song.author == "Anna Example, John Sample")
        #expect(song.key == "D")
        #expect(song.ccliNumber == "9999002")
        #expect(song.copyright == "© 2023 Example Music (Admin. by Example Admin)")
        #expect(song.rawLyrics == "[Zwrotka 1]\nEvening falls\nStars appear\n\n[Refren]\nRest now\nPeace is near")
    }

    @Test("ChordPro: tekst bez akordów do projekcji, akordy nad tekstem w arkuszu chwytów")
    func chordPro() throws {
        let pro = """
        {title: Morning Light}
        {key: G}
        {copyright: 2024 Example Music}
        {ccli: 9999001}

        {comment: Verse 1}
        [G]Morning light is [C]breaking
        Over [D]hills and sea

        {start_of_chorus}
        [C]Sing a song of [G]morning
        {end_of_chorus}
        """
        let song = SongSelectImporter.parseChordPro(pro, fallbackTitle: "plik")

        #expect(song.title == "Morning Light")
        #expect(song.key == "G")
        #expect(song.ccliNumber == "9999001")
        #expect(song.rawLyrics == "[Zwrotka 1]\nMorning light is breaking\nOver hills and sea\n\n[Refren]\nSing a song of morning")
        let chords = try #require(song.chords)
        #expect(chords.contains("Verse 1:\nG" + String(repeating: " ", count: 16) + "C\nMorning light is breaking"))
        #expect(chords.contains("     D\nOver hills and sea"))
    }

    @Test("Akordy obok siebie nie sklejają się")
    func adjacentChords() {
        let (chords, lyrics) = SongSelectImporter.splitChords("[G][D]Amen")
        #expect(lyrics == "Amen")
        #expect(chords == "G D")
    }

    @Test("Nazwy sekcji SongSelect na znaczniki programu")
    func sectionMarkers() {
        #expect(SongSelectImporter.sectionMarker(for: "Verse 2") == "[Zwrotka 2]")
        #expect(SongSelectImporter.sectionMarker(for: "Pre-Chorus") == "[Pre-Chorus]")
        #expect(SongSelectImporter.sectionMarker(for: "Ending") == "[Zakończenie]")
        #expect(SongSelectImporter.sectionMarker(for: "Morning light is breaking") == nil)
    }

    @Test("Import z pliku przez TextImporter rozpoznaje SongSelect po treści i rozszerzeniu")
    func importFromFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("songselect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let txt = directory.appendingPathComponent("morning.txt")
        try lyricsText.write(to: txt, atomically: true, encoding: .utf8)
        let pro = directory.appendingPathComponent("morning.pro")
        try "{title: Morning Light}\n[G]Morning".write(to: pro, atomically: true, encoding: .utf8)

        #expect(TextImporter.importFromURL(txt).first?.ccliNumber == "9999001")
        #expect(TextImporter.importFromURL(pro).first?.title == "Morning Light")
    }
}
