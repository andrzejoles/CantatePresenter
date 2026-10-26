import Foundation

public struct DuplicateRecord: Identifiable {
    public let id = UUID()
    public let primarySong: Song
    public let duplicateSong: Song
    public let reason: String
    public let similarityScore: Int // 0 to 100%
    public var shouldSkipDuplicate: Bool = true
}

public struct EnrichmentRecord: Identifiable {
    public let id = UUID()
    public let originalTitle: String
    public let enrichedTitle: String
    public let originalAuthor: String
    public let enrichedAuthor: String
    public let details: String
}

public struct ImportProcessingResult {
    public var totalScanned: Int
    public var uniqueSongs: [Song]
    public var duplicateRecords: [DuplicateRecord]
    public var enrichmentRecords: [EnrichmentRecord]
    public var existingCollisions: [DuplicateRecord]
    
    /// Pieśni do dodania po przeglądzie importu. Brak decyzji w mapach oznacza wartość domyślną
    /// `shouldSkipDuplicate` z rekordu.
    public func songsToCommit(workingSongs: [Song], duplicateSkips: [UUID: Bool], collisionSkips: [UUID: Bool]) -> [Song] {
        let skippedCollisionIDs = Set(existingCollisions
            .filter { collisionSkips[$0.id] ?? $0.shouldSkipDuplicate }
            .map(\.duplicateSong.id))
        var result = workingSongs.filter { !skippedCollisionIDs.contains($0.id) }
        for record in duplicateRecords where !(duplicateSkips[record.id] ?? record.shouldSkipDuplicate) {
            var copy = record.duplicateSong
            copy.title = "\(copy.title) (wersja alternatywna)"
            result.append(copy)
        }
        return result
    }
}

public final class SongDeduplicationService: Sendable {
    public static let shared = SongDeduplicationService()
    
    /// Normalizes lyrics to word tokens
    public static func lyricsTokens(_ foldedLyrics: String) -> Set<String> {
        let words = foldedLyrics.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        return Set(words)
    }
    
    /// Calculates word similarity between two precomputed token sets
    public static func tokenSimilarity(_ t1: Set<String>, _ t2: Set<String>) -> Int {
        if t1.isEmpty && t2.isEmpty { return 100 }
        if t1.isEmpty || t2.isEmpty { return 0 }
        let intersection = t1.intersection(t2).count
        let union = t1.union(t2).count
        guard union > 0 else { return 0 }
        return Int((Double(intersection) / Double(union)) * 100.0)
    }
    
