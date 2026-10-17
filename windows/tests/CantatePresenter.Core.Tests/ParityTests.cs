using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Online;
using Xunit;

namespace CantatePresenter.Core.Tests;

/// <summary>Funkcje przeniesione z macOS przy wyrównywaniu interfejsu: baza chwytów, Tytuł/Autor, ustawienia paska i sortowania.</summary>
public class ParityTests
{
    private static string RepoRoot => Path.GetFullPath(Path.Combine(Fixtures.Directory, "..", ".."));

    [Fact]
    public void ChordsCatalogMatchesMacSource()
    {
        // Eksport windows/tools/export_chords_catalog.py musi odpowiadać bazie w GuitarChordsService.swift.
        var swift = File.ReadAllText(Path.Combine(RepoRoot, "Sources", "CantatePresenterCore", "Services", "GuitarChordsService.swift"));
        var titles = Regex.Matches(swift, @"add\(""([^""]+)"",\s*key:").Select(m => m.Groups[1].Value).ToList();
        Assert.NotEmpty(titles);
        Assert.Equal(titles, ChordsCatalog.All.Select(e => e.Title));
        Assert.All(ChordsCatalog.All, e => Assert.False(string.IsNullOrWhiteSpace(e.ChordsSheet)));
    }

    [Fact]
    public void ChordsCatalogSearchesByFoldedTitle()
    {
        Assert.Equal("Barka", ChordsCatalog.Search("barka").First().Title);
        Assert.Equal("Bóg się rodzi", ChordsCatalog.Search("BOG SIE RODZI").First().Title);
        // Fragment w jedną lub drugą stronę, jak w macOS.
        Assert.Contains(ChordsCatalog.Search("Barka (wersja oazowa)"), r => r.Title == "Barka");
        Assert.Empty(ChordsCatalog.Search(""));
        Assert.Empty(ChordsCatalog.Search("Pieśń, której nie ma w bazie"));
    }

    [Fact]
    public void SuggestedQueryUsesFirstLyricsLineOrCleanTitle()
    {
        var song = Song.Create("Barka", rawLyrics: "[Zwrotka 1]\nPan kiedyś stanął nad brzegiem, szukał ludzi gotowych\nSzukał ludzi");
        Assert.Equal("Pan kiedyś stanął nad brzegiem, szukał", AuthorTitleLookup.SuggestedQuery(song));
        // Krótkie linie pomijane, wtedy tytuł bez numeru i rozszerzenia.
        Assert.Equal("Barka", AuthorTitleLookup.SuggestedQuery(Song.Create("01. Barka.txt", rawLyrics: "Ala ma")));
        Assert.Equal("Abba Ojcze", AuthorTitleLookup.SuggestedQuery(Song.Create("12 - Abba Ojcze")));
    }

    [Fact]
    public void ScoresCandidatesLikeMacOs()
    {
        var song = Song.Create("Kiedy ranne wstają zorze", rawLyrics: "Kiedy ranne wstają zorze, Tobie ziemia, Tobie morze");
        // Ten sam tytuł (+40), wszystkie słowa wspólne (+35), autor podany: 30 + 40 + 35 = 105 → 99.
        Assert.Equal(99, AuthorTitleLookup.Score(song, "Kiedy ranne wstają zorze", "Franciszek Karpiński", song.RawLyrics));
        // Tytuł zawiera tytuł pieśni (+25), brak wspólnych słów, brak autora (−10).
        Assert.Equal(45, AuthorTitleLookup.Score(song, "Kiedy ranne wstają zorze (pieśń poranna)", "", "Zupełnie inny tekst"));
        // Nic wspólnego: 30 − 10 = 20.
        Assert.Equal(20, AuthorTitleLookup.Score(song, "Inna", "", "nic"));
        var best = AuthorTitleLookup.Best(song,
        [
            (new LookupCandidate("Inna", "", "Wikiźródła", ""), "nic"),
            (new LookupCandidate("Kiedy ranne wstają zorze", "Franciszek Karpiński", "Wikiźródła", ""), song.RawLyrics),
        ]);
        Assert.NotNull(best);
        Assert.Equal("Franciszek Karpiński", best.ProposedAuthor);
        Assert.True(best.IsSelected);
        Assert.Null(AuthorTitleLookup.Best(song, []));
    }

    [Fact]
    public void BottomBarHeightAndSortOrderAreTolerant()
    {
        var defaults = AppSettings.Default();
        Assert.Equal(72, defaults.BottomBarHeight);
        Assert.Equal("titleAsc", defaults.SongSortOrder);
        var settings = AppSettings.FromJson(JsonNode.Parse("""{"bottomBarHeight": 500, "songSortOrder": "nieznane"}"""));
        Assert.Equal(160, settings.BottomBarHeight);
        Assert.Equal("titleAsc", settings.SongSortOrder);
        settings.BottomBarHeight = 10;
        settings.SongSortOrder = "newest";
        var reloaded = AppSettings.FromJson(settings.ToJson());
        Assert.Equal(52, reloaded.BottomBarHeight);
        Assert.Equal("newest", reloaded.SongSortOrder);
        // Wartość z macOS (np. 96.0) zostaje bez zmian.
        Assert.Equal(96, AppSettings.FromJson(JsonNode.Parse("""{"bottomBarHeight": 96.0}""")).BottomBarHeight);
    }
}
