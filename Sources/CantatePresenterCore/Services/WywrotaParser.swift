import Foundation

// MARK: - Wywrota Song

/// Pieśń odczytana z jednej strony Śpiewnika Wywroty wyświetlonej przez użytkownika (`WywrotaBrowserSheet`).
/// Aplikacja niczego nie pobiera sama: odczytuje tylko stronę otwartą w przeglądarce i tylko po kliknięciu
/// „Wstaw…” (decyzja właściciela 2026-11-03, regulamin serwisu §7.1 zakazuje automatycznego i masowego pobierania).
public struct WywrotaSong: Equatable, Sendable {
    public var title: String
    public var url: String
    /// Tekst do slajdów: zwrotki numerowane w serwisie dostają nagłówek „[Zwrotka N]”, a nienumerowane obok nich
    /// i oznaczone „Ref.” nagłówek „[Refren]”.
    public var lyrics: String
    /// Arkusz „chwyty nad tekstem” z tymi samymi nagłówkami; `nil`, gdy opracowanie nie ma chwytów.
    public var chords: String?
}

// MARK: - Wywrota Parser

/// Zamiana opracowania ze strony Śpiewnika Wywroty na tekst i arkusz chwytów.
///
/// Serwis zapisuje opracowanie w `.interpretation-content`: wiersze rozdzielone `<br>`, a każdy chwyt jako
/// `<code class='an' data-chord='C' data-suffix='7'>` wstawiony w tekst w miejscu zmiany akordu.
public enum WywrotaParser {
    /// Hosty serwisu, które przeglądarka w aplikacji otwiera u siebie; inne adresy idą do domyślnej przeglądarki.
    public static func isWywrotaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "wywrota.pl" || host.hasSuffix(".wywrota.pl")
    }

    public static let homeURL = URL(string: "https://spiewnik.wywrota.pl/piosenki-religijne")!

    /// Adres wyszukiwania w serwisie (formularz „Szukaj” na stronie, `/search?q=`).
    public static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://spiewnik.wywrota.pl/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    /// Skrypt odczytujący wyświetloną stronę: HTML opracowania, tytuł z danych strukturalnych i to, czy serwis
    /// pokazuje tylko początek (niezalogowany użytkownik widzi „Zaloguj się aby zobaczyć całe opracowanie”).
    /// Wynik: JSON albo `null`, gdy to nie jest strona pieśni.
    public static let pageScript = """
    (() => {
      const content = document.querySelector('.interpretation-content');
      if (!content) { return null; }
      let title = '';
      for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
        try {
          const data = JSON.parse(script.textContent);
          if (data && data['@type'] === 'MusicRecording' && typeof data.name === 'string') { title = data.name; }
        } catch (e) {}
      }
      const overlay = document.querySelector('.white-gradient-overlay');
      const truncated = !!(overlay && overlay.querySelector('a[href*="login"]'));
      return JSON.stringify({ html: content.innerHTML, title: title, truncated: truncated });
    })()
    """

    /// Wynik `pageScript`.
    public struct Page: Decodable, Equatable, Sendable {
        public var html: String
        public var title: String
        public var truncated: Bool
    }

    // MARK: Lines

    struct Line: Equatable {
        var text: String
        /// Chwyt i kolumna (w znakach tekstu), nad którą stoi.
        var chords: [(column: Int, name: String)]

        static func == (lhs: Line, rhs: Line) -> Bool {
            lhs.text == rhs.text && lhs.chords.map(\.column) == rhs.chords.map(\.column) && lhs.chords.map(\.name) == rhs.chords.map(\.name)
        }
    }

    /// Wiersze opracowania z HTML-a `.interpretation-content`. Puste wiersze zostają (granice zwrotek),
    /// puste na początku i końcu są usuwane.
    static func lines(fromHTML html: String) -> [Line] {
        var lines: [Line] = []
        var current = Line(text: "", chords: [])
        var index = html.startIndex

        func appendText(_ raw: Substring) {
            // Znaki nowej linii w źródle HTML to tylko formatowanie (wiersze dzieli `<br>`).
            let text = decodeEntities(String(raw)).replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            current.text += text.replacingOccurrences(of: "\u{00A0}", with: " ")
        }

        while index < html.endIndex {
            guard let open = html[index...].firstIndex(of: "<") else {
                appendText(html[index...])
                break
            }
            appendText(html[index..<open])
            guard let close = html[open...].firstIndex(of: ">") else { break }
            let tag = html[html.index(after: open)..<close]
            let name = tag.prefix { $0.isLetter || $0 == "/" }.lowercased()
            index = html.index(after: close)
            switch name {
            case "br":
                lines.append(current)
                current = Line(text: "", chords: [])
            case "code" where attribute("data-chord", in: tag) != nil:
                let chord = (attribute("data-chord", in: tag) ?? "") + (attribute("data-suffix", in: tag) ?? "")
                if !chord.isEmpty {
                    current.chords.append((current.text.count, chord))
                }
                // Treść `<code>` to ten sam chwyt pokazany na stronie, nie tekst pieśni.
                if let end = html[index...].range(of: "</code>", options: .caseInsensitive) {
                    index = end.upperBound
                }
            default:
                break
            }
        }
        lines.append(current)

        let normalized = lines.map(normalize)
        guard let first = normalized.firstIndex(where: { !$0.isBlank }),
              let last = normalized.lastIndex(where: { !$0.isBlank }) else { return [] }
        return Array(normalized[first...last])
    }

    /// Spacje na początku i końcu wiersza bez przesuwania chwytów względem tekstu.
    private static func normalize(_ line: Line) -> Line {
        let leading = line.text.prefix { $0 == " " || $0 == "\t" }.count
        let text = String(line.text.dropFirst(leading)).trimmingCharacters(in: .whitespaces)
        let chords = line.chords.map { (column: min(max(0, $0.column - leading), text.count), name: $0.name) }
        return Line(text: text, chords: chords)
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        for quote in ["'", "\""] {
            if let start = tag.range(of: "\(name)=\(quote)") {
                let rest = tag[start.upperBound...]
                if let end = rest.firstIndex(of: Character(quote)) {
                    return decodeEntities(String(rest[..<end]))
                }
            }
        }
        return nil
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";") {
                let entity = String(after[..<semicolon])
                var decoded: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    decoded = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = named[entity]
                }
                if let decoded {
                    result += decoded
                    rest = after[after.index(after: semicolon)...]
                    continue
                }
            }
            result += "&"
            rest = after
        }
        return result + rest
    }

    // MARK: Song

    /// Zwrotki („1. Tekst”) i refren („Ref.: Tekst”) rozpoznane w opracowaniu.
    private struct Stanza {
        var header: String?
        var lines: [Line]
        var hasText: Bool { lines.contains { !$0.text.isEmpty } }
    }

    private static let verseNumber = try! NSRegularExpression(pattern: #"^([0-9]{1,2})[.)]\s*"#)
    private static let chorusMarker = try! NSRegularExpression(pattern: #"^(ref(ren)?|r|chorus)\s*[.:]+\s*"#, options: .caseInsensitive)

    public static func song(page: Page, url: String) -> WywrotaSong {
        song(contentHTML: page.html, title: page.title, url: url)
    }

    public static func song(contentHTML html: String, title: String, url: String) -> WywrotaSong {
        var stanzas: [Stanza] = []
        var current: [Line] = []
        for line in lines(fromHTML: html) + [Line(text: "", chords: [])] {
            if line.isBlank {
                if !current.isEmpty { stanzas.append(Stanza(header: nil, lines: current)) }
                current = []
            } else {
                current.append(line)
            }
        }

        var hasNumbered = false
        for index in stanzas.indices {
            guard var first = stanzas[index].lines.first else { continue }
            if let number = strip(verseNumber, from: &first) {
                stanzas[index].header = "[Zwrotka \(number)]"
                hasNumbered = true
            } else if strip(chorusMarker, from: &first) != nil {
                stanzas[index].header = "[Refren]"
            }
            stanzas[index].lines[0] = first
        }
        // W śpiewnikach zwrotki są numerowane, a refren nie: bez nagłówka byłby liczony jako kolejna zwrotka
        // i cyfra na klawiaturze trafiałaby w refren.
        if hasNumbered {
            for index in stanzas.indices where stanzas[index].header == nil && stanzas[index].hasText {
                stanzas[index].header = "[Refren]"
            }
        }

        // Zwrotka z samymi chwytami (wstęp, przejście) jest tylko w arkuszu chwytów, bez pustego slajdu.
        let lyrics = stanzas.filter(\.hasText).map { stanza in
            ([stanza.header].compactMap { $0 } + stanza.lines.map(\.text).filter { !$0.isEmpty }).joined(separator: "\n")
        }.joined(separator: "\n\n")

        let hasChords = stanzas.contains { $0.lines.contains { !$0.chords.isEmpty } }
        let sheet = stanzas.map { stanza in
            ([stanza.header].compactMap { $0 } + stanza.lines.flatMap { line -> [String] in
                line.chords.isEmpty ? [line.text] : [chordLine(line.chords), line.text].filter { !$0.isEmpty }
            }).joined(separator: "\n")
        }.joined(separator: "\n\n")

        return WywrotaSong(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            lyrics: lyrics,
            chords: hasChords ? sheet : nil
        )
    }

    /// Usuwa znacznik z początku wiersza i przesuwa chwyty; zwraca grupę 1 (numer) albo całe dopasowanie.
    private static func strip(_ regex: NSRegularExpression, from line: inout Line) -> String? {
        let range = NSRange(line.text.startIndex..., in: line.text)
        guard let match = regex.firstMatch(in: line.text, range: range), let whole = Range(match.range, in: line.text) else { return nil }
        let group = match.range(at: 1).location != NSNotFound ? Range(match.range(at: 1), in: line.text).map { String(line.text[$0]) } : nil
        let removed = line.text[whole].count
        line.text = String(line.text[whole.upperBound...])
        line.chords = line.chords.map { (column: max(0, $0.column - removed), name: $0.name) }
        return group ?? ""
    }

    /// Wiersz chwytów z nazwami w kolumnach tekstu; nachodzące na siebie rozdziela jedna spacja.
    static func chordLine(_ chords: [(column: Int, name: String)]) -> String {
        var line = ""
        for chord in chords {
            if line.count < chord.column {
                line += String(repeating: " ", count: chord.column - line.count)
            } else if !line.isEmpty {
                line += " "
            }
            line += chord.name
        }
        return line
    }
}

private extension WywrotaParser.Line {
    var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && chords.isEmpty }
}
