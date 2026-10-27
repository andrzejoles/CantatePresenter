import Foundation
import Testing
import WebKit
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
            .appendingPathComponent("Sources/CantatePresenterCore/Resources/standby.html")
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

// MARK: - R4-37: plansza z zegarem także na świeżej instalacji

@Suite("Szablon planszy (R4-37)")
struct StandbyTemplateTests {
    @Test("Szablon z zegarem i tekstem gotowości jest zasobem pakietu")
    func bundledTemplateHasClock() throws {
        let url = try #require(StandbyTemplate.bundledURL)
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains(StandbyRenderer.logoMarker))
        #expect(html.contains("id=\"clock\""))
        #expect(html.contains(StandbyRenderer.defaultReadyText))
    }

    @Test("Świeża instalacja (brak standby.html w danych): szablon z pakietu, nie zastępczy")
    func freshInstallUsesBundledTemplate() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let url = StandbyTemplate.url(customPath: "", dataFile: dir.file("standby.html"))
        #expect(url == StandbyTemplate.bundledURL)
    }

    @Test("Kolejność: własny plik, plik w katalogu danych, szablon z pakietu")
    func resolutionOrder() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        try dir.write("<html>dane</html>", to: "standby.html")
        try dir.write("<html>własny</html>", to: "custom.html")
        let dataFile = dir.file("standby.html")

        #expect(StandbyTemplate.url(customPath: "", dataFile: dataFile) == dataFile)
        #expect(StandbyTemplate.url(customPath: dir.file("custom.html").path, dataFile: dataFile) == dir.file("custom.html"))
        #expect(StandbyTemplate.url(customPath: dir.file("brak.html").path, dataFile: dataFile) == dataFile)
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

// MARK: - R7-02: plansza bez dostępu do plików i bez połączeń

@Suite("Plansza: izolacja skryptów (R7-02)")
struct StandbyIsolationTests {
    private let texts = StandbyRenderer.Texts(version: "Wersja 1", ready: "R", credits: "C")

    @Test("CSP na samym początku dokumentu (po doctype), bez połączeń i ramek")
    func contentSecurityPolicyFirst() throws {
        let html = "<!DOCTYPE html>\n<html><head><script>fetch('https://x')</script></head><body><!--LOGO--></body></html>"
        let result = StandbyRenderer.render(html: html, logoSVG: "<svg/>", texts: texts)
        #expect(result.hasPrefix("<!DOCTYPE html>\n<meta http-equiv=\"Content-Security-Policy\""))
        let csp = StandbyRenderer.contentSecurityPolicy
        #expect(csp.contains("default-src 'none'"))
        #expect(!csp.contains("connect-src"))
        #expect(!csp.contains("http"))
        #expect(csp.contains("form-action 'none'") && csp.contains("base-uri 'none'"))
        // Skrypt z szablonu stoi za CSP, więc ona go obejmuje.
        let meta = try #require(result.range(of: "Content-Security-Policy"))
        let script = try #require(result.range(of: "<script>"))
        #expect(meta.lowerBound < script.lowerBound)
    }

    @Test("Szablon bez doctype albo ze skryptem przed <html>: CSP i tak pierwsza")
    func contentSecurityPolicyWithoutDoctype() {
        let result = StandbyRenderer.render(html: "  <script>x()</script><html><body></body></html>", logoSVG: "", texts: texts)
        #expect(result.hasPrefix("<meta http-equiv=\"Content-Security-Policy\""))
    }

    @MainActor
    @Test("WKWebView planszy bez allowFileAccessFromFileURLs")
    func noFileAccessFromFileURLs() {
        let config = StandbyWebView.makeConfiguration()
        #expect((config.preferences.value(forKey: "allowFileAccessFromFileURLs") as? Bool) == false)
        #expect(!config.preferences.javaScriptCanOpenWindowsAutomatically)
    }

    @Test("Nawigacja: tylko wczytanie zlecone przez aplikację, potem żadnej")
    func navigationPolicy() {
        var policy = StandbyNavigationPolicy()
        let base = URL(fileURLWithPath: "/tmp/plansza/", isDirectory: true)
        let blank = URL(string: "about:blank")
        var decisions: [Bool] = []
        decisions.append(policy.allow(url: base, isMainFrame: true))

        policy.expectLoad(baseURL: base)
        decisions.append(policy.allow(url: URL(string: "https://example.com/?d=1"), isMainFrame: true))
        decisions.append(policy.allow(url: base, isMainFrame: true))
        decisions.append(policy.allow(url: base, isMainFrame: true))

        policy.expectLoad(baseURL: nil)
        decisions.append(policy.allow(url: blank, isMainFrame: false))
        decisions.append(policy.allow(url: blank, isMainFrame: true))
        decisions.append(policy.allow(url: blank, isMainFrame: true))

        #expect(decisions == [false, false, true, false, false, true, false])
    }
}
