import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N5: XML przez parser, tonacja z deserializera

@Suite("Import Holyrics: XML i tonacja (N5)")
struct HolyricsXMLTests {
    @Test("XML: encje i CDATA dekodowane, kilka pieśni")
    func xmlEntitiesAndCData() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <songs>
          <song><title>Ty i ja &amp; my</title><author>Jan &lt;Kowalski&gt;</author><key>D</key>
            <lyrics><![CDATA[Pierwsza linia & druga

        Refren <cicho>]]></lyrics></song>
          <music><nome>Grandioso És Tu</nome><artista>Stuart K. Hine</artista><tom>G</tom><letra>Senhor meu Deus</letra></music>
        </songs>
        """
        let songs = HolyricsImporter.parseHolyricsContent(xml, fallbackTitle: "plik")

        #expect(songs.map(\.title) == ["Ty i ja & my", "Grandioso És Tu"])
        #expect(songs[0].author == "Jan <Kowalski>")
        #expect(songs[0].key == "D")
        #expect(songs[0].rawLyrics.contains("Pierwsza linia & druga"))
        #expect(songs[0].rawLyrics.contains("Refren <cicho>"))
        #expect(songs[1].key == "G")
    }

    @Test("Pojedyncza pieśń bez elementu song: tytuł z nazwy pliku, gdy brak tytułu")
    func singleSongWithoutWrapper() {
        let songs = HolyricsImporter.parseHolyricsContent("<?xml version=\"1.0\"?><lyrics>Tylko tekst &amp; nic więcej</lyrics>", fallbackTitle: "Moja pieśń")
        #expect(songs.map(\.title) == ["Moja pieśń"])
        #expect(songs.first?.rawLyrics == "Tylko tekst & nic więcej")
    }

    @Test("Uszkodzony XML nie wywraca importu")
    func malformedXML() {
        _ = HolyricsImporter.parseHolyricsContent("<?xml version=\"1.0\"?><song><title>Bez końca", fallbackTitle: "x")
    }
}
