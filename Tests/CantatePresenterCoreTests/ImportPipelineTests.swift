import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Import: kodowanie, JSON, archiwa, wzbogacanie (R2-02 … R2-07, R2-18, R2-20, R2-21)

@Suite("Import: kodowanie znaków (R2-02, R2-18)")
struct ImportEncodingTests {
    private static func cp(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }

    @Test("Znaki innych języków w UTF-8 nie są „naprawiane” na polskie (R2-02)")
    func keepsNonPolishLetters() {
        let text = "Bendigo al Señor, ¿quién? être, Æterne, £5, Ñandú, mercê"
        #expect(TextImporter.decodeText(Data(text.utf8)) == text)
        #expect(PolishEncodingService.shared.repairMojibake(text) == text)
    }

    @Test("Prawdziwe mojibake UTF-8 czytanego jako Windows-1252 jest dalej naprawiane")
    func repairsRealMojibake() {
        #expect(PolishEncodingService.shared.repairMojibake("Å‚Ä…ka i Å›wiÄ™to") == "łąka i święto")
    }

    @Test("Wzbogacanie nie zmienia hiszpańskiego tekstu (R2-02)")
    func enrichmentKeepsSpanish() {
        let result = SongEnrichmentService().enrich(song: Song(title: "Señor", rawLyrics: "Bendigo al Señor\n¿Quién como Él?"))
        #expect(result.enrichedSong.title == "Señor")
        #expect(result.enrichedSong.rawLyrics == "Bendigo al Señor\n¿Quién como Él?")
    }

