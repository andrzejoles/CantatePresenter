import Foundation

// MARK: - SongSelect Importer

/// Import plików pobranych ręcznie z CCLI SongSelect: tekst (`.txt`), stary format `.usr` i ChordPro (`.pro`, `.cho`).
/// API SongSelect jest dostępne tylko dla partnerów CCLI, a regulamin zabrania automatycznego pobierania,
/// więc pliki pobiera osoba z kontem parafii. Nagłówki sekcji zamieniane są na znaczniki programu (`[Zwrotka 1]`, `[Refren]`).
public enum SongSelectImporter {
    public static let chordProExtensions: Set<String> = ["pro", "cho", "chopro", "chordpro", "crd"]
    
    /// Adres pieśni w SongSelect zapisywany jako źródło.
    public static func songURL(ccliNumber: String) -> String {
        "https://songselect.ccli.com/songs/\(ccliNumber)"
    }
    
    /// Wyszukiwanie w SongSelect (otwierane w przeglądarce, na koncie użytkownika).
    public static func searchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://songselect.ccli.com/search/results")
        components?.queryItems = [URLQueryItem(name: "search", value: query)]
        return components?.url
    }
    
    // MARK: - Sections
    
    private static let sectionRegex = try! NSRegularExpression(
        pattern: #"^(verse|chorus|refrain|pre-chorus|pre chorus|prechorus|bridge|tag|ending|outro|intro|interlude|instrumental|vamp|misc|strophe|coro|verso|puente)(\s+\d+)?:?$"#,
        options: .caseInsensitive
    )
    
    /// „Verse 2” → „[Zwrotka 2]”, „Chorus” → „[Refren]”; `nil`, gdy linia nie jest nagłówkiem sekcji.
    static func sectionMarker(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = sectionRegex.firstMatch(in: trimmed, range: range),
              let nameRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        let name = trimmed[nameRange].lowercased()
        let number = Range(match.range(at: 2), in: trimmed).map { " " + trimmed[$0].trimmingCharacters(in: .whitespaces) } ?? ""
        
        switch name {
        case "verse", "strophe", "verso": return "[Zwrotka\(number)]"
        case "chorus", "refrain", "coro": return "[Refren]"
        case "pre-chorus", "pre chorus", "prechorus": return "[Pre-Chorus]"
        case "bridge", "puente": return "[Bridge]"
        case "tag": return "[Tag]"
        case "ending": return "[Zakończenie]"
        case "outro": return "[Outro]"
        case "intro": return "[Intro]"
        case "interlude", "instrumental": return "[Przejście]"
        default: return "[\(trimmed[nameRange])\(number)]"
        }
    }
    
    // MARK: - Lyrics Text (.txt)
    
    /// Plik tekstowy z SongSelect rozpoznajemy po stopce „CCLI Song #”.
    public static func isSongSelectText(_ text: String) -> Bool {
        text.range(of: #"(?m)^\s*CCLI Song (#|No\.?)\s*\d+"#, options: .regularExpression) != nil
    }
    
    public static func parseText(_ text: String) -> Song? {
        let lines = normalizedLines(text)
        guard let titleIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let footerIndex = lines.firstIndex(where: { $0.range(of: #"^\s*CCLI Song (#|No\.?)"#, options: .regularExpression) != nil }),
              footerIndex > titleIndex else {
            return nil
        }
        
        let title = lines[titleIndex].trimmingCharacters(in: .whitespaces)
        let body = Array(lines[(titleIndex + 1)..<footerIndex])
        
        let ccliNumber = digits(in: lines[footerIndex])
        var author = ""
        var copyright: String?
        for line in lines[(footerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("For use solely") || trimmed.hasPrefix("Note:") {
                continue
            } else if trimmed.hasPrefix("CCLI License") || trimmed.hasPrefix("CCLI Licence") {
                continue
            } else if trimmed.hasPrefix("©") || trimmed.lowercased().hasPrefix("copyright") {
                copyright = trimmed
            } else if author.isEmpty {
                author = authors(from: trimmed)
            }
        }
        
        return makeSong(title: title, author: author, key: "", lyrics: lyrics(fromSections: body), chords: nil,
                        copyright: copyright, ccliNumber: ccliNumber)
    }
    
    // MARK: - USR (.usr)
    
    /// Stary format SongSelect: sekcja `[S A<numer>]`, pola `Title=`, `Author=`, `Copyright=`, `Keys=`,
    /// `Fields=` (nazwy sekcji) i `Words=` (teksty sekcji); separator sekcji `/t`, nowa linia `/n`.
    public static func parseUSR(_ text: String) -> Song? {
        var values: [String: String] = [:]
        var ccliNumber = ""
        for line in normalizedLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[S ") {
                ccliNumber = digits(in: trimmed)
            } else if let equals = trimmed.firstIndex(of: "=") {
                values[String(trimmed[..<equals]).lowercased()] = String(trimmed[trimmed.index(after: equals)...])
            }
        }
        guard let title = values["title"], !title.isEmpty else { return nil }
        
        let fields = (values["fields"] ?? "").components(separatedBy: "/t")
        let words = (values["words"] ?? "").components(separatedBy: "/t")
        var blocks: [String] = []
        for (index, sectionText) in words.enumerated() {
            let text = sectionText.replacingOccurrences(of: "/n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let marker = index < fields.count ? sectionMarker(for: fields[index]) : nil
            blocks.append([marker, text].compactMap { $0 }.joined(separator: "\n"))
        }
        
        var copyright = values["copyright"].map { $0.hasPrefix("©") ? $0 : "© " + $0 }
        if let admin = values["admin"], !admin.isEmpty, let current = copyright {
            copyright = "\(current) (Admin. by \(admin))"
        }
        let key = (values["keys"] ?? "").components(separatedBy: "/t").first ?? ""
        
        return makeSong(title: title, author: authors(from: values["author"] ?? ""), key: key,
                        lyrics: blocks.joined(separator: "\n\n"), chords: nil, copyright: copyright, ccliNumber: ccliNumber)
    }
    
    // MARK: - ChordPro (.pro)
    
    /// ChordPro z SongSelect: dyrektywy `{title:}`, `{key:}`, `{copyright:}`, `{ccli:}`, sekcje `{comment: Verse 1}`
    /// albo `{start_of_chorus}`, akordy w tekście `[G]`. Do projekcji idzie tekst bez akordów, a akordy trafiają
    /// do arkusza chwytów (linie akordów nad tekstem).
    public static func parseChordPro(_ text: String, fallbackTitle: String) -> Song {
        var title = ""
        var authorsList: [String] = []
        var key = ""
        var copyright: String?
        var ccliNumber = ""
        var lyricLines: [String] = []
        var sheetLines: [String] = []
        var hasChords = false
        
        func addSection(_ marker: String, sheetLabel: String) {
            if let last = lyricLines.last, !last.isEmpty { lyricLines.append("") }
            if let last = sheetLines.last, !last.isEmpty { sheetLines.append("") }
            lyricLines.append(marker)
            sheetLines.append(sheetLabel + ":")
        }
        
        for line in normalizedLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
                let inner = String(trimmed.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let name = parts[0].lowercased()
                let value = parts.count > 1 ? parts[1] : ""
                switch name {
                case "title", "t": title = value
                case "artist", "author", "composer", "lyricist", "subtitle", "st":
                    if !value.isEmpty { authorsList.append(contentsOf: value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }) }
                case "key": key = value
                case "copyright": copyright = value.hasPrefix("©") ? value : "© " + value
                case "ccli": ccliNumber = digits(in: value)
                case "comment", "c", "comment_italic", "ci", "comment_box", "cb":
                    if let marker = sectionMarker(for: value) { addSection(marker, sheetLabel: value) }
                case "start_of_chorus", "soc":
                    addSection("[Refren]", sheetLabel: value.isEmpty ? "Chorus" : value)
                case "start_of_bridge", "sob":
                    addSection("[Bridge]", sheetLabel: value.isEmpty ? "Bridge" : value)
                case "start_of_verse", "sov":
                    addSection(value.isEmpty ? "[Zwrotka]" : (sectionMarker(for: value) ?? "[\(value)]"), sheetLabel: value.isEmpty ? "Verse" : value)
                default:
                    break
                }
                continue
            }
            
            if let marker = sectionMarker(for: trimmed) {
                addSection(marker, sheetLabel: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                continue
            }
            
            let (chordLine, lyricLine) = splitChords(trimmed)
            if let chordLine {
                hasChords = true
                sheetLines.append(chordLine)
            }
            lyricLines.append(lyricLine)
            sheetLines.append(lyricLine)
        }
        
        let lyrics = collapseBlankLines(lyricLines)
        let chords = hasChords ? collapseBlankLines(sheetLines) : nil
        return makeSong(title: title.isEmpty ? fallbackTitle : title, author: authorsList.joined(separator: ", "), key: key,
                        lyrics: lyrics, chords: chords, copyright: copyright, ccliNumber: ccliNumber)
    }
    
    /// „A[G]mazing grace how [G7]sweet” → („ G               G7”, „Amazing grace how sweet”): akordy nad sylabą.
    static func splitChords(_ line: String) -> (chords: String?, lyrics: String) {
        guard line.contains("[") else { return (nil, line) }
        var lyrics = ""
        var chords = ""
        var lyricCount = 0
        var index = line.startIndex
        var found = false
        while index < line.endIndex {
            let character = line[index]
            if character == "[", let close = line[index...].firstIndex(of: "]") {
                let chord = String(line[line.index(after: index)..<close])
                var chordCount = chords.count
                if chordCount > lyricCount {
                    chords += " "
                    chordCount += 1
                }
                chords += String(repeating: " ", count: max(0, lyricCount - chordCount)) + chord
                found = true
                index = line.index(after: close)
            } else {
                lyrics.append(character)
                lyricCount += 1
                index = line.index(after: index)
            }
        }
        let cleaned = lyrics.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (found ? chords : nil, found ? cleaned : line)
    }
    
    // MARK: - Helpers
    
    private static func makeSong(title: String, author: String, key: String, lyrics: String, chords: String?,
                                 copyright: String?, ccliNumber: String) -> Song {
        var song = Song(title: title, author: author, key: key, tags: ["SongSelect"], rawLyrics: lyrics, chords: chords)
        song.copyright = copyright
        if !ccliNumber.isEmpty {
            song.ccliNumber = ccliNumber
            song.source = songURL(ccliNumber: ccliNumber)
        }
        return song
    }
    
    /// Treść między tytułem a stopką: nagłówki sekcji (osobne linie) na znaczniki programu, sekcje rozdzielone pustą linią.
    private static func lyrics(fromSections body: [String]) -> String {
        var output: [String] = []
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = sectionMarker(for: trimmed) {
                if let last = output.last, !last.isEmpty { output.append("") }
                output.append(marker)
            } else {
                output.append(trimmed)
            }
        }
        return collapseBlankLines(output)
    }
    
    private static func collapseBlankLines(_ lines: [String]) -> String {
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// SongSelect rozdziela autorów znakiem „|”.
    private static func authors(from line: String) -> String {
        line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    
    private static func digits(in text: String) -> String {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return "" }
        return String(text[range])
    }
    
    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: "\n")
    }
}
