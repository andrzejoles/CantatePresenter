import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S6: wykrywanie kodowania polskich plików tekstowych

@Suite("TextImporter: kodowanie (S6)")
struct TextEncodingTests {
    private static let polish = "Zażółć gęślą jaźń\nĄĆĘŁŃÓŚŹŻ ąćęłńóśźż\nPan kiedyś stanął nad brzegiem, szukał ludzi"

    private static func encoding(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }

    @Test("Polski tekst w każdym popularnym kodowaniu wraca bez zmian", arguments: [
        ("UTF-8", String.Encoding.utf8),
        ("Windows-1250", encoding(.windowsLatin2)),
        ("ISO-8859-2", encoding(.isoLatin2)),
        ("Mac Central European", encoding(.macCentralEurRoman))
    ])
    func decodesPolishText(name: String, encoding: String.Encoding) throws {
        let data = try #require(Self.polish.data(using: encoding), "\(name)")

        #expect(TextImporter.decodeText(data) == Self.polish, "\(name)")
    }

    @Test("Krótki tekst ISO-8859-2 z jedną literą „ś” nie jest czytany jako Windows-1250")
    func shortIsoLatin2() throws {
        let data = try #require("Gdzie jest Twój dom, ś".data(using: Self.encoding(.isoLatin2)))

        #expect(TextImporter.decodeText(data) == "Gdzie jest Twój dom, ś")
    }

    @Test("UTF-8 z BOM: znacznik jest usuwany")
    func utf8WithBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("Barka".utf8)

        #expect(TextImporter.decodeText(data) == "Barka")
    }

    @Test("Zwykły ASCII")
    func plainASCII() {
        #expect(TextImporter.decodeText(Data("Amazing Grace".utf8)) == "Amazing Grace")
    }

    @Test("Tekst ukraiński i rosyjski w Windows-1251 wraca cyrylicą (R6-12)", arguments: [
        "Боже великий, єдиний, нам Україну храни",
        "Боже великий",
        "Слава Отцю, і Сину, і Святому Духові",
        "Христос воскрес! Воистину воскрес!"
    ])
    func cyrillicWindows1251(text: String) throws {
        let data = try #require(text.data(using: .windowsCP1251))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Krótkie polskie teksty Windows-1250 i ISO-8859-2 nie są czytane jako cyrylica (R6-12)", arguments: [
        "Bóg się rodzi", "Zażółć gęślą jaźń", "Ś", "żółw", "Łódź", "ąę", "Święty, Święty, Święty",
        "Gdzie jest Twój dom, ś", "Kto się w opiekę"
    ])
    func shortPolishIsNotCyrillic(text: String) throws {
        for encoding in [Self.encoding(.windowsLatin2), Self.encoding(.isoLatin2)] {
            let data = try #require(text.data(using: encoding))
            #expect(TextImporter.decodeText(data) == text, "\(text)")
        }
    }

    @Test("Francuski i niemiecki tekst Windows-1252 nie staje się cyrylicą (R6-12)", arguments: [
        "Être prêt pour la fête, même là où tu vas.\nÀ toi la gloire, ô Ressuscité",
        "Großer Gott, wir loben dich. Herr, wir preisen deine Stärke."
    ])
    func westernEuropean(text: String) throws {
        let data = try #require(text.data(using: .windowsCP1252))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Krótki tekst Windows-1252 z samodzielnym „é”, „à”, „ô” nie staje się cyrylicą (R10-02)", arguments: [
        "Gloire à Dieu", "Gloire à Dieu, gloire à Dieu",
        "Gloire à Dieu\n\nGloire à Dieu, gloire à Dieu\nPaix sur la terre aux hommes qu'il aime",
        "à toi la gloire", "Je t'exalte, ô Roi", "Ô Seigneur",
        "Ele é Senhor, ele é Rei", "Santo é o Senhor", "É o Senhor", "Aleluia! É Ele", "Deus é fiel"
    ])
    func westernStandaloneAccentsAreNotCyrillic(text: String) throws {
        let data = try #require(text.data(using: .windowsCP1252))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Niemiecki tekst Windows-1252 z „ü”, „ö” nie jest czytany jako Mac Central European (R10-06)", arguments: [
        "Herr, für dich will ich singen", "Für Elise", "Müde bin ich, geh zur Ruh", "Grüß Gott",
        "Jesus, zu dir ruf ich\nDu bist für uns gestorben\nWir loben dich mit fröhlichem Herzen",
        "¡Aleluya!"
    ])
    func germanUmlautsAreNotMacCentralEuropean(text: String) throws {
        let data = try #require(text.data(using: .windowsCP1252))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Portugalskie „ão” w Windows-1252 nie staje się „ăo” ani „„o” (R10-06)", arguments: [
        "Coração", "Ação de graças", "Não temas", "Mãe de Deus", "Santo, Santo, Santo é o Senhor\nDeus do universo"
    ])
    func portugueseTilde(text: String) throws {
        let data = try #require(text.data(using: .windowsCP1252))
        #expect(TextImporter.decodeText(data) == text)
    }

    @Test("Krótkie polskie linie Windows-1250 z „cudzysłowem” nie są czytane jako Mac Central European (R10-06)", arguments: [
        "„Jezus\" i „Syn Najwyższego\".", "„Amen\" jak Maryja,", "„Barka”", "Śpiewaj „Alleluja”",
        "Ref. Śpiewaj: „Hosanna\", śpiewaj: „Hosanna\",", "On teraz ŻYWYM BOGIEM naszym jest. Alleluja!",
        "Ja Tobie ufam i nie pytam „jak\"?"
    ])
    func polishQuotesAreNotMacCentralEuropean(text: String) throws {
        for encoding in [Self.encoding(.windowsLatin2), Self.encoding(.isoLatin2)] {
            guard let data = text.data(using: encoding) else { continue }
            #expect(TextImporter.decodeText(data) == text, "\(text)")
        }
    }
}

