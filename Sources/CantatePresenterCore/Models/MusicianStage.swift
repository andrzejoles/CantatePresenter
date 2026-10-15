import Foundation

// MARK: - Musician Stage

/// Stan ekranu dla muzyków: bieżący i następny slajd z chwytami nad tekstem. Ten sam model pokazuje
/// okno na Macu i strona na tabletach (JSON przez serwer pilota), więc oba widoki są zgodne.
public struct MusicianStage: Codable, Equatable, Sendable {
    public struct Slide: Codable, Equatable, Sendable {
        public var label: String
        public var lines: [ChordLine]
        /// Chwyty pożyczone z innej sekcji (np. pierwszej zwrotki).
        public var borrowedFrom: String?
    }

    public var isLive: Bool
    public var isBlackScreen: Bool
    public var isClearText: Bool
    public var songTitle: String
    public var author: String
    public var key: String
    public var semitones: Int
    public var position: String
    public var current: Slide?
    public var next: Slide?
    public var nextSongTitle: String?
    public var hasChords: Bool

    /// - Parameter semitones: transpozycja chwytów i tonacji, np. +2 albo −3 (capo).
    @MainActor
    public static func make(store: DataStore, semitones: Int) -> MusicianStage {
        let song = store.isLive ? store.activeSong : nil
        let shift = semitones % 12

        func slide(_ slide: SongSlide, of song: Song) -> Slide {
            let result = ChordSheet.lines(for: slide, sheet: song.chords, semitones: shift)
            return Slide(label: slide.displayLabel, lines: result.lines, borrowedFrom: result.borrowedFrom)
        }

        var current: Slide?
        var next: Slide?
        var position = ""
        if let song, store.activeSlideIndex < song.slides.count {
            current = slide(song.slides[store.activeSlideIndex], of: song)
            position = "\(store.activeSlideIndex + 1)/\(song.slides.count)"
            if store.activeSlideIndex + 1 < song.slides.count {
                next = slide(song.slides[store.activeSlideIndex + 1], of: song)
            }
        }
        let upcoming = store.upcomingSongInPlan
        if next == nil, let upcoming, let first = upcoming.slides.first, upcoming.id != song?.id {
            next = slide(first, of: upcoming)
        }

        let key = song.map { $0.key.isEmpty ? "" : ChordTransposer.transpose($0.key, semitones: shift) } ?? ""
        return MusicianStage(
            isLive: store.isLive,
            isBlackScreen: store.isBlackScreen,
            isClearText: store.isClearText,
            songTitle: song?.title ?? "",
            author: song?.author ?? "",
            key: key,
            semitones: shift,
            position: position,
            current: current,
            next: next,
            nextSongTitle: (song == nil || next == nil || store.activeSlideIndex + 1 >= (song?.slides.count ?? 0)) ? upcoming?.title : nil,
            hasChords: !(song?.chords ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
