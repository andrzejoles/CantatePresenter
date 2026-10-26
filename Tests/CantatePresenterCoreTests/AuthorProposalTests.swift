import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R6-11: wyszukiwanie autorów dla wielu pieśni

@Suite("Propozycje autorów: zastosowanie do pieśni")
struct AuthorProposalTests {
    private func proposal(for song: Song, author: String = "Jan Kowalski", title: String = "", accept: Bool) -> SongMatchProposal {
        SongMatchProposal(songId: song.id, currentTitle: song.title, currentAuthor: song.author,
                          proposedTitle: title, proposedAuthor: author, source: "test", confidence: 50, acceptAuthor: accept)
    }

    @Test("Odrzucony autor przy „Uzupełniaj tylko puste pola” nie zastępuje istniejącego autora (R6-11)")
    func rejectedAuthorKeepsExistingAuthor() {
        let song = Song(title: "Barka", author: "C. Gabarain", rawLyrics: "Pan kiedyś stanął")
        let result = proposal(for: song, accept: false).applied(to: song, onlyFillEmptyFields: true, updateTitle: false)
        #expect(result.author == "C. Gabarain")
    }

    @Test("Odrzucony autor przy pustym polu daje stały znacznik „Nieznany”")
    func rejectedAuthorFillsEmptyAuthor() {
        let song = Song(title: "Barka", author: "  ", rawLyrics: "Pan kiedyś stanął")
        let result = proposal(for: song, accept: false).applied(to: song, onlyFillEmptyFields: true, updateTitle: false)
        #expect(result.author == SongEnrichmentService.unknownAuthorPlaceholder)
    }

    @Test("Bez „tylko puste pola” odrzucenie i akceptacja zmieniają autora")
    func overwriteWhenAllowed() {
        let song = Song(title: "Barka", author: "C. Gabarain", rawLyrics: "Pan kiedyś stanął")
        #expect(proposal(for: song, accept: false).applied(to: song, onlyFillEmptyFields: false, updateTitle: false).author == SongEnrichmentService.unknownAuthorPlaceholder)
        #expect(proposal(for: song, accept: true).applied(to: song, onlyFillEmptyFields: false, updateTitle: false).author == "Jan Kowalski")
        #expect(proposal(for: song, accept: true).applied(to: song, onlyFillEmptyFields: true, updateTitle: false).author == "C. Gabarain")
    }

    @Test("Tytuł zmienia się tylko z opcją aktualizacji tytułu")
    func titleUpdate() {
        let song = Song(title: "barka", author: "", rawLyrics: "Pan kiedyś stanął")
        let prop = proposal(for: song, title: "Barka", accept: true)
        #expect(prop.applied(to: song, onlyFillEmptyFields: true, updateTitle: false).title == "barka")
        #expect(prop.applied(to: song, onlyFillEmptyFields: true, updateTitle: true).title == "Barka")
    }
}
