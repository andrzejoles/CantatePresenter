import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Autor na planszy startowej

@Suite("Plansza startowa: autor")
struct StandbyCreditsTests {
    private let credits = "Autor: Andrzej Oles · we współpracy z Claude (Anthropic)"

    @Test("Autor dopisany raz, przed </body>")
    func injectsBeforeBody() {
        let html = "<html><body><h1>CantatePresenter</h1>\n</body></html>"
        let result = StandbyCredits.inject(into: html, credits: credits)

        #expect(result.components(separatedBy: "Andrzej Oles").count == 2)
        #expect(result.range(of: "Andrzej Oles")!.lowerBound < result.range(of: "</body>")!.lowerBound)
        #expect(result.contains("class=\"cantate-credits\""))
    }

    @Test("Plansza, która już ma autora, zostaje bez zmian")
    func skipsWhenPresent() {
        let html = "<html><body><p>Andrzej Oles</p></body></html>"
        #expect(StandbyCredits.inject(into: html, credits: credits) == html)
    }

    @Test("Plik bez </body> i znaki specjalne HTML")
    func noBodyAndEscaping() {
        let result = StandbyCredits.inject(into: "<h1>Plansza</h1>", credits: "A & B <C>")
        #expect(result.hasSuffix("A &amp; B &lt;C&gt;</div>"))
    }

    @Test("Domyślna plansza z repozytorium dostaje autora")
    func defaultStandby() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CantatePresenterCore/Resources/standby.html")
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(StandbyCredits.inject(into: html, credits: credits).contains("Andrzej Oles"))
    }
}

// MARK: - N9: logo END jako zasób

@Suite("Logo END z zasobów (N9)")
struct ENDLogoAssetTests {
    @Test("Logo wczytuje się z zasobów jako poprawny PNG")
    func loadsPNG() throws {
        let data = try #require(Data(base64Encoded: ENDLogoAsset.base64PNG))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 10_000)
    }
}
