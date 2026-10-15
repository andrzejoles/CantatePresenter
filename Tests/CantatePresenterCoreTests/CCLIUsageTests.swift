import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - CCLI: raport użycia

@Suite("Raport użycia CCLI")
struct CCLIUsageTests {
    private var song: Song {
        var song = Song(title: "Morning Light", author: "Anna Example, John Sample", rawLyrics: "A")
        song.copyright = "© 2024 Example \"Music\""
        song.ccliNumber = "9999001"
        return song
    }

    @Test("Jeden wpis na pieśń dziennie; pieśni bez numeru CCLI pomijane")
    func oncePerDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let morning = Date(timeIntervalSince1970: 1_760_500_000)
        let first = try #require(CCLIUsageReport.entry(for: song, at: morning, existing: [], calendar: calendar))

        #expect(CCLIUsageReport.entry(for: song, at: morning.addingTimeInterval(3600), existing: [first], calendar: calendar) == nil)
        #expect(CCLIUsageReport.entry(for: song, at: morning.addingTimeInterval(86_400 * 7), existing: [first], calendar: calendar) != nil)
        #expect(CCLIUsageReport.entry(for: Song(title: "Bez CCLI", rawLyrics: "A"), at: morning, existing: [], calendar: calendar) == nil)
    }

    @Test("CSV: nagłówek, data, pola z przecinkiem i cudzysłowem w cudzysłowach")
    func csv() {
        let entry = CCLIUsageEntry(date: Date(timeIntervalSince1970: 1_760_500_000), title: song.title, author: song.author,
                                   ccliNumber: "9999001", copyright: song.copyright)
        let lines = CCLIUsageReport.csv([entry], timeZone: TimeZone(identifier: "UTC")!).components(separatedBy: "\r\n")

        #expect(lines[0] == "Date,Title,Authors,CCLI Song Number,Copyright")
        #expect(lines[1] == #"2025-10-15,Morning Light,"Anna Example, John Sample",9999001,"© 2024 Example ""Music""""#)
    }

    @MainActor
    @Test("Wyświetlenie pieśni zapisuje użycie na dysku; po ponownym uruchomieniu wpis zostaje")
    func recordedOnPresent() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }

        let store = DataStore(dataDirectory: dir.url)
        store.present(song: song)
        store.present(song: song, slideIndex: 0)
        #expect(store.ccliUsage.count == 1)

        let reopened = DataStore(dataDirectory: dir.url)
        #expect(reopened.ccliUsage.map(\.ccliNumber) == ["9999001"])
    }
}
