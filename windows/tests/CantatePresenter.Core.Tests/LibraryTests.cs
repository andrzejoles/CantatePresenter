using System.Text.Json.Nodes;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Models;
using Xunit;

namespace CantatePresenter.Core.Tests;

/// <summary>Katalog tymczasowy; testy nigdy nie dotykają prawdziwego katalogu danych.</summary>
public sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "CantateTests-" + Guid.NewGuid(), "data");
    public TempDirectory() => Directory.CreateDirectory(Path);
    public string File(string name) => System.IO.Path.Combine(Path, name);
    public void Dispose() => Directory.Delete(System.IO.Path.GetDirectoryName(Path)!, recursive: true);
}

public class LibraryTests
{
    [Fact]
    public void HasChordsOnlyForNonEmptySheet()
    {
        var song = Song.Create("A", rawLyrics: "x");
        Assert.False(song.HasChords);
        song.Chords = "  \n ";
        Assert.False(song.HasChords);
        song.Chords = "G  D\nTekst";
        Assert.True(song.HasChords);
    }

    [Fact]
    public void FirstRunCreatesSamplesAndCurrentSchema()
    {
        using var dir = new TempDirectory();
        var library = new Library(new AppPaths(dir.Path));
        Assert.Equal(2, library.Songs.Count);
        Assert.Single(library.Plans);
        Assert.Equal(1, Json.Int(JsonNode.Parse(File.ReadAllText(dir.File("settings.json")))!["schemaVersion"]));
        Assert.Empty(library.Issues);
    }

    [Fact]
    public void MacOsFieldsSurviveRoundTrip()
    {
        using var dir = new TempDirectory();
        File.WriteAllText(dir.File("settings.json"), """{"appLanguage":"de","selectedScreenID":42,"googleDrive":{"isEnabled":true,"targetFolder":"X"},"marginPercent":5}""");
        File.WriteAllText(dir.File("songs.json"), """[{"id":"6f1c5a39-2b5e-4f0b-9c55-111111111111","title":"A","rawLyrics":"Tekst 1\n\nTekst 2","futureField":{"x":1},"createdAt":782000000,"ccliNumber":123}]""");
        File.WriteAllText(dir.File("plans.json"), """[{"id":"6f1c5a39-2b5e-4f0b-9c55-222222222222","name":"P","items":[{"songId":"6f1c5a39-2b5e-4f0b-9c55-111111111111","x":1},{"note":"bez pieśni"}]}]""");
        var library = new Library(new AppPaths(dir.Path));
        Assert.Equal("de", library.Settings.AppLanguage);
        Assert.Equal(0.3, library.Settings.MarginPercent);
        var song = Assert.Single(library.Songs);
        Assert.Equal("6F1C5A39-2B5E-4F0B-9C55-111111111111", song.Id);
        Assert.Equal("123", song.CcliNumber);
        Assert.Equal(2, song.Slides.Count);
        Assert.StartsWith("2025-", song.CreatedAt);
        Assert.Single(Assert.Single(library.Plans).Items);

        library.UpdateSettings(s => s.FontFamily = "Arial");
        library.UpdateSong(song);
        library.SavePlans();
        var settings = JsonNode.Parse(File.ReadAllText(dir.File("settings.json")))!;
        Assert.Equal(42, Json.Int(settings["selectedScreenID"]));
        Assert.Equal("X", Json.Str(settings["googleDrive"]?["targetFolder"]));
        var saved = JsonNode.Parse(File.ReadAllText(dir.File("songs.json")))![0]!;
        Assert.Equal(1, Json.Int(saved["futureField"]?["x"]));
        Assert.Equal(1, Json.Int(JsonNode.Parse(File.ReadAllText(dir.File("plans.json")))![0]!["items"]![0]!["x"]));
        Assert.True(Directory.GetFiles(Path.Combine(dir.Path, "history")).Length >= 2);
    }

    [Fact]
    public void UnreadableFileIsQuarantinedAndNotOverwritten()
    {
        using var dir = new TempDirectory();
        File.WriteAllText(dir.File("songs.json"), "{nie json");
        var library = new Library(new AppPaths(dir.Path));
        Assert.Empty(library.Songs);
        Assert.Contains(library.Issues, i => i.Kind == PersistenceIssueKind.Unreadable && i.FileName == "songs.json");
        Assert.Single(Directory.GetFiles(dir.Path, "songs.corrupt-*.json"));
        library.AddSong(Song.Create("Nowa"));
        Assert.Equal("{nie json", File.ReadAllText(dir.File("songs.json")));
    }

    [Fact]
    public void NewerSchemaIsReadOnly()
    {
        using var dir = new TempDirectory();
        const string settings = """{"schemaVersion":99,"appLanguage":"de"}""";
        File.WriteAllText(dir.File("settings.json"), settings);
        File.WriteAllText(dir.File("songs.json"), "[]");
        var library = new Library(new AppPaths(dir.Path));
        Assert.True(library.IsReadOnlyNewerSchema);
        Assert.Contains(library.Issues, i => i.Kind == PersistenceIssueKind.NewerSchema);
        library.AddSong(Song.Create("Nowa"));
        library.UpdateSettings(s => s.AppLanguage = "pl");
        Assert.Equal("[]", File.ReadAllText(dir.File("songs.json")));
        Assert.Equal(settings, File.ReadAllText(dir.File("settings.json")));
    }

