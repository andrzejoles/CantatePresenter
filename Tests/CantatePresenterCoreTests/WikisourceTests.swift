import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S9: teksty z Wikiźródeł

@Suite("Wikiźródła (S9)")
struct WikisourceTests {
    /// Uproszczony HTML jak z action=parse dla strony ze „Śpiewnika kościelnego” (zwrotka przecięta końcem strony skanu).
    private let html = """
    <div class="mw-parser-output"><table class="infobox ws-noexport dttable"><tr><th>Tytuł</th><td>Boże z twoich rąk żyjemy</td></tr></table>
    <div class="prp-pages-output"><span class="ws-pagenum ws-noexport">[278]</span>
    <p class="center">PIEŚŃ XVII.</p><p>Pod czas pracy w polu.<sup class="reference">[1]</sup></p>
    <div class="poem"><p>Boże z twoich rąk żyjemy,<br>Choć naszemi pracujemy;<br>Z ciebie plenność miewa rola,<br>My zbieramy z twego pola.</p>
    <p>Wszystko cię mój Boże chwali:<br>Aleśmy i to poznali,<br>Że najmilszą ci się zdała,<br>Pracującej ręki chwała.</p>
    <p>Co rządzisz ziemią i niebem,<br>Opatrz dzieci twoje chlebem;</p></div>
    <span class="ws-pagenum ws-noexport">[279]</span>
    <div class="poem"><p>Ty nam daj urodzaj złoty,<br>My ci dajem trud i poty.</p>
    <p>Kiedyś przyjdziem na godzinę<br>Gdy kończąc ziemską gościnę,<br>Z Łazarzem po naszym zgonie,<br>Odpoczniemy na twem łonie.</p></div></div>
    <div class="licencja">Tekst lub tłumaczenie polskie jest własnością publiczną (public domain), ponieważ prawa autorskie do niego wygasły.</div></div>
    """

    @Test("Tekst pieśni z elementów poem, bez numerów stron i przypisów; przecięta zwrotka sklejona")
    func extractsLyrics() {
        let lyrics = WikisourceParser.lyrics(fromHTML: html)
        let stanzas = lyrics.components(separatedBy: "\n\n")

        #expect(stanzas.count == 4)
        #expect(stanzas[0].hasPrefix("Boże z twoich rąk żyjemy,\nChoć naszemi pracujemy;"))
        #expect(stanzas[2] == "Co rządzisz ziemią i niebem,\nOpatrz dzieci twoje chlebem;\nTy nam daj urodzaj złoty,\nMy ci dajem trud i poty.")
        #expect(!lyrics.contains("[278]"))
        #expect(!lyrics.contains("PIEŚŃ"))
    }

    @Test("Strona bez tekstu pieśni (np. ujednoznacznienie) daje pusty wynik")
    func noPoem() {
        #expect(WikisourceParser.lyrics(fromHTML: "<div><ul><li>Kiedy ranne wstają zorze – wiersz</li></ul></div>").isEmpty)
    }

    @Test("Licencja: domena publiczna albo CC BY-SA")
    func license() {
        #expect(WikisourceParser.license(fromHTML: html) == .publicDomain)
        #expect(WikisourceParser.license(fromHTML: "<div>Creative Commons Attribution-ShareAlike</div>") == .ccBySA)
    }

    @Test("Autor z szablonu Dane tekstu, z odnośnika lub zwykły")
    func author() {
        #expect(WikisourceParser.author(fromWikitext: "{{Dane tekstu\n|autor=[[Autor:Franciszek Karpiński|Franciszek Karpiński]]\n|tytuł=X\n}}") == "Franciszek Karpiński")
        #expect(WikisourceParser.author(fromWikitext: "{{Dane tekstu\n|autor=Adam Mickiewicz\n}}") == "Adam Mickiewicz")
        #expect(WikisourceParser.author(fromWikitext: "{{Dane tekstu\n|tytuł=X\n}}") == "")
    }

    @Test("Tytuł wyniku z nazwy strony: bez nazwy zbioru i nawiasu z wydaniem")
    func shortTitle() {
        #expect(OnlineSearchService.shortTitle(fromPageTitle: "Ołtarzyk polski katolickiego nabożeństwa/Kiedy ranne wstają zorze") == "Kiedy ranne wstają zorze")
        #expect(OnlineSearchService.shortTitle(fromPageTitle: "Boże coś Polskę (red. Derdowski, ok. 1890)") == "Boże coś Polskę")
    }

    @Test("Adresy API dla języka wyszukiwania")
    func endpoints() {
        #expect(WikisourceParser.host(forLanguage: "pl") == "pl.wikisource.org")
        #expect(WikisourceParser.host(forLanguage: "uk") == "uk.wikisource.org")
        #expect(WikisourceParser.host(forLanguage: "all") == "pl.wikisource.org")
        #expect(WikisourceParser.pageURL(title: "Śpiewnik kościelny/Boże z twoich rąk żyjemy", language: "pl").absoluteString
                == "https://pl.wikisource.org/wiki/%C5%9Apiewnik_ko%C5%9Bcielny/Bo%C5%BCe_z_twoich_r%C4%85k_%C5%BCyjemy")
    }

    @Test("Pieśń ma pola źródła, praw autorskich i numeru CCLI, zgodne wstecz")
    func songSourceFields() throws {
        var song = Song(title: "T", rawLyrics: "A")
        song.source = "Wikiźródła"
        song.copyright = "Domena publiczna"
        song.ccliNumber = "22025"
        let decoded = try JSONFileStore.makeDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        #expect(decoded.source == "Wikiźródła")
        #expect(decoded.ccliNumber == "22025")
        let old = try JSONFileStore.makeDecoder().decode(Song.self, from: Data(#"{"title":"Stara","rawLyrics":"x"}"#.utf8))
        #expect(old.source == nil && old.copyright == nil && old.ccliNumber == nil)
        let numeric = try JSONFileStore.makeDecoder().decode(Song.self, from: Data(#"{"title":"T","ccliNumber":22025}"#.utf8))
        #expect(numeric.ccliNumber == "22025")
    }
}
