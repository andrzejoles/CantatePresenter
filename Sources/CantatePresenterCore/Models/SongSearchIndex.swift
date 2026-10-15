import Foundation

// MARK: - Song Search Index

/// Złożone (bez polskich znaków, małe litery) pola pieśni liczone raz przy zmianie biblioteki,
/// a nie przy każdym przerysowaniu listy i każdym naciśnięciu klawisza (S2).
/// Semantyka wyszukiwania jest taka sama jak `Song.matches(query:scope:)`.
public struct SongSearchIndex {
    private struct Entry {
        // Pola źródłowe: tylko one wpływają na wynik, więc tylko je porównujemy przy sprawdzaniu aktualności.
        let sourceTitle: String
        let sourceAuthor: String
        let sourceTags: [String]
        let sourceLyrics: String
        // Złożone pola jako NSString: dosłowne `range(of:)` jest dużo szybsze niż `String.contains`.
        let title: NSString
        let author: NSString
        let tags: [NSString]
        let lyrics: NSString
        
        init(_ song: Song) {
            sourceTitle = song.title
            sourceAuthor = song.author
            sourceTags = song.tags
            sourceLyrics = song.rawLyrics
            title = Song.searchFold(song.title) as NSString
            author = Song.searchFold(song.author) as NSString
            tags = song.tags.map { Song.searchFold($0) as NSString }
            lyrics = Song.searchFold(song.rawLyrics) as NSString
        }
        
        func isCurrent(for song: Song) -> Bool {
            sourceTitle == song.title && sourceAuthor == song.author && sourceTags == song.tags && sourceLyrics == song.rawLyrics
        }
    }
    
    private var entries: [UUID: Entry] = [:]
    
    public init() {}
    
    /// Przelicza tylko pieśni nowe lub zmienione; zwraca ich liczbę.
    @discardableResult
    public mutating func update(with songs: [Song]) -> Int {
        var updated: [UUID: Entry] = [:]
        updated.reserveCapacity(songs.count)
        var recomputed = 0
        for song in songs {
            if let existing = entries[song.id], existing.isCurrent(for: song) {
                updated[song.id] = existing
            } else {
                updated[song.id] = Entry(song)
                recomputed += 1
            }
        }
        entries = updated
        return recomputed
    }
    
    public func filter(_ songs: [Song], query: String, scope: Song.SearchScope) -> [Song] {
        let folded = Song.searchFold(query)
        guard !folded.isEmpty else { return songs }
        return songs.filter { song in
            guard let entry = entries[song.id], entry.isCurrent(for: song) else {
                // Pieśń spoza indeksu (np. tymczasowa): ścieżka bez cache.
                return song.matches(query: query, scope: scope)
            }
            func has(_ text: NSString) -> Bool {
                text.range(of: folded, options: .literal).location != NSNotFound
            }
            switch scope {
            case .all:
                return has(entry.title) || has(entry.author) || entry.tags.contains(where: has) || has(entry.lyrics)
            case .titleAndAuthor:
                return has(entry.title) || has(entry.author)
            case .titleOnly:
                return has(entry.title)
            case .authorOnly:
                return has(entry.author)
            }
        }
    }
}
