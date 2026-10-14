import Foundation

public struct Song: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var author: String
    public var key: String
    public var tags: [String]
    public var rawLyrics: String
    public var chords: String?
    public var slides: [SongSlide]
    public var createdAt: Date
    public var updatedAt: Date
    
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
    
    // MARK: - Search matching with Polish diacritics folding
    public static func foldString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public enum SearchScope: String, CaseIterable, Identifiable {
        case all = "Wszędzie"
        case titleAndAuthor = "Tytuł i autor"
        case titleOnly = "Tylko tytuł"
        case authorOnly = "Tylko autor"
        
        public var id: String { rawValue }
    }
    
    public func matches(query: String, scope: SearchScope = .all) -> Bool {
        let cleanQuery = Song.foldString(query)
        if cleanQuery.isEmpty { return true }
        
        let foldedTitle = Song.foldString(title)
        let foldedAuthor = Song.foldString(author)
        
        switch scope {
        case .all:
            if foldedTitle.contains(cleanQuery) { return true }
            if foldedAuthor.contains(cleanQuery) { return true }
            for tag in tags {
                if Song.foldString(tag).contains(cleanQuery) { return true }
            }
            let foldedLyrics = Song.foldString(rawLyrics)
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
        let cleanQuery = Song.foldString(query)
        guard !cleanQuery.isEmpty else { return nil }
        
        let foldedTitle = Song.foldString(title)
        if foldedTitle.contains(cleanQuery) { return nil }
        
        let lines = rawLyrics.components(separatedBy: .newlines)
        for line in lines {
            let folded = Song.foldString(line)
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
            let headerRegex = try? NSRegularExpression(
                pattern: #"^\[([^\]]+)\]$|^([0-9]+)\.?$|^(ref(ren)?|chorus|bridge|most(ek)?|coda|koda|interlude|przej[sś]cie|solo|intro|wst[eę]p|outro|zako[nń]czenie|ending|tag|zwrotka|z)(\s*[0-9]*)?:?$"#,
                options: .caseInsensitive
            )
            let isHeaderMatch = headerRegex?.firstMatch(in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.utf16.count)) != nil
            
            if isHeaderMatch || lower.hasPrefix("[") || lower.hasPrefix("ref:") || lower.hasPrefix("refren:") || lower.hasPrefix("chorus:") || lower.hasPrefix("coda:") || lower.hasPrefix("koda:") || lower.hasPrefix("przejście:") || lower.hasPrefix("przejscie:") || lower.hasPrefix("zakończenie:") {
                let headerContent = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "[]: \t"))
                let hLower = headerContent.lowercased()
                
                if hLower.contains("coda") || hLower.contains("koda") {
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
                lines.removeFirst()
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
                slides.append(SongSlide(type: type, label: label, text: text))
            }
        }
        
        return slides.isEmpty ? [SongSlide(type: .verse, label: "Zwrotka 1", text: raw)] : slides
    }
}
