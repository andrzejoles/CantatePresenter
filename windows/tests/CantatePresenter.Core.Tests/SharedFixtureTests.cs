using System.Text.Json;
using CantatePresenter.Core.Chords;
using CantatePresenter.Core.Input;
using CantatePresenter.Core.Text;
using Xunit;

namespace CantatePresenter.Core.Tests;

public class SharedFixtureTests
{
    [Fact]
    public void Lyrics()
    {
        foreach (var f in Fixtures.Load("lyrics.json").EnumerateArray())
        {
            var name = f.Str("name") ?? f.Str("input");
            var slides = LyricsParser.Parse(f.Str("input"));
            var expected = f.GetProperty("expected").EnumerateArray().ToList();
            Assert.True(expected.Count == slides.Count, $"{name}: {slides.Count} zamiast {expected.Count}");
            for (var i = 0; i < expected.Count; i++)
            {
                Assert.Equal(expected[i].Str("type"), slides[i].Type);
                Assert.Equal(expected[i].Str("label"), slides[i].Label);
                Assert.Equal(expected[i].Str("text"), slides[i].Text);
                int? number = expected[i].TryGetProperty("number", out var n) && n.ValueKind == JsonValueKind.Number ? n.GetInt32() : null;
                Assert.Equal(number, slides[i].Number);
            }
        }
    }

    [Fact]
    public void Search()
    {
        foreach (var f in Fixtures.Load("search.json").EnumerateArray())
        {
            Assert.Equal(f.Str("fold"), TextFold.Fold(f.Str("input")));
            Assert.Equal(f.Str("searchFold"), TextFold.SearchFold(f.Str("input")));
        }
    }

    [Fact]
    public void Transpose()
    {
        foreach (var f in Fixtures.Load("transpose.json").EnumerateArray())
        {
            Assert.Equal(f.Str("expected"), ChordTransposer.Transpose(f.Str("sheet")!, f.GetProperty("semitones").GetInt32()));
        }
    }

    [Fact]
    public void ChordSheetForMusicians()
    {
        foreach (var f in Fixtures.Load("chordsheet.json").EnumerateArray())
        {
            var slide = f.GetProperty("slide");
            var semitones = f.TryGetProperty("semitones", out var s) ? s.GetInt32() : 0;
            var result = ChordSheet.LinesForSlide(slide.Str("text")!, slide.Str("type")!, f.Str("sheet"), semitones);
            var expected = f.GetProperty("expected");
            var lines = expected.GetProperty("lines").EnumerateArray().Select(l => new ChordLine(l.Str("chords"), l.Str("text")!)).ToList();
            Assert.Equal(lines, result.Lines);
            Assert.Equal(expected.Str("borrowedFrom"), result.BorrowedFrom);
        }
    }

    [Fact]
    public void Keyboard()
    {
        foreach (var f in Fixtures.Load("keyboard.json").EnumerateArray())
        {
            KeyContext? context = null;
            if (f.TryGetProperty("context", out var c) && c.ValueKind == JsonValueKind.Object)
            {
                context = c.Str("kind") == "presentation" ? KeyContext.Presentation : KeyContext.Main(c.Str("focus") switch
                {
                    "text" => KeyFocus.Text, "multilineText" => KeyFocus.MultilineText, "list" => KeyFocus.List, _ => KeyFocus.Other,
                });
            }
            int? macCode = f.TryGetProperty("macCode", out var m) && m.ValueKind == JsonValueKind.Number ? m.GetInt32() : null;
            var action = KeyboardRouter.Action(macCode, f.Str("characters") ?? "", f.GetProperty("command").GetBoolean(), new ShortcutSettings(), context);
            var expected = f.GetProperty("expected");
            if (expected.ValueKind == JsonValueKind.Null)
            {
                Assert.True(action is null, f.Str("note"));
            }
            else
            {
                int? number = expected.TryGetProperty("number", out var n) ? n.GetInt32() : null;
                Assert.Equal(new KeyboardAction(expected.Str("type")!, number), action);
            }
        }
    }
}

public class SharedImportFixtureTests
{
    [Fact]
    public void Holyrics()
    {
        var f = Fixtures.Load("holyrics.json");
        foreach (var file in f.GetProperty("files").EnumerateArray())
        {
            var name = file.Str("file")!;
            var songs = CantatePresenter.Core.Import.HolyricsImporter.ReadFile(File.ReadAllBytes(Fixtures.PathOf(name)), name);
            var expected = file.GetProperty("songs").EnumerateArray().ToList();
            Assert.Equal(expected.Count, songs.Count);
            for (var i = 0; i < expected.Count; i++)
            {
                Assert.Equal(expected[i].Str("title"), songs[i].Title);
                Assert.Equal(expected[i].Str("author"), songs[i].Author);
                Assert.Equal(expected[i].Str("key"), songs[i].Key);
                Assert.Equal(expected[i].GetProperty("tags").EnumerateArray().Select(t => t.GetString()!).ToList(), songs[i].Tags);
                Assert.Equal(expected[i].Str("rawLyrics"), songs[i].RawLyrics);
            }
        }
        foreach (var name in f.GetProperty("invalidStreams").EnumerateArray().Select(n => n.GetString()!))
        {
            Assert.Throws<CantatePresenter.Core.Import.HolyricsException>(() =>
                CantatePresenter.Core.Import.HolyricsJavaDeserializer.DeserializeMusicRecords(File.ReadAllBytes(Fixtures.PathOf(name))));
        }
        // Zapętlone zagnieżdżenie nie przepełnia stosu.
        var nested = new byte[] { 0xAC, 0xED, 0x00, 0x05 }.Concat(Enumerable.Repeat((byte)0x75, 200)).ToArray();
        Assert.Throws<CantatePresenter.Core.Import.HolyricsException>(() => CantatePresenter.Core.Import.HolyricsJavaDeserializer.DeserializeMusicRecords(nested));
    }

    [Fact]
    public void Wikisource()
    {
        var f = Fixtures.Load("wikisource.json");
        foreach (var page in f.GetProperty("pages").EnumerateArray())
        {
            Assert.Equal(page.Str("lyrics"), CantatePresenter.Core.Online.Wikisource.LyricsFromHtml(page.Str("html")!));
            Assert.Equal(page.Str("license"), CantatePresenter.Core.Online.Wikisource.LicenseFromHtml(page.Str("html")!));
        }
        foreach (var a in f.GetProperty("authors").EnumerateArray()) Assert.Equal(a.Str("author"), CantatePresenter.Core.Online.Wikisource.AuthorFromWikitext(a.Str("wikitext")!));
        foreach (var t in f.GetProperty("titles").EnumerateArray()) Assert.Equal(t.Str("title"), CantatePresenter.Core.Online.Wikisource.ShortTitle(t.Str("page")!));
        foreach (var u in f.GetProperty("urls").EnumerateArray()) Assert.Equal(u.Str("url"), CantatePresenter.Core.Online.Wikisource.PageUrl(u.Str("page")!, u.Str("language")!));
    }
}
