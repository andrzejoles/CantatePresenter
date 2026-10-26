import Foundation

// MARK: - Remote Control Page

/// Strona pilota dla telefonu (iOS i Android, zwykła przeglądarka). Wszystkie teksty przychodzą w stanie (`labels`)
/// w języku interfejsu aplikacji, więc strona nie ma własnych tłumaczeń. Tekst wstawiany tylko przez `textContent`.
enum RemoteControlPage {
    static func html(language: String) -> String {
        template.replacingOccurrences(of: "{{LANG}}", with: language.filter { $0.isLetter || $0 == "-" })
    }
    
    /// Szablon w zasobach pakietu (`Resources/remote_page.html`).
    private static let template = WebPageResource.load("remote_page")
}

// MARK: - Web Page Resource

/// Strony dla telefonu i tabletu z zasobów pakietu. Brak pliku (uszkodzona instalacja) daje krótki komunikat zamiast awarii.
enum WebPageResource {
    static func load(_ name: String) -> String {
        guard let url = Localization.resourceBundle?.url(forResource: name, withExtension: "html"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "<!doctype html><html lang=\"{{LANG}}\"><meta charset=\"utf-8\"><title>CantatePresenter</title><p>CantatePresenter: \(name).html</p></html>"
        }
        return text
    }
}