    @Test("UTF-16 z BOM (Notatnik „Unicode”) (R2-18)")
    func decodesUTF16WithBOM() throws {
        let text = "Zażółć gęślą jaźń\nBarka"
        let little = Data([0xFF, 0xFE]) + (try #require(text.data(using: .utf16LittleEndian)))
        let big = Data([0xFE, 0xFF]) + (try #require(text.data(using: .utf16BigEndian)))
        #expect(TextImporter.decodeText(little) == text)
        #expect(TextImporter.decodeText(big) == text)
    }

    @Test("Hiszpański tekst w Windows-1252 nie jest czytany jako Windows-1250 (R2-18)")
    func decodesWesternCP1252() throws {
        let text = "¿Quién es el Señor?\nAño nuevo, niño, mañana"
        let data = try #require(text.data(using: .windowsCP1252))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Polski tekst w Windows-1250 dalej wygrywa z Windows-1252")
    func polishCP1250StillWins() throws {
        let text = "Pan kiedyś stanął nad brzegiem, szukał ludzi gotowych pójść za Nim. Żłóbek, źródło, łąka."
        let data = try #require(text.data(using: Self.cp(.windowsLatin2)))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("OpenLyrics: <br/> to nowa linia, <verse> to nowy slajd (R2-18)")
    func openLyricsLineBreaks() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.9">
          <properties><titles><title>Amazing Grace</title></titles></properties>
          <lyrics>
            <verse name="v1">
              <lines>
                Amazing grace how sweet the sound<br/>
                That saved a wretch like me
              </lines>
            </verse>
            <verse name="v2">
              <lines>Twas grace that taught<br/>my heart to fear</lines>
            </verse>
          </lyrics>
        </song>
        """
        let songs = HolyricsImporter.parseHolyricsContent(xml, fallbackTitle: "plik")
        #expect(songs.first?.title == "Amazing Grace")
        #expect(songs.first?.rawLyrics == "Amazing grace how sweet the sound\nThat saved a wretch like me\n\nTwas grace that taught\nmy heart to fear")
    }

    @Test("XML z deklaracją ISO-8859-2 po zdekodowaniu nie jest psuty (R2-18)")
    func xmlDeclarationEncoding() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"ISO-8859-2\"?><song><title>Gdy śliczna Panna</title><lyrics>Żłóbek</lyrics></song>"
        let data = try #require(xml.data(using: .isoLatin2))
        let text = try #require(TextImporter.decodeText(data))
        let songs = HolyricsImporter.parseHolyricsContent(text, fallbackTitle: "plik")
        #expect(songs.first?.title == "Gdy śliczna Panna")
        #expect(songs.first?.rawLyrics == "Żłóbek")
    }
}

@Suite("Import: JSON (R2-03)")
struct ImportJSONTests {
    @Test("JSON z innego programu (name/lyrics) daje tytuł i tekst, nie puste pieśni")
    func looseKeys() {
        let songs = TextImporter.decodeSongsFromJSON(data: Data(#"[{"name":"A","lyrics":"x y z"}]"#.utf8))
        #expect(songs.map(\.title) == ["A"])
        #expect(songs.first?.rawLyrics == "x y z")
    }

    @Test("Obiekt z listą songs")
    func wrappedSongs() {
        let songs = TextImporter.decodeSongsFromJSON(data: Data(#"{"songs":[{"title":"A","rawLyrics":"x"}]}"#.utf8))
        #expect(songs.map(\.title) == ["A"])
        #expect(songs.first?.rawLyrics == "x")
    }

    @Test("Pojedyncza pieśń Holyrics (title/lyrics) jako obiekt")
    func singleHolyricsObject() {
        let songs = TextImporter.decodeSongsFromJSON(data: Data(#"{"title":"X","artist":"Y","lyrics":"Linia"}"#.utf8))
        #expect(songs.map(\.title) == ["X"])
        #expect(songs.first?.author == "Y")
        #expect(songs.first?.rawLyrics == "Linia")
    }

    @Test("plans.json, settings.json i manifest.json nie są pieśniami")
    func nonSongFiles() {
        #expect(TextImporter.decodeSongsFromJSON(data: Data(#"[{"id":"7B1F5E3A-0000-4000-8000-000000000001","name":"Plan","items":[]}]"#.utf8)).isEmpty)
        #expect(TextImporter.decodeSongsFromJSON(data: Data(#"{"schemaVersion":1,"fontSize":40,"appLanguage":"pl"}"#.utf8)).isEmpty)
        #expect(TextImporter.decodeSongsFromJSON(data: Data(#"{"version":"1.0","songsCount":3,"includedFiles":["songs.json"]}"#.utf8)).isEmpty)
    }

    @Test("Własny eksport JSON zachowuje chwyty, CCLI, © i źródło")
    func nativeExportKeepsFields() throws {
        var song = Song(title: "Barka", author: "C. Gabarain", key: "D", rawLyrics: "Pan kiedyś stanął", chords: "D A")
        song.ccliNumber = "123"
        song.copyright = "© 1979"
        song.source = "https://example.org"
        let data = try #require(SongExporter.songsToJSONData([song]))

        let decoded = try #require(TextImporter.decodeSongsFromJSON(data: data).first)
        #expect(decoded.title == "Barka")
        #expect(decoded.chords == "D A")
        #expect(decoded.ccliNumber == "123")
        #expect(decoded.copyright == "© 1979")
        #expect(decoded.source == "https://example.org")
    }

    @Test("Folder z danymi aplikacji: tylko songs.json daje pieśni")
    func dataFolderImport() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"[{"title":"A","rawLyrics":"x"}]"#, to: "songs.json")
        try dir.write(#"[{"id":"7B1F5E3A-0000-4000-8000-000000000001","name":"Plan","items":[]}]"#, to: "plans.json")
        try dir.write(#"{"schemaVersion":1,"fontSize":40}"#, to: "settings.json")

        #expect(TextImporter.importFromURL(dir.url).map(\.title) == ["A"])
    }
}

@Suite("Import: archiwa i eksport tekstowy (R2-07, R2-21)")
struct ImportArchiveTests {
    private func zip(_ source: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", source.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func sampleSong() -> Song {
        var song = Song(title: "Barka", author: "Cesareo Gabarain", key: "D", tags: ["Oazowa"],
                        rawLyrics: "[Zwrotka 1]\nPan kiedyś stanął nad brzegiem\n\n[Refren]\nO Panie, to Ty na mnie spojrzałeś",
                        chords: "D A\nh G")
        song.ccliNumber = "1234567"
        song.copyright = "© 1979 Cesareo Gabarain"
        song.source = "https://pl.wikisource.org/wiki/Barka"
        return song
    }

    @Test("Eksport .txt i ponowny import zachowuje metadane, chwyty, ©, CCLI i źródło (R2-21)")
    func textRoundTrip() throws {
        let song = sampleSong()
        let parsed = TextImporter.parseString(rawContent: SongExporter.songToText(song))

        #expect(parsed.title == song.title)
        #expect(parsed.author == song.author)
        #expect(parsed.key == song.key)
        #expect(parsed.tags == song.tags)
        #expect(parsed.chords == song.chords)
        #expect(parsed.ccliNumber == song.ccliNumber)
        #expect(parsed.copyright == song.copyright)
        #expect(parsed.source == song.source)
        #expect(parsed.slides.map(\.text) == song.slides.map(\.text))
        #expect(!parsed.rawLyrics.contains("Chwyty"))
    }

    @Test("Spakowany eksport do folderu wraca jako te same pieśni (R2-07)")
    func zippedFolderExport() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let folder = dir.url.appendingPathComponent("eksport")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let song = sampleSong()
        _ = try SongExporter.exportSongs([song], to: folder)
        let archive = dir.file("eksport.zip")
        try zip(folder, to: archive)

        let imported = try #require(TextImporter.importFromURL(archive).first)
        #expect(imported.title == song.title)
        #expect(imported.key == song.key)
        #expect(imported.chords == song.chords)
        #expect(!imported.slides.contains { $0.text.contains("Tytuł:") || $0.text.contains("Tonacja:") })
        #expect(!imported.tags.contains("Import Holyrics"))
    }

    @Test("Spakowany eksport JSON zachowuje tekst i chwyty (R2-07)")
    func zippedJSONExport() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let folder = dir.url.appendingPathComponent("json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let song = sampleSong()
        try #require(SongExporter.songsToJSONData([song])).write(to: folder.appendingPathComponent("baza.json"))
        let archive = dir.file("baza.zip")
        try zip(folder, to: archive)

        let imported = try #require(TextImporter.importFromURL(archive).first)
        #expect(imported.rawLyrics == song.rawLyrics)
        #expect(imported.chords == song.chords)
        #expect(imported.ccliNumber == song.ccliNumber)
    }

    @Test("Znaczniki Holyrics rozpoznawane tylko przed tekstem, nie w środku pieśni (R2-07)")
    func holyricsTagsOnlyBeforeLyrics() {
        let song = HolyricsImporter.parseSingleHolyricsSong("@nome: Tytuł\nPierwsza linia\nautor: to jest tekst pieśni\nkey: też tekst", fallbackTitle: "x")
        #expect(song.title == "Tytuł")
        #expect(song.rawLyrics == "Pierwsza linia\nautor: to jest tekst pieśni\nkey: też tekst")
    }
}

@Suite("Import: chwyty w tekście (R2-20)")
struct ImportChordExtractionTests {
    @Test("[1], (3) i (ach) to nie chwyty")
    func numbersAreNotChords() {
        let result = GuitarChordsService.shared.extractChordsAndCleanLyrics("[1]\nPan jest\nAlleluja (3)\nOch (ach)")
        #expect(result.extractedChords == nil)
        #expect(result.cleanLyrics == "[1]\nPan jest\nAlleluja (3)\nOch (ach)")
    }

    @Test("Prawdziwe chwyty w nawiasach są dalej wyodrębniane")
    func realChords() {
        let result = GuitarChordsService.shared.extractChordsAndCleanLyrics("Pan kiedyś stanął nad brzegiem (D A)\n[G]Szukał ludzi")
        #expect(result.extractedChords != nil)
        #expect(result.cleanLyrics == "Pan kiedyś stanął nad brzegiem \nSzukał ludzi")
    }
}

@Suite("Import: wzbogacanie metadanych (R2-05)")
struct ImportEnrichmentTests {
    private let service = SongEnrichmentService()

    @Test("Dłuższy tytuł nie jest obcinany do znanego początku")
    func titlesAreNotTruncated() {
        for title in ["Magnificat anima mea Dominum", "Laudate Dominum omnes gentes", "Jubilate Deo omnis terra", "Gdy wpatruję się w krzyż"] {
            #expect(service.enrich(song: Song(title: title, rawLyrics: "Tekst pieśni")).enrichedSong.title == title)
        }
        #expect(service.canonicalizeTitle("magnificat") == "Magnificat")
    }

    @Test("Gloria nie staje się kolędą z powodu „Chwała na wysokości”")
    func gloriaIsNotACarol() {
        let result = service.enrich(song: Song(title: "Gloria", rawLyrics: "Chwała na wysokości Bogu, a na ziemi pokój ludziom dobrej woli"))
        #expect(result.enrichedSong.author.isEmpty)
        #expect(!result.enrichedSong.tags.contains("Kolęda"))
    }

    @Test("Krótkie, ogólne frazy (np. „Abba Ojcze”, „Zaufaj Mi”) nie przypisują autora")
    func genericPhrasesDoNotMatch() {
        for lyrics in ["Wołamy: Abba Ojcze, przyjdź", "Zaufaj Mi, mówi Pan", "Prowadź mnie Maryjo do Syna", "Śpiewajmy: Gloria in excelsis Deo"] {
            #expect(service.enrich(song: Song(title: "Inna pieśń", rawLyrics: lyrics)).enrichedSong.author.isEmpty, "\(lyrics)")
        }
    }

    @Test("Pełna fraza z tekstu dalej daje autora")
    func fullPhraseStillMatches() {
        let result = service.enrich(song: Song(title: "Nad brzegiem", rawLyrics: "Pan kiedyś stanął nad brzegiem,\nszukał ludzi gotowych pójść za Nim"))
        #expect(result.enrichedSong.author == "Cesareo Gabarain, tłum. ks. Stanisław Szmidt SDB")
    }

    @Test("Ten sam wynik przy każdym uruchomieniu (stała kolejność bazy)")
    func deterministic() {
        // Frazy dwóch różnych pieśni w jednym tekście: wygrywa zawsze ta sama.
        let lyrics = "Bóg się rodzi, moc truchleje\nCicha noc, święta noc"
        let authors = Set((0..<20).map { _ in SongEnrichmentService().enrich(song: Song(title: "Składanka", rawLyrics: lyrics)).enrichedSong.author })
        #expect(authors == ["Franciszek Karpiński (1792)"])
    }

    @Test("„Moja droga” nie staje się „Moja drogą”, a „zlobka” to „żłobka”")
    func diacriticsRestoration() {
        let encoding = PolishEncodingService.shared
        #expect(encoding.restoreTitleDiacritics(title: "Moja droga", lyrics: "Idę drogą, moja droga prowadzi").title == "Moja droga")
        #expect(encoding.restoreTitleDiacritics(title: "Moja droga", lyrics: "").title == "Moja droga")
        #expect(encoding.restoreTitleDiacritics(title: "Do zlobka", lyrics: "").title == "Do żłobka")
    }

    @Test("Zastępczy autor to stała, a jego tłumaczenia ze starszych wersji też znaczą „brak autora” (R2-11)")
    func unknownAuthorPlaceholder() {
        #expect(SongEnrichmentService.unknownAuthorPlaceholder == "Nieznany")
        for author in ["Nieznany", "Unknown", "Unbekannt", "Desconocido", "Невідомий", ""] {
            #expect(SongEnrichmentService.isUnknownAuthor(author), "\(author)")
        }
        #expect(!SongEnrichmentService.isUnknownAuthor("Jan Kowalski"))
    }

    @Test("Słowo z tekstem w dwóch wersjach (z ogonkiem i bez) nie jest zmieniane")
    func ambiguousLyricsWord() {
        let result = PolishEncodingService.shared.restoreTitleDiacritics(title: "Swieta noc", lyrics: "Święta noc, święta, swieta")
        #expect(result.title == "Swieta noc")
    }
}

@Suite("Import: nieczytelne pliki i JSON w plikach Holyrics (R6-05, R6-06)")
struct ImportFileProblemTests {
    @Test("Ucięty plik JSON jest zgłaszany jako problem (R6-05)")
    func truncatedJSON() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"[{"title":"A","rawLyrics":"x""#, to: "broken.json")
        let outcome = TextImporter.importFile(dir.file("broken.json"))
        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
        #expect(outcome.problems.first?.fileName == "broken.json")
    }

    @Test("Poprawny JSON bez pieśni (plan) jest zgłaszany jako problem (R6-05)")
    func jsonWithoutSongs() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"{"name":"Plan","items":[]}"#, to: "plan.json")
        let outcome = TextImporter.importFile(dir.file("plan.json"))
        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
    }

    @Test("Nieczytelny plik .usr jest zgłaszany jako problem (R6-05)")
    func unreadableUSR() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("[File]\nType=SongSelect Import File\n", to: "broken.usr")
        let outcome = TextImporter.importFile(dir.file("broken.usr"))
        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
    }

    @Test("Własny eksport JSON zapisany jako .mufl zachowuje tekst, chwyty i CCLI (R6-06)")
    func ownJSONAsMufl() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"[{"title":"A","rawLyrics":"x","chords":"D A","ccliNumber":"5"}]"#, to: "own.mufl")
        let outcome = TextImporter.importFile(dir.file("own.mufl"))
        let song = try #require(outcome.songs.first)
        #expect(outcome.songs.count == 1)
        #expect(song.title == "A")
        #expect(song.rawLyrics == "x")
        #expect(song.chords == "D A")
        #expect(song.ccliNumber == "5")
    }

    @Test("Plan JSON zapisany jako .hly nie jest pieśnią (R6-06)")
    func planJSONAsHly() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write(#"{"name":"Plan","items":[]}"#, to: "plan.hly")
        let outcome = TextImporter.importFile(dir.file("plan.hly"))
        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
    }

    @Test("JSON Holyrics bez tytułu: tytuł z katalogu tłumaczeń, nie wpisany na stałe (R6-06)")
    func holyricsJSONWithoutTitle() {
        let songs = HolyricsImporter.parseHolyricsContent(#"[{"lyrics":"Linia"}]"#, fallbackTitle: "plik")
        #expect(songs.map(\.rawLyrics) == ["Linia"])
        #expect(songs.first?.title == Lnow("Bez tytułu"))
    }
}
