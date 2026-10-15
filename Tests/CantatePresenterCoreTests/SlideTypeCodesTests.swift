import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - S10: stałe kody typów slajdów i numer zwrotki

@Suite("Typy slajdów jako stałe kody (S10)")
struct SlideTypeCodesTests {
    private func decodeSlide(_ json: String) throws -> SongSlide {
        try JSONFileStore.makeDecoder().decode(SongSlide.self, from: Data(json.utf8))
    }

    @Test("Stare pliki z polskimi nazwami typów nadal się wczytują", arguments: [
        ("Zwrotka", SlideType.verse), ("Refren", .chorus), ("Bridge", .bridge), ("Pre-Chorus", .preChorus),
        ("Coda", .coda), ("Przejście", .interlude), ("Intro", .intro), ("Outro", .outro),
        ("Zakończenie", .ending), ("Tag", .tag), ("Pusty", .blank), ("Własny", .custom)
    ])
    func legacyPolishTypes(name: String, expected: SlideType) throws {
        #expect(try decodeSlide(#"{"type":"\#(name)","label":"x","text":"y"}"#).type == expected)
    }

    @Test("Zapis używa stałego kodu i numeru, nie polskiej nazwy")
    func encodesCodes() throws {
        let slide = try decodeSlide(#"{"type":"Zwrotka","label":"Zwrotka 2","text":"Tekst"}"#)
        let json = String(decoding: try JSONEncoder().encode(slide), as: UTF8.self)

        #expect(slide.number == 2)
        #expect(json.contains(#""type":"verse""#))
        #expect(json.contains(#""number":2"#))
        #expect(!json.contains("Zwrotka\""))
    }

    @Test("Wszystkie kody są stabilne i angielskie")
    func codes() {
        #expect(SlideType.allCases.map(\.rawValue) == ["verse", "chorus", "bridge", "preChorus", "coda", "interlude", "intro", "outro", "ending", "tag", "blank", "custom"])
    }

    @Test("parseLyrics zapisuje numer zwrotki, także z nagłówka")
    func parseSetsNumbers() {
        let slides = Song.parseLyrics("Pierwsza\n\n[Refren]\nR\n\nDruga\n\n[Zwrotka 5]\nPiąta")

        #expect(slides.map(\.number) == [1, 1, 2, 5])
        #expect(slides.map(\.label) == ["Zwrotka 1", "Refren", "Zwrotka 2", "Zwrotka 5"])
    }

    @MainActor
    @Test("Skok do zwrotki po numerze, nie po polskiej etykiecie")
    func jumpToVerseUsesNumber() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let song = Song(title: "Test", rawLyrics: "", slides: [
            SongSlide(type: .verse, label: "Pierwsza", text: "a", number: 1),
            SongSlide(type: .chorus, label: "Ref", text: "b", number: 1),
            SongSlide(type: .verse, label: "Druga", text: "c", number: 2)
        ])
        store.present(song: song)

        store.jumpToVerse(number: 2)

        #expect(store.activeSlideIndex == 2)
    }
}
