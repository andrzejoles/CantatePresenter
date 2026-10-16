import Foundation

public struct Song: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var author: String
    public var key: String
    public var tags: [String]
    public var rawLyrics: String
    public var chords: String?
    
    /// Pieśń ma arkusz chwytów (pusty albo same spacje się nie liczy).
    public var hasChords: Bool {
        !(chords ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var slides: [SongSlide]
    public var createdAt: Date
    public var updatedAt: Date
    /// Skąd pochodzi tekst (adres strony, np. Wikiźródła albo SongSelect); `nil` dla pieśni wpisanych ręcznie (S9).
    public var source: String?
    /// Informacja o prawach autorskich lub licencji, np. „Domena publiczna” albo linia © z SongSelect.
    public var copyright: String?
    /// Numer pieśni w katalogu CCLI.
    public var ccliNumber: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        key: String = "",
        tags: [String] = [],
        rawLyrics: String,
        chords: String? = nil,
        slides: [SongSlide] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.key = key
        self.tags = tags
        self.rawLyrics = rawLyrics
        self.chords = chords
        if slides.isEmpty && !rawLyrics.isEmpty {
            self.slides = Song.parseLyrics(rawLyrics)
        } else {
            self.slides = slides
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Codable
    // Tolerancyjny dekoder: brakujące pola dostają wartości domyślne, więc nowe pola
    // dodane w przyszłości nie spowodują, że stara biblioteka przestanie się wczytywać (K1).
    private enum CodingKeys: String, CodingKey {
        case id, title, author, key, tags, rawLyrics, chords, slides, createdAt, updatedAt
        case source, copyright, ccliNumber
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.rawLyrics = try container.decodeIfPresent(String.self, forKey: .rawLyrics) ?? ""
        self.chords = try container.decodeIfPresent(String.self, forKey: .chords)
        let slides = try container.decodeIfPresent([SongSlide].self, forKey: .slides) ?? []
        self.slides = slides.isEmpty && !rawLyrics.isEmpty ? Song.parseLyrics(rawLyrics) : slides
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
        // Numer CCLI bywa zapisywany jako liczba (inne programy), więc przyjmujemy oba typy.
        if let text = try? container.decodeIfPresent(String.self, forKey: .ccliNumber) {
            self.ccliNumber = text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .ccliNumber) {
            self.ccliNumber = String(number)
        }
    }
    
    // MARK: - Unique Identifiers
    /// Nadaje nowe id (pieśni i jej slajdom) pieśniom, których id jest już zajęte w `existing`
    /// albo powtarza się wcześniej w `songs`. Pozostałe pieśni zostają bez zmian (W8).
    public static func assigningUniqueIdentifiers(_ songs: [Song], existing: Set<UUID>) -> [Song] {
        var used = existing
        return songs.map { song in
            var song = song
            if used.contains(song.id) {
                song.id = UUID()
                song.slides = song.slides.map { slide in
                    var slide = slide
                    slide.id = UUID()
                    return slide
                }
            }
            used.insert(song.id)
            return song
        }
    }
    
    // MARK: - Search matching with Polish diacritics folding
    public static func foldString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Postać do wyszukiwania: jak `foldString`, a do tego znaki interpunkcyjne zamienione na spacje
    /// i spacje zwinięte, więc „moj jezu moj zbawco” znajduje „Mój Jezu, mój Zbawco”.
    public static func searchFold(_ string: String) -> String {
        foldString(string)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
    
    public enum SearchScope: String, CaseIterable, Identifiable {
        case all = "Wszędzie"
        case titleAndAuthor = "Tytuł i autor"
        case titleOnly = "Tylko tytuł"
        case authorOnly = "Tylko autor"
        
        public var id: String { rawValue }
    }
    
    public func matches(query: String, scope: SearchScope = .all) -> Bool {
        let cleanQuery = Song.searchFold(query)
        if cleanQuery.isEmpty { return true }
        
        let foldedTitle = Song.searchFold(title)
        let foldedAuthor = Song.searchFold(author)
        
        switch scope {
        case .all:
            if foldedTitle.contains(cleanQuery) { return true }
            if foldedAuthor.contains(cleanQuery) { return true }
            for tag in tags {
                if Song.searchFold(tag).contains(cleanQuery) { return true }
            }
            let foldedLyrics = Song.searchFold(rawLyrics)
            return foldedLyrics.contains(cleanQuery)
            
        case .titleAndAuthor:
            return foldedTitle.contains(cleanQuery) || foldedAuthor.contains(cleanQuery)
            
        case .titleOnly:
            return foldedTitle.contains(cleanQuery)
            
        case .authorOnly:
            return foldedAuthor.contains(cleanQuery)
        }
    }
    
    public func matchingSnippet(query: String) -> String? {
        let cleanQuery = Song.searchFold(query)
        guard !cleanQuery.isEmpty else { return nil }
        
        let foldedTitle = Song.searchFold(title)
        if foldedTitle.contains(cleanQuery) { return nil }
        
        let lines = rawLyrics.components(separatedBy: .newlines)
        for line in lines {
            let folded = Song.searchFold(line)
            if folded.contains(cleanQuery) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 70 {
                    return String(trimmed.prefix(67)) + "..."
                }
                return trimmed
            }
        }
        return nil
    }
    
    // MARK: - Smart Lyrics Parsing
    /// Tekst za nagłówkiem w tej samej linii, bez dwukropka i spacji na początku; `nil`, gdy pusty.
    private static func textAfterHeader(_ rest: Substring) -> String? {
        let text = String(rest.drop(while: { $0 == ":" || $0 == " " || $0 == "\t" })).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
    
    private static let preChorusKeywords = ["pre-chorus", "prechorus", "pre chorus", "przed-refren", "przedrefren", "przed refren"]
    
    /// Kompilowany raz, a nie dla każdego bloku (N3).
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^\[([^\]]+)\]$|^([0-9]+)\.?$|^(pre[- ]?chorus|przed[- ]?refren|ref(ren)?|chorus|bridge|most(ek)?|coda|koda|interlude|przej[sś]cie|solo|intro|wst[eę]p|outro|zako[nń]czenie|ending|tag|zwrotka|z)(\s*[0-9]*)?:?$"#,
        options: .caseInsensitive
    )
    
    public static func parseLyrics(_ raw: String) -> [SongSlide] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
        
        let blocks = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if blocks.isEmpty {
            return [SongSlide(type: .verse, label: "Zwrotka 1", text: raw.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        
        var slides: [SongSlide] = []
        var verseCounter = 1
        var chorusCounter = 1
        var bridgeCounter = 1
        var codaCounter = 1
        var interludeCounter = 1
        var endingCounter = 1
        
        for block in blocks {
            var lines = block.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            guard !lines.isEmpty else { continue }
            
            var type: SlideType = .verse
            var label = ""
            
            let firstLine = lines[0]
            let lower = firstLine.lowercased()
            
            // Check for explicit headers like [Zwrotka 1], [Refren], [Coda], [Koda], [Przejście], [Zakończenie], etc.
            let isHeaderMatch = Song.headerRegex.firstMatch(in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.utf16.count)) != nil
            
            if isHeaderMatch || lower.hasPrefix("[") || lower.hasPrefix("ref:") || lower.hasPrefix("refren:") || lower.hasPrefix("chorus:") || lower.hasPrefix("coda:") || lower.hasPrefix("koda:") || lower.hasPrefix("przejście:") || lower.hasPrefix("przejscie:") || lower.hasPrefix("zakończenie:") {
                // Tekst w tej samej linii co nagłówek („Ref: Chwała Panu”, „[Refren] Chwała”) zostaje w slajdzie.
                let headerContent: String
                var inlineText: String?
                if lower.hasPrefix("["), let close = firstLine.firstIndex(of: "]") {
                    headerContent = String(firstLine[firstLine.index(after: firstLine.startIndex)..<close])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]: \t"))
                    inlineText = Song.textAfterHeader(firstLine[firstLine.index(after: close)...])
                } else if !isHeaderMatch, let colon = firstLine.firstIndex(of: ":") {
                    headerContent = String(firstLine[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]: \t"))
                    inlineText = Song.textAfterHeader(firstLine[firstLine.index(after: colon)...])
                } else {
                    headerContent = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "[]: \t"))
                }
                let hLower = headerContent.lowercased()
                
                // Przedrefren przed refrenem: „pre-chorus” zawiera „chorus”, a „przed-refren” zawiera „ref” (S7).
                if Song.preChorusKeywords.contains(where: { hLower.contains($0) }) {
                    type = .preChorus
                    label = "Pre-Chorus"
                } else if hLower.contains("coda") || hLower.contains("koda") {
                    type = .coda
                    label = codaCounter > 1 ? "Coda \(codaCounter)" : "Coda"
                    codaCounter += 1
                } else if hLower.contains("interlude") || hLower.contains("przejscie") || hLower.contains("przejście") || hLower.contains("solo") {
                    type = .interlude
                    label = interludeCounter > 1 ? "Przejście \(interludeCounter)" : "Przejście"
                    interludeCounter += 1
                } else if hLower.contains("zakonczenie") || hLower.contains("zakończenie") || hLower.contains("ending") {
                    type = .ending
                    label = endingCounter > 1 ? "Zakończenie \(endingCounter)" : "Zakończenie"
                    endingCounter += 1
                } else if hLower.contains("outro") {
                    type = .outro
                    label = "Outro"
                } else if hLower.contains("intro") || hLower.contains("wstep") || hLower.contains("wstęp") {
                    type = .intro
                    label = "Intro"
                } else if hLower.contains("ref") || hLower.contains("chorus") || hLower == "r" {
                    type = .chorus
                    label = chorusCounter > 1 ? "Refren \(chorusCounter)" : "Refren"
                    chorusCounter += 1
                } else if hLower.contains("bridge") || hLower == "b" || hLower.contains("most") {
                    type = .bridge
                    label = bridgeCounter > 1 ? "Bridge \(bridgeCounter)" : "Bridge"
                    bridgeCounter += 1
                } else if hLower.contains("pre") {
                    type = .preChorus
                    label = "Pre-Chorus"
                } else if hLower.contains("tag") {
                    type = .tag
                    label = "Tag"
                } else {
                    type = .verse
                    label = headerContent
                }
                if let inlineText {
                    lines[0] = inlineText
                } else {
                    lines.removeFirst()
                }
            } else {
                // Auto detect by line prefix or sequential index
                if lower.starts(with: "ref:") || lower.starts(with: "refren:") {
                    type = .chorus
                    label = chorusCounter > 1 ? "Refren \(chorusCounter)" : "Refren"
                    chorusCounter += 1
                    lines[0] = String(lines[0].drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if lower.starts(with: "r:") {
                    type = .chorus
                    label = chorusCounter > 1 ? "Refren \(chorusCounter)" : "Refren"
                    chorusCounter += 1
                    lines[0] = String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if lower.starts(with: "coda:") || lower.starts(with: "koda:") {
                    type = .coda
                    label = codaCounter > 1 ? "Coda \(codaCounter)" : "Coda"
                    codaCounter += 1
                    lines[0] = String(lines[0].drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if lower.starts(with: "przejście:") || lower.starts(with: "przejscie:") || lower.starts(with: "interlude:") {
                    type = .interlude
                    label = interludeCounter > 1 ? "Przejście \(interludeCounter)" : "Przejście"
                    interludeCounter += 1
                    lines[0] = String(lines[0].drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if lower.starts(with: "zakończenie:") || lower.starts(with: "zakonczenie:") || lower.starts(with: "ending:") {
                    type = .ending
                    label = endingCounter > 1 ? "Zakończenie \(endingCounter)" : "Zakończenie"
                    endingCounter += 1
                    lines[0] = String(lines[0].drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                } else {
                    type = .verse
                    label = "Zwrotka \(verseCounter)"
                    verseCounter += 1
                }
            }
            
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let numbered: Set<SlideType> = [.verse, .chorus, .bridge, .coda, .interlude, .ending]
                let number = SongSlide.trailingNumber(in: label) ?? (numbered.contains(type) ? 1 : nil)
                slides.append(SongSlide(type: type, label: label, text: text, number: number))
            }
        }
        
        return slides.isEmpty ? [SongSlide(type: .verse, label: "Zwrotka 1", text: raw)] : slides
    }
}
