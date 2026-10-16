using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Presentation;

public sealed record MusicianSlide(string Label, IReadOnlyList<ChordLine> Lines, string? BorrowedFrom);

/// <summary>Ekran dla muzyków: bieżący i następny slajd z chwytami nad tekstem (jak MusicianStage w macOS).</summary>
public sealed record MusicianStage(bool IsLive, bool IsBlackScreen, bool IsClearText, string SongTitle, string Author, string Key,
    int Semitones, string Position, MusicianSlide? Current, MusicianSlide? Next, string? NextSongTitle, bool HasChords)
{
    public static MusicianStage Make(Library library, int semitones, Func<SongSlide, string> label)
    {
        var song = library.IsLive ? library.ActiveSong : null;
        var shift = semitones % 12;
        MusicianSlide Slide(SongSlide slide, Song owner)
        {
            var result = ChordSheet.LinesForSlide(slide.Text, slide.Type, owner.Chords, shift);
            return new MusicianSlide(label(slide), result.Lines, result.BorrowedFrom);
        }
        MusicianSlide? current = null, next = null;
        var position = "";
        var index = library.ActiveSlideIndex;
        if (song is not null && index < song.Slides.Count)
        {
            current = Slide(song.Slides[index], song);
            position = $"{index + 1}/{song.Slides.Count}";
            if (index + 1 < song.Slides.Count) next = Slide(song.Slides[index + 1], song);
        }
        var upcoming = library.UpcomingSongInPlan;
        if (next is null && upcoming?.Slides.FirstOrDefault() is SongSlide first && upcoming.Id != song?.Id) next = Slide(first, upcoming);
        var key = song is not null && song.Key.Length > 0 ? ChordTransposer.Transpose(song.Key, shift) : "";
        return new MusicianStage(library.IsLive, library.IsBlackScreen, library.IsClearText, song?.Title ?? "", song?.Author ?? "", key, shift, position,
            current, next, song is null || next is null || index + 1 >= song.Slides.Count ? upcoming?.Title : null, !string.IsNullOrWhiteSpace(song?.Chords));
    }
}