// MARK: - Korpus: przykładowa biblioteka w kodowaniach jednobajtowych (R10-02, R10-06)

@Suite("TextImporter: kodowanie przykładowej biblioteki (R10-02, R10-06)")
struct TextEncodingCorpusTests {
    /// Przykładowa biblioteka z repozytorium (`data/songs.json`, N9), nie prawdziwy katalog danych.
    private static let songsFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("data/songs.json")

    private static func encoding(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }

    /// Tytuły i całe teksty oraz osobno pojedyncze linie (krótki tekst jest najtrudniejszy).
    private static func corpus() throws -> (whole: [String], lines: [String]) {
        let objects = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: songsFile)) as? [[String: Any]])
        var whole: [String] = []
        var lines: [String] = []
        for object in objects {
            if let title = object["title"] as? String { whole.append(title) }
            if let lyrics = object["rawLyrics"] as? String {
                whole.append(lyrics)
                lines.append(contentsOf: lyrics.components(separatedBy: "\n").filter { !$0.isEmpty })
            }
        }
        // „Seńor” to w przykładach już zepsute hiszpańskie „Señor”; dekoder słusznie czyta je jako hiszpańskie.
        let isUsable: (String) -> Bool = { !$0.contains("Seńor") }
        return (whole.filter(isUsable), lines.filter(isUsable))
    }

    /// Teksty, które w danym kodowaniu mają bajty spoza ASCII, i te z nich, które wracają inaczej.
    private static func misdecoded(_ texts: [String], in encoding: String.Encoding) -> (total: Int, wrong: [String]) {
        var total = 0
        var wrong: [String] = []
        for text in texts {
            guard let data = text.data(using: encoding), data.contains(where: { $0 >= 0x80 }) else { continue }
            total += 1
            let decoded = TextImporter.decodeText(data)
            if decoded != PolishEncodingService.shared.repairMojibake(text) {
                wrong.append("\(text) → \(decoded ?? "nil")")
            }
        }
        return (total, wrong)
    }

    private static let foreignLetters = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)
        .union(CharacterSet(charactersIn: "ĀāĒēĖėĢģĪīĮįĶķĻļŅņŌōŖŗŪūŲų"))

    @Test("Windows-1250, ISO-8859-2 i Windows-1252: każdy tytuł, tekst i linia wraca bez zmian", arguments: [
        ("Windows-1250", encoding(.windowsLatin2)),
        ("ISO-8859-2", encoding(.isoLatin2)),
        ("Windows-1252", String.Encoding.windowsCP1252)
    ])
    func centralAndWesternEncodings(name: String, encoding: String.Encoding) throws {
        let (whole, lines) = try Self.corpus()
        for texts in [whole, lines] {
            let result = Self.misdecoded(texts, in: encoding)
            #expect(result.total > 0, "\(name)")
            #expect(result.wrong.isEmpty, "\(name): \(result.wrong.prefix(5))")
        }
    }

    /// W Mac Central European „ś” ma ten sam bajt co „ć” w Windows-1250 i ISO-8859-2, więc krótki tekst z jedną
    /// taką literą jest nierozstrzygalny. Pilnujemy, żeby błędów nie przybyło (przed R10-06 było ich więcej, np. „ăAmen”)
    /// i żeby nigdy nie wyszła cyrylica ani litery bałtyckie.
    @Test("Mac Central European: bez cyrylicy i liter bałtyckich, błędów nie przybywa")
    func macCentralEuropean() throws {
        let (whole, lines) = try Self.corpus()
        let encoding = Self.encoding(.macCentralEurRoman)
        for (texts, limit) in [(whole, 52), (lines, 266)] {
            let result = Self.misdecoded(texts, in: encoding)
            #expect(result.total > 0)
            #expect(result.wrong.count <= limit, "\(result.wrong.count): \(result.wrong.prefix(5))")
            let foreign = result.wrong.filter { $0.unicodeScalars.contains(where: Self.foreignLetters.contains) }
            #expect(foreign.isEmpty, "\(foreign.prefix(5))")
        }
    }
}
