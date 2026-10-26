import Foundation

public struct SongMatchProposal: Identifiable, Equatable {
    public let id = UUID()
    public let songId: UUID
    public var currentTitle: String
    public var currentAuthor: String
    public var proposedTitle: String
    public var proposedAuthor: String
    public var source: String
    public var confidence: Int // 0 to 100%
    public var candidateResults: [OnlineSearchResult]
    public var isSelected: Bool
    public var isApplied: Bool
    public var acceptAuthor: Bool
    public var customAuthor: String
    
    public init(
        songId: UUID,
        currentTitle: String,
        currentAuthor: String,
        proposedTitle: String,
        proposedAuthor: String,
        source: String,
        confidence: Int,
        candidateResults: [OnlineSearchResult] = [],
        isSelected: Bool = true,
        isApplied: Bool = false,
        acceptAuthor: Bool = true,
        customAuthor: String = ""
    ) {
        self.songId = songId
        self.currentTitle = currentTitle
        self.currentAuthor = currentAuthor
        self.proposedTitle = proposedTitle
        self.proposedAuthor = proposedAuthor
        self.source = source
        self.confidence = confidence
        self.candidateResults = candidateResults
        self.isSelected = isSelected
        self.isApplied = isApplied
        self.acceptAuthor = acceptAuthor
        self.customAuthor = customAuthor
    }
}

public final class AuthorTitleLookupService: Sendable {
    public static let shared = AuthorTitleLookupService()
    
    /// Extracts the best search query candidate for a song (lyrics first line or clean title)
    public func suggestedQuery(for song: Song) -> String {
        // First try the first meaningful line of lyrics
        for slide in song.slides {
            let lines = slide.text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    !line.isEmpty &&
                    !line.hasPrefix("[") &&
                    !line.hasPrefix("1.") &&
                    !line.hasPrefix("2.")
                }
            if let firstLine = lines.first, firstLine.count >= 8 {
                // If it's a good line of lyrics, take up to 6 words
                let words = firstLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if words.count >= 2 {
                    return words.prefix(6).joined(separator: " ")
                }
            }
        }
        
        // Fallback to cleaned title
        var title = song.title
        // Remove leading numbers like "01. ", "02 - "
        if let regex = try? NSRegularExpression(pattern: #"^[0-9]+[\.\-\_\s]+"#) {
            let nsTitle = title as NSString
            let range = NSRange(location: 0, length: nsTitle.length)
            title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
        }
        // Remove file extension if present
        if title.lowercased().hasSuffix(".txt") {
            title = String(title.dropLast(4))
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Finds metadata proposals for a single song
    public func lookup(for song: Song, customQuery: String? = nil, language: String = "pl") async -> (best: SongMatchProposal?, all: [OnlineSearchResult]) {
        let query = (customQuery ?? suggestedQuery(for: song)).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return (nil, [])
        }
        
        let results = await OnlineSearchService.shared.search(query: query, language: language)
        if results.isEmpty {
            return (nil, [])
        }
        
        // Calculate similarity scores for each result
        var scoredResults: [(result: OnlineSearchResult, score: Int)] = []
        let foldedSongTitle = Song.foldString(song.title)
        let foldedSongLyrics = Song.foldString(song.rawLyrics)
        let songWords = Set(foldedSongLyrics.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        
        for r in results {
            var score = 30 // Base match from search engine
            let rTitle = Song.foldString(r.title)
            let rLyrics = Song.foldString(r.lyrics)
            
            // Title match bonus
            if rTitle == foldedSongTitle {
                score += 40
            } else if rTitle.contains(foldedSongTitle) || foldedSongTitle.contains(rTitle) {
                score += 25
            }
            
            // Lyrics word overlap
            let rWords = Set(rLyrics.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
            if !songWords.isEmpty && !rWords.isEmpty {
                let common = songWords.intersection(rWords).count
                let overlapRatio = Double(common) / Double(min(songWords.count, 25))
                score += Int(min(35.0, overlapRatio * 35.0))
            }
            
            // Penalty if artist is empty
            if r.artist.trimmingCharacters(in: .whitespaces).isEmpty {
                score -= 10
            }
            
            scoredResults.append((r, min(99, max(15, score))))
        }
        
        scoredResults.sort { $0.score > $1.score }
        
        guard let top = scoredResults.first else {
            return (nil, results)
        }
        
        let proposal = SongMatchProposal(
            songId: song.id,
            currentTitle: song.title,
            currentAuthor: song.author,
            proposedTitle: top.result.title,
            proposedAuthor: top.result.artist,
            source: top.result.source,
            confidence: top.score,
            candidateResults: results,
            isSelected: top.score >= 45,
            isApplied: false
        )
        
        return (proposal, results)
    }
}
