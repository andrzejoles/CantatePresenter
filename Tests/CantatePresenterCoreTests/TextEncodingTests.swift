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
}
