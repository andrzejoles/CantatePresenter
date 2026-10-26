import Foundation

// MARK: - Musician Stage Page

/// Strona dla muzyków na tabletach i telefonach (tylko podgląd): bieżący slajd z chwytami nad tekstem i następny slajd.
/// Transpozycję i wielkość czcionki każde urządzenie pamięta osobno (localStorage). Tekst wstawiany tylko przez textContent.
enum MusicianStagePage {
    static func html(language: String) -> String {
        template.replacingOccurrences(of: "{{LANG}}", with: language.filter { $0.isLetter || $0 == "-" })
    }

    /// Szablon w zasobach pakietu (`Resources/stage_page.html`).
    private static let template = WebPageResource.load("stage_page")
}
