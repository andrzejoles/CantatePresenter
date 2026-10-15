import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - CCLI: informacja o prawach na slajdzie

@Suite("Informacja o prawach autorskich (CCLI)")
struct CopyrightNoticeTests {
    private var song: Song {
        var song = Song(title: "Morning Light", author: "Anna Example", rawLyrics: "A\n\nB\n\nC")
        song.copyright = "© 2024 Example Music"
        song.ccliNumber = "9999001"
        return song
    }

    private func settings(_ placement: CopyrightNoticePlacement, license: String = "1234567") -> AppSettings {
        var settings = AppSettings()
        settings.copyrightNoticePlacement = placement
        settings.ccliLicenseNumber = license
        return settings
    }

    @Test("Pełna informacja: tytuł, autor, ©, numer pieśni i licencji")
    func fullNotice() throws {
        let text = try #require(CopyrightNotice.text(for: song, slideIndex: 0, settings: settings(.firstSlide)))
        #expect(text.contains("Morning Light"))
        #expect(text.contains("Anna Example"))
        #expect(text.contains("© 2024 Example Music"))
        #expect(text.contains("9999001"))
        #expect(text.contains("1234567"))
    }

    @Test("Miejsce: pierwszy, ostatni, każdy slajd albo wcale")
    func placement() {
        #expect(CopyrightNotice.text(for: song, slideIndex: 1, settings: settings(.firstSlide)) == nil)
        #expect(CopyrightNotice.text(for: song, slideIndex: 2, settings: settings(.lastSlide)) != nil)
        #expect(CopyrightNotice.text(for: song, slideIndex: 0, settings: settings(.lastSlide)) == nil)
        #expect(CopyrightNotice.text(for: song, slideIndex: 1, settings: settings(.allSlides)) != nil)
        #expect(CopyrightNotice.text(for: song, slideIndex: 0, settings: settings(.none)) == nil)
    }

    @Test("Bez numeru CCLI (np. domena publiczna) nic się nie pokazuje; bez licencji parafii bez jej numeru")
    func withoutNumbers() throws {
        var plain = song
        plain.ccliNumber = nil
        #expect(CopyrightNotice.text(for: plain, slideIndex: 0, settings: settings(.allSlides)) == nil)
        let text = try #require(CopyrightNotice.text(for: song, slideIndex: 0, settings: settings(.firstSlide, license: "")))
        #expect(!text.contains("1234567"))
    }

    @Test("Ustawienia: domyślnie pierwszy slajd; stare i nieznane wartości się wczytują")
    func settingsDecoding() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appLanguage":"pl"}"#.utf8))
        #expect(old.copyrightNoticePlacement == .firstSlide)
        #expect(old.ccliLicenseNumber.isEmpty)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"copyrightNoticePlacement":"sideways","ccliLicenseNumber":"42"}"#.utf8))
        #expect(unknown.copyrightNoticePlacement == .firstSlide)
        #expect(unknown.ccliLicenseNumber == "42")
    }
}
