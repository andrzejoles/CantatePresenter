import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S8: logo i teksty planszy wstawiane w pamięci

@Suite("StandbyRenderer (S8)")
struct StandbyRendererTests {
    private let texts = StandbyRenderer.Texts(
        version: "Version 2.0",
        ready: "READY FOR PROJECTION • WAITING",
        credits: "Author: Andrzej Oles"
    )

    @Test("Logo wstawiane w znacznik <!--LOGO-->")
    func logoIntoMarker() {
        let html = "<body><div class=\"logo-wrapper\"><!--LOGO--></div></body>"
        let result = StandbyRenderer.render(html: html, logoSVG: "<svg id=\"nowe\"/>", texts: texts)
        #expect(result.contains("<div class=\"logo-wrapper\"><svg id=\"nowe\"/></div>"))
        #expect(!result.contains("<!--LOGO-->"))
    }

    @Test("Stary plik bez znacznika: podmieniana zawartość logo-wrapper")
    func logoIntoLegacyWrapper() {
        let html = "<body><div class=\"logo-wrapper\">\n<svg id=\"stare\"></svg>\n</div><h1>Tytuł</h1></body>"
        let result = StandbyRenderer.render(html: html, logoSVG: "<svg id=\"nowe\"/>", texts: texts)
        #expect(result.contains("<svg id=\"nowe\"/>"))
        #expect(!result.contains("stare"))
        #expect(result.contains("<h1>Tytuł</h1>"))
    }

    @Test("Znaki $ i \\ w SVG nie psują planszy (dawniej szablon regex)")
    func specialCharactersInSVG() {
        let svg = #"<svg><text>$1 \1 $0 \\ cena 5$</text></svg>"#
        let html = "<body><div class=\"logo-wrapper\"><!--LOGO--></div></body>"
        #expect(StandbyRenderer.render(html: html, logoSVG: svg, texts: texts).contains(svg))
    }

    @Test("Wersja i tekst gotowości w wybranym języku, autor dopisany")
    func textsLocalized() {
        let html = "<body><span>Wersja 1.0.0</span><div>GOTOWY DO PROJEKCJI • OCZEKIWANIE NA PREZENTACJĘ</div></body>"
        let result = StandbyRenderer.render(html: html, logoSVG: "", texts: texts)
        #expect(result.contains("<span>Version 2.0</span>"))
        #expect(result.contains("READY FOR PROJECTION • WAITING"))
        #expect(result.contains("Author: Andrzej Oles"))
    }

    @Test("Domyślny szablon z repozytorium ma znacznik logo")
    func defaultTemplateHasMarker() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/standby.html")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("<!--LOGO-->"))
    }

    @MainActor
    @Test("Zmiana logo nie zapisuje pliku planszy")
    func updateActiveLogoDoesNotWriteFile() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("<body><div class=\"logo-wrapper\"><svg/></div></body>", to: "standby.html")
        let before = try dir.contents(of: "standby.html")
        let store = DataStore(dataDirectory: dir.url)

        store.updateActiveLogo(id: "equipes_notre_dame")

        #expect(try dir.contents(of: "standby.html") == before)
        #expect(store.settings.activeLogoId == "equipes_notre_dame")
    }
}

@Suite("Powiększenie planszy")
struct StandbyZoomTests {
    @Test("Plansza rośnie z szerokością ekranu: na 1920 px dwa razy większa")
    func zoomFollowsWidth() {
        #expect(StandbyZoom.factor(forWidth: 1920) == 2.0)
        #expect(StandbyZoom.factor(forWidth: 960) == 1.0)
        #expect(StandbyZoom.factor(forWidth: 3840) == 4.0)
        #expect(StandbyZoom.factor(forWidth: 120) == 0.3)
    }
}
