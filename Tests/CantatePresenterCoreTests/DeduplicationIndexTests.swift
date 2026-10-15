import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N8: indeks deduplikacji po zamianie i kolizje z wieloma pieśniami o tym samym tytule

@Suite("Deduplikacja: indeks (N8)")
struct DeduplicationIndexTests {
    private let verse = "Pan kiedyś stanął nad brzegiem szukał ludzi gotowych pójść za Nim by łowić serca słów Bożych prawdą"

    @Test("Kopia pieśni, która zastąpiła oryginał (lepszy autor), wykrywana po jej tytule")
    func duplicateOfSwappedPrimary() {
        // Wymyślone tytuły i tekst: wbudowany śpiewnik nie może sam uzupełnić autora.
        let lyrics = "Wiatr nad doliną niesie cichą modlitwę zielonych pól i srebrnych strumieni o świcie"
        // Alfa i Beta mają ten sam początek tekstu, więc Beta (z autorem) zastępuje Alfę.
        let alfa = Song(title: "Pieśń testowa Alfa", rawLyrics: lyrics + " amen")
        let beta = Song(title: "Pieśń testowa Beta", author: "Jan Testowy", rawLyrics: lyrics + " amen alleluja chwała")
        // Kopia Bety: ten sam tytuł, inny początek tekstu; do wykrycia potrzebny jest tytuł Bety w indeksie.
        let betaCopy = Song(title: "Pieśń testowa Beta", rawLyrics: "O świcie " + lyrics + " alleluja chwała")

        let result = SongDeduplicationService.shared.processAndDeduplicate(incoming: [alfa, beta, betaCopy], existingLibrary: [])

        #expect(result.uniqueSongs.map(\.title) == ["Pieśń testowa Beta"])
        #expect(result.uniqueSongs.first?.author == "Jan Testowy")
        #expect(result.duplicateRecords.count == 2)
    }

    @Test("Kolizja z biblioteką: porównanie z najbardziej podobną pieśnią o tym tytule, nie z ostatnią")
    func collisionWithBestMatchingLibrarySong() throws {
        let library = [
            Song(title: "Barka", rawLyrics: verse),
            Song(title: "Barka", rawLyrics: "Zupełnie inny utwór o łodzi rybackiej na jeziorze i sieciach")
        ]
        let incoming = [Song(title: "Barka", rawLyrics: verse)]

        let result = SongDeduplicationService.shared.processAndDeduplicate(incoming: incoming, existingLibrary: library)
        let collision = try #require(result.existingCollisions.first)

        #expect(collision.similarityScore == 100)
        #expect(collision.shouldSkipDuplicate)
    }
}

// MARK: - N3: znaczniki Holyrics (wzorce kompilowane raz)

@Suite("Znaczniki sekcji Holyrics (N3)")
struct HolyricsMarkerTests {
    @Test("Znaczniki ##(…) zamieniane na nagłówki slajdów")
    func translatesMarkers() {
        let text = "##(Verse 2)\nA\n\n##(Chorus)\nB\n\n##(Pre-Chorus)\nC\n\n##(Solo X)\nD"
        #expect(HolyricsImporter.translateHolyricsVerseMarkers(text) == "[Zwrotka 2]\nA\n\n[Refren]\nB\n\n[Przed-refren]\nC\n\n[Solo X]\nD")
    }
}