    /// Processes incoming songs: enriches canonical metadata and detects duplicates with O(1) indexed lookup
    public func processAndDeduplicate(incoming: [Song], existingLibrary: [Song]) -> ImportProcessingResult {
        var enrichedList: [Song] = []
        var enrichments: [EnrichmentRecord] = []
        // Unikalne id już na wejściu, żeby decyzje w przeglądzie importu dotyczyły jednej pieśni (W8).
        let incoming = Song.assigningUniqueIdentifiers(incoming, existing: Set(existingLibrary.map(\.id)))
        
        // 1. Enrich metadata for all incoming songs
        for s in incoming {
            let (enriched, wasEnriched, details) = SongEnrichmentService.shared.enrich(song: s)
            enrichedList.append(enriched)
            if wasEnriched {
                enrichments.append(EnrichmentRecord(
                    originalTitle: s.title,
                    enrichedTitle: enriched.title,
                    originalAuthor: s.author.isEmpty ? "brak" : s.author,
                    enrichedAuthor: enriched.author,
                    details: details
                ))
            }
        }
        
        // Internal helper to extract prefix key (first 6 words of folded lyrics)
        func lyricsPrefixKey(_ foldedLyrics: String) -> String {
            let words = foldedLyrics.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return words.prefix(6).joined(separator: " ")
        }
        
        // 2. Fast Indexed Internal Deduplication
        var uniqueIncoming: [Song] = []
        var uniqueTokens: [Set<String>] = []
        var uniqueFoldedLyrics: [String] = []
        var duplicates: [DuplicateRecord] = []
        
        var titleToIndices: [String: [Int]] = [:]
        var prefixToIndices: [String: [Int]] = [:]
        var fullLyricsToIndices: [String: [Int]] = [:]
        
        for candidate in enrichedList {
            let cTitleFolded = Song.foldString(candidate.title)
            let cLyricsFolded = Song.foldString(candidate.rawLyrics)
            let cTokens = SongDeduplicationService.lyricsTokens(cLyricsFolded)
            let cPrefix = lyricsPrefixKey(cLyricsFolded)
            
            var matchedIndex: Int? = nil
            var highestSim = 0
            var duplicateReason = ""
            
            // Check 1: Identical full lyrics
            if !cLyricsFolded.isEmpty, let idxs = fullLyricsToIndices[cLyricsFolded], let first = idxs.first {
                matchedIndex = first
                highestSim = 100
                duplicateReason = Lnow("Identyczny tekst utworu (100% zgodności)")
            }
            // Check 2: Same folded title
            else if let idxs = titleToIndices[cTitleFolded] {
                for idx in idxs {
                    let sim = SongDeduplicationService.tokenSimilarity(cTokens, uniqueTokens[idx])
                    if sim >= 35 || cTokens.isEmpty {
                        matchedIndex = idx
                        highestSim = max(highestSim, sim)
                        duplicateReason = Lnow("Ten sam tytuł i zgodność tekstu ({0}%)", sim)
                        break
                    }
                }
            }
            // Check 3: Identical lyrics opening (first 6 words)
            if matchedIndex == nil && !cPrefix.isEmpty, let idxs = prefixToIndices[cPrefix] {
                for idx in idxs {
                    let sim = SongDeduplicationService.tokenSimilarity(cTokens, uniqueTokens[idx])
                    if sim >= 70 {
                        matchedIndex = idx
                        highestSim = sim
                        duplicateReason = Lnow("Identyczny początek i bardzo wysokie podobieństwo tekstu ({0}%)", sim)
                        break
                    }
                }
            }
            
            if let matchIdx = matchedIndex {
                let primary = uniqueIncoming[matchIdx]
                let candidateHasAuthor = !SongEnrichmentService.isUnknownAuthor(candidate.author)
                let primaryHasAuthor = !SongEnrichmentService.isUnknownAuthor(primary.author)
                
                // If candidate has better metadata than current primary, swap them
                if candidateHasAuthor && !primaryHasAuthor {
                    let replaced = uniqueIncoming[matchIdx]
                    uniqueIncoming[matchIdx] = candidate
                    uniqueTokens[matchIdx] = cTokens
                    uniqueFoldedLyrics[matchIdx] = cLyricsFolded
                    // Nowa pieśń główna musi być w indeksach, inaczej jej kolejne kopie przejdą niezauważone (N8).
                    func addIndex(_ index: inout [String: [Int]], _ key: String) {
                        guard !key.isEmpty, !(index[key]?.contains(matchIdx) ?? false) else { return }
                        index[key, default: []].append(matchIdx)
                    }
                    addIndex(&titleToIndices, cTitleFolded)
                    addIndex(&prefixToIndices, cPrefix)
                    addIndex(&fullLyricsToIndices, cLyricsFolded)
                    duplicates.append(DuplicateRecord(
                        primarySong: candidate,
                        duplicateSong: replaced,
                        reason: duplicateReason,
                        similarityScore: highestSim
                    ))
                } else {
                    duplicates.append(DuplicateRecord(
                        primarySong: primary,
                        duplicateSong: candidate,
                        reason: duplicateReason,
                        similarityScore: highestSim
                    ))
                }
            } else {
                let newIdx = uniqueIncoming.count
                uniqueIncoming.append(candidate)
                uniqueTokens.append(cTokens)
                uniqueFoldedLyrics.append(cLyricsFolded)
                
                titleToIndices[cTitleFolded, default: []].append(newIdx)
                if !cPrefix.isEmpty {
                    prefixToIndices[cPrefix, default: []].append(newIdx)
                }
                if !cLyricsFolded.isEmpty {
                    fullLyricsToIndices[cLyricsFolded, default: []].append(newIdx)
                }
            }
        }
        
        // 3. Fast Collision Check against Existing Library
        var existingCollisions: [DuplicateRecord] = []
        if !existingLibrary.isEmpty {
            // Wszystkie pieśni o danym tytule, nie tylko ostatnia (N8).
            var libTitleMap: [String: [Song]] = [:]
            for libSong in existingLibrary {
                libTitleMap[Song.foldString(libSong.title), default: []].append(libSong)
            }
            
            for (i, s) in uniqueIncoming.enumerated() {
                let sTitleFolded = Song.foldString(s.title)
                let candidates = (libTitleMap[sTitleFolded] ?? []).map { libSong in
                    (song: libSong, sim: SongDeduplicationService.tokenSimilarity(
                        uniqueTokens[i], SongDeduplicationService.lyricsTokens(Song.foldString(libSong.rawLyrics))))
                }
                if let best = candidates.max(by: { $0.sim < $1.sim }) {
                    let libSong = best.song
                    let sim = best.sim
                    existingCollisions.append(DuplicateRecord(
                        primarySong: libSong,
                        duplicateSong: s,
                        reason: Lnow("Utwór o tym tytule istnieje już w bibliotece ({0}% zgodności)", sim),
                        similarityScore: sim,
                        // Prawie identyczne pieśni (np. ponowny import własnego eksportu) domyślnie pomijamy.
                        shouldSkipDuplicate: sim >= 90
                    ))
                }
            }
        }
        
        return ImportProcessingResult(
            totalScanned: incoming.count,
            uniqueSongs: uniqueIncoming,
            duplicateRecords: duplicates,
            enrichmentRecords: enrichments,
            existingCollisions: existingCollisions
        )
    }
}