    [Fact]
    public void PresentationNavigationPlanAndResume()
    {
        using var dir = new TempDirectory();
        var library = new Library(new AppPaths(dir.Path));
        var first = library.AddSong(Song.Create("Pierwsza", rawLyrics: "A1\n\n[Refren]\nR\n\nA2"));
        var second = library.AddSong(Song.Create("Druga", rawLyrics: "B1"));
        library.CreatePlan("Plan");
        library.AddSongToPlan(first.Id);
        library.AddSongToPlan(second.Id);

        library.Present(first);
        library.JumpToChorus();
        Assert.Equal(1, library.ActiveSlideIndex);
        library.NextSlide();
        library.NextSlide();
        Assert.Equal("Druga", library.ActiveSong?.Title);
        library.PrevSongInPlan();
        Assert.Equal("Pierwsza", library.ActiveSong?.Title);

        library.JumpToVerse(2);
        Assert.Equal(2, library.ActiveSlideIndex);
        library.StopLive();
        library.StartOrResume();
        Assert.True(library.IsLive);
        Assert.Equal(2, library.ActiveSlideIndex);

        library.PresentQuickText("Ogłoszenie", null);
        Assert.Null(library.SongById(library.ActiveSong!.Id));
        library.NextSongInPlan();
        Assert.Equal("Druga", library.ActiveSong?.Title);
    }

    [Fact]
    public void CcliUsageOncePerDayAndCsv()
    {
        using var dir = new TempDirectory();
        var library = new Library(new AppPaths(dir.Path));
        var song = library.AddSong(Song.Create("Pieśń, \"cytat\"", "Autor"));
        song.CcliNumber = "55";
        song.Copyright = "© 2020";
        library.Present(song);
        library.Present(song);
        Assert.Single(library.CcliUsage);
        var csv = Ccli.UsageCsv(library.CcliUsage);
        Assert.StartsWith("Date,Title,Authors,CCLI Song Number,Copyright\r\n", csv);
        Assert.Contains("\"Pieśń, \"\"cytat\"\"\",Autor,55,© 2020\r\n", csv);
        Assert.Equal("Pieśń, \"cytat\" · Autor · © 2020 · Pieśń CCLI nr 55", library.CurrentCopyrightNotice);
    }
}

public class BackupTests
{
    [Fact]
    public void MacOsBackupRestoresAndCanBeUndone()
    {
        using var dir = new TempDirectory();
        var library = new Library(new AppPaths(dir.Path));
        var before = library.Songs.Count;
        var result = Backup.Restore(Fixtures.PathOf("backup-macos.cantatebackup"), dir.Path, Library.Format);
        Assert.Equal(2, result.SongsCount);
        library.Reload();
        Assert.Equal(2, library.Songs.Count);
        Assert.Equal("left", library.Settings.TextAlignment);
        Assert.True(File.Exists(dir.File("ccli_usage.json")));
        Assert.True(Backup.CanUndo(dir.Path));
        Backup.UndoLastRestore(dir.Path, Library.Format);
        library.Reload();
        Assert.Equal(before, library.Songs.Count);
    }

    [Fact]
    public void CreatedBackupRoundTripsAndNewerIsRejected()
    {
        using var dir = new TempDirectory();
        var library = new Library(new AppPaths(dir.Path));
        library.AddSong(Song.Create("Z kopii", rawLyrics: "tekst"));
        var archive = Path.Combine(Path.GetDirectoryName(dir.Path)!, Backup.FileName());
        Backup.Create(library, archive, "1.0.0", "test");
        using (var zip = System.IO.Compression.ZipFile.OpenRead(archive))
        {
            Assert.Contains(zip.Entries, e => e.FullName == "manifest.json");
            Assert.Contains(zip.Entries, e => e.FullName == "songs.json");
        }
        library.DeleteSong(library.Songs[0].Id);
        Backup.Restore(archive, dir.Path, Library.Format);
        library.Reload();
        Assert.Contains(library.Songs, s => s.Title == "Z kopii");

        var newer = Path.Combine(Path.GetDirectoryName(dir.Path)!, "newer.zip");
        using (var zip = System.IO.Compression.ZipFile.Open(newer, System.IO.Compression.ZipArchiveMode.Create))
        {
            using (var w = new StreamWriter(zip.CreateEntry("songs.json").Open())) w.Write("[]");
            using (var w = new StreamWriter(zip.CreateEntry("settings.json").Open())) w.Write("""{"schemaVersion":99}""");
        }
        Assert.Throws<BackupException>(() => Backup.Restore(newer, dir.Path, Library.Format));
        Assert.Throws<BackupException>(() => Backup.Restore(Fixtures.PathOf("lyrics.json"), dir.Path, Library.Format));
    }
}
