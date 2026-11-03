import Foundation
import Testing
import WebKit
@testable import CantatePresenterCore

// MARK: - Śpiewnik Wywroty: tekst i chwyty z wyświetlonej strony

@Suite("Śpiewnik Wywroty: odczyt opracowania")
struct WywrotaParserTests {
    /// Sztuczne opracowanie w układzie strony serwisu (`.interpretation-content`).
    private func fixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/wywrota-song.html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Tekst: zwrotki numerowane dostają nagłówek, nienumerowane i „Ref.” są refrenem, wstęp z samymi chwytami pominięty")
    func lyrics() throws {
        let song = WywrotaParser.song(contentHTML: try fixture(), title: " Idzie wiosna ", url: "https://spiewnik.wywrota.pl/x/y")

        #expect(song.title == "Idzie wiosna")
        #expect(song.lyrics == """
        [Zwrotka 1]
        Idzie wiosna przez "łąki"
        I śpiewa nam

        [Refren]
        Chwała, chwała
        Tobie Panie

        [Zwrotka 2]
        Druga zwrotka & koniec

        [Refren]
        Chwała na końcu
        """)
    }

    @Test("Chwyty nad tekstem w kolumnach, z przyrostkiem (A7), także po usuniętym numerze zwrotki")
    func chordSheet() throws {
        let song = WywrotaParser.song(contentHTML: try fixture(), title: "", url: "")

        #expect(song.chords == """
        [Zwrotka 1]
        D        G
        Idzie wiosna przez "łąki"
          A7        D
        I śpiewa nam

        [Refren]
        G       D
        Chwała, chwała
              e    A
        Tobie Panie

        D G A

        [Zwrotka 2]
        D
        Druga zwrotka & koniec

        [Refren]
        G
        Chwała na końcu
        """)
    }

    @Test("Wynik daje slajdy i sekcje, które rozumie reszta aplikacji")
    func slidesAndMusicians() throws {
        let song = WywrotaParser.song(contentHTML: try fixture(), title: "", url: "")
        let slides = Song.parseLyrics(song.lyrics)

        #expect(slides.map(\.type) == [.verse, .chorus, .verse, .chorus])
        #expect(slides.map(\.number) == [1, 1, 2, 2])
        let refrain = try #require(slides.dropFirst().first)
        let lines = ChordSheet.lines(for: refrain, sheet: song.chords, semitones: 0).lines
        #expect(lines.first?.chords?.split(separator: " ") == ["G", "D"])
    }

    @Test("Opracowanie bez chwytów: sam tekst, arkusz chwytów pusty; bez numerów nic nie jest refrenem")
    func withoutChords() {
        let song = WywrotaParser.song(contentHTML: "Pierwsza linia<br>Druga<br><br>Trzecia<br>", title: "", url: "")
        #expect(song.chords == nil)
        #expect(song.lyrics == "Pierwsza linia\nDruga\n\nTrzecia")
    }

    @Test("Encje HTML, także liczbowe")
    func entities() {
        #expect(WywrotaParser.decodeEntities("a &amp; b &#261;&#x15B; &lt;x&gt; &bogus; &") == "a & b ąś <x> &bogus; &")
    }

    @Test("Nachodzące chwyty rozdziela spacja")
    func overlappingChords() {
        #expect(WywrotaParser.chordLine([(0, "Cmaj7"), (2, "G")]) == "Cmaj7 G")
    }

    @Test("Przeglądarka w aplikacji otwiera tylko adresy serwisu")
    func hosts() {
        #expect(WywrotaParser.isWywrotaHost("spiewnik.wywrota.pl"))
        #expect(WywrotaParser.isWywrotaHost("www.wywrota.pl"))
        #expect(!WywrotaParser.isWywrotaHost("wywrota.pl.example.com"))
        #expect(!WywrotaParser.isWywrotaHost("evilwywrota.pl"))
        #expect(!WywrotaParser.isWywrotaHost(nil))
        #expect(WywrotaParser.searchURL(for: "Abba Ojcze & co")?.absoluteString == "https://spiewnik.wywrota.pl/search?q=Abba%20Ojcze%20%26%20co")
    }

    @Test("Wynik skryptu strony (JSON) dekoduje się do Page")
    func pageJSON() throws {
        let json = #"{"html":"<br>","title":"T","truncated":true}"#
        let page = try JSONDecoder().decode(WywrotaParser.Page.self, from: Data(json.utf8))
        #expect(page == WywrotaParser.Page(html: "<br>", title: "T", truncated: true))
    }
}

// MARK: - Czysty widok (bez reklam)

@MainActor
@Suite("Śpiewnik Wywroty: czysty widok")
struct WywrotaCleanViewTests {
    @Test("Reguły to poprawny JSON i kompilują się w WebKit")
    func rulesCompile() async throws {
        let object = try JSONSerialization.jsonObject(with: Data(WywrotaCleanView.encodedRules.utf8))
        let rules = try #require(object as? [[String: Any]])
        #expect(rules.count == WywrotaCleanView.blockedHosts.count + 1)

        // Magazyn w katalogu tymczasowym, nie domyślny w ~/Library/WebKit.
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = WKContentRuleListStore(url: dir.url)
        let compiled: Bool = await withCheckedContinuation { continuation in
            WywrotaCleanView.compile(in: store) { continuation.resume(returning: $0 != nil) }
        }
        #expect(compiled)
    }

    @Test("Blokowane są adresy reklam z subdomenami, a strony serwisu i logowanie Google nie")
    func filters() throws {
        let filters = try WywrotaCleanView.blockedHosts.map { try NSRegularExpression(pattern: WywrotaCleanView.urlFilter(forHost: $0)) }
        func blocked(_ url: String) -> Bool {
            filters.contains { $0.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        }
        #expect(blocked("https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=x"))
        #expect(blocked("https://www.googletagmanager.com/gtag/js?id=G-1"))
        #expect(blocked("https://fundingchoicesmessages.google.com/i/pub?ers=1"))
        #expect(blocked("https://doubleclick.net:443/x"))
        #expect(!blocked("https://spiewnik.wywrota.pl/piosenki-religijne/abba-ojcze"))
        #expect(!blocked("https://accounts.google.com/gsi/client"))
        #expect(!blocked("https://example.com/?u=googlesyndication.com/"))
    }
}
