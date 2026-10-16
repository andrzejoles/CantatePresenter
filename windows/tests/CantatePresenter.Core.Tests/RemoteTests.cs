using System.Net.Http;
using System.Text;
using System.Text.Json;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Models;
using CantatePresenter.Core.Remote;
using Xunit;

namespace CantatePresenter.Core.Tests;

/// <summary>Pilot ze smartfona i podgląd dla muzyków (jak RemoteControlTests w macOS).</summary>
public class RemoteTests
{
    private static RemoteHttpRequest Request(string raw)
    {
        var (status, request) = RemoteHttpRequest.Parse(Encoding.UTF8.GetBytes(raw));
        Assert.Equal(RemoteHttpRequest.Status.Complete, status);
        return request!;
    }

    private static string Body(RemoteHttpResponse response) => Encoding.UTF8.GetString(response.Body);

    [Fact]
    public void ParsesRequestsLikeMacOS()
    {
        var get = Request("GET /api/search?t=abc&q=%C5%9Bwi%C4%99ty+x HTTP/1.1\r\nHost: x\r\n\r\n");
        Assert.Equal("GET", get.Method);
        Assert.Equal("/api/search", get.Path);
        Assert.Equal("abc", get.Query["t"]);
        Assert.Equal("święty+x", get.Query["q"]);

        var post = Request("post /api/command?t=abc HTTP/1.1\r\nContent-Length: 18\r\n\r\n{\"command\":\"next\"}");
        Assert.Equal("POST", post.Method);
        Assert.IsType<RemoteCommand.Next>(RemoteCommand.FromJson(post.Body));

        Assert.Equal(RemoteHttpRequest.Status.Incomplete, RemoteHttpRequest.Parse("GET / HTTP/1.1\r\n"u8).Status);
        Assert.Equal(RemoteHttpRequest.Status.Incomplete, RemoteHttpRequest.Parse("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"u8).Status);
        Assert.Equal(RemoteHttpRequest.Status.Invalid, RemoteHttpRequest.Parse("GARBAGE\r\n\r\n"u8).Status);
        Assert.Equal(RemoteHttpRequest.Status.Invalid, RemoteHttpRequest.Parse(new byte[RemoteHttpRequest.MaxSize + 1]).Status);
    }

    [Fact]
    public void CommandsFromJson()
    {
        RemoteCommand? Parse(string json) => RemoteCommand.FromJson(Encoding.UTF8.GetBytes(json));
        Assert.Equal(new RemoteCommand.Slide(2), Parse("{\"command\":\"slide\",\"index\":2}"));
        Assert.Equal(new RemoteCommand.PlanItem(0), Parse("{\"command\":\"planItem\",\"index\":0}"));
        Assert.Null(Parse("{\"command\":\"slide\",\"index\":-1}"));
        Assert.Null(Parse("{\"command\":\"slide\"}"));
        Assert.Null(Parse("{\"command\":\"song\",\"id\":\"nie-uuid\"}"));
        Assert.Null(Parse("{\"command\":\"format\"}"));
        Assert.Null(Parse("nie json"));
        Assert.IsType<RemoteCommand.Song>(Parse("{\"command\":\"song\",\"id\":\"11111111-1111-1111-1111-111111111111\"}"));
    }

    private static (Library Library, Song First, Song Second) MakeLibrary(TempDirectory dir)
    {
        var library = new Library(new AppPaths(dir.Path));
        var first = library.AddSong(Song.Create("Pierwsza", "Autor A", rawLyrics: "Zwrotka jeden\ndruga linia\n\n[Refren]\nRefren tutaj", chords: "C G\nZwrotka jeden"));
        var second = library.AddSong(Song.Create("Święty dzień", rawLyrics: "Drugi tekst"));
        library.CreatePlan("Plan");
        library.AddSongToPlan(first.Id);
        library.AddSongToPlan(second.Id);
        // Bez zaznaczenia: „Start” bierze pierwszą pieśń z planu.
        library.SelectSong(null);
        return (library, first, second);
    }

    [Fact]
    public void RouterRequiresTokensAndMusiciansOnlyRead()
    {
        using var dir = new TempDirectory();
        var (library, first, _) = MakeLibrary(dir);
        var router = RemoteBridge.Router(library, "ctrl", "stage", s => s.Label);

        Assert.Equal(403, router.Respond(Request("GET / HTTP/1.1\r\n\r\n")).Status);
        Assert.Equal(403, router.Respond(Request("GET /api/state?t=ctrlx HTTP/1.1\r\n\r\n")).Status);
        var page = router.Respond(Request("GET /?t=ctrl HTTP/1.1\r\n\r\n"));
        Assert.Equal(200, page.Status);
        Assert.StartsWith("<!doctype html>\n<html lang=\"pl\">", Body(page));
        Assert.Contains("/api/state", Body(page));

        // Token muzyków: strona i stan podglądu, bez sterowania.
        Assert.Contains("/api/stage", Body(router.Respond(Request("GET /stage?t=stage HTTP/1.1\r\n\r\n"))));
        Assert.Equal(403, router.Respond(Request("GET /api/state?t=stage HTTP/1.1\r\n\r\n")).Status);
        Assert.Equal(403, router.Respond(Request("POST /api/command?t=stage HTTP/1.1\r\nContent-Length: 18\r\n\r\n{\"command\":\"next\"}")).Status);
        Assert.Equal(405, router.Respond(Request("POST /stage?t=stage HTTP/1.1\r\n\r\n")).Status);
        Assert.Equal(404, router.Respond(Request("GET /nic?t=ctrl HTTP/1.1\r\n\r\n")).Status);
        Assert.Equal(400, router.Respond(Request("POST /api/command?t=ctrl HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}")).Status);

        library.Present(first);
        var stage = JsonDocument.Parse(router.Respond(Request("GET /api/stage?t=stage&transpose=2 HTTP/1.1\r\n\r\n")).Body).RootElement;
        // Te same nazwy pól co JSON z macOS (strona dla muzyków jest wspólna).
        Assert.True(stage.GetProperty("stage").GetProperty("isLive").GetBoolean());
        Assert.Equal(2, stage.GetProperty("stage").GetProperty("semitones").GetInt32());
        Assert.Equal("D A", stage.GetProperty("stage").GetProperty("current").GetProperty("lines")[0].GetProperty("chords").GetString()?.Trim());
        Assert.Equal("Tonacja: {0}", stage.GetProperty("labels").GetProperty("key").GetString());
    }

    [Fact]
    public void StateCommandsStartAndResume()
    {
        using var dir = new TempDirectory();
        var (library, first, second) = MakeLibrary(dir);
        var router = RemoteBridge.Router(library, "ctrl", "stage", s => s.Label);
        JsonElement Command(string json) => JsonDocument.Parse(router.Respond(Request(
            $"POST /api/command?t=ctrl HTTP/1.1\r\nContent-Length: {Encoding.UTF8.GetByteCount(json)}\r\n\r\n{json}")).Body).RootElement;

        var state = JsonDocument.Parse(router.Respond(Request("GET /api/state?t=ctrl HTTP/1.1\r\n\r\n")).Body).RootElement;
        Assert.False(state.GetProperty("isLive").GetBoolean());
        Assert.True(state.GetProperty("canStart").GetBoolean());
        Assert.Equal("Pierwsza", state.GetProperty("startTitle").GetString());
        Assert.Equal("Dalej", state.GetProperty("labels").GetProperty("next").GetString());

        state = Command("{\"command\":\"start\"}");
        Assert.True(state.GetProperty("isLive").GetBoolean());
        Assert.Equal("Pierwsza", state.GetProperty("songTitle").GetString());
        Assert.Equal("Zwrotka jeden", state.GetProperty("slides")[0].GetProperty("preview").GetString());
        Assert.True(state.GetProperty("plan")[0].GetProperty("isCurrent").GetBoolean());

        state = Command("{\"command\":\"next\"}");
        Assert.Equal(1, state.GetProperty("slideIndex").GetInt32());
        Assert.Equal("Refren tutaj", state.GetProperty("slideText").GetString());
        Assert.True(Command("{\"command\":\"black\"}").GetProperty("isBlackScreen").GetBoolean());

        // Zatrzymanie i wznowienie w tym samym miejscu.
        Command("{\"command\":\"stop\"}");
        state = Command("{\"command\":\"start\"}");
        Assert.Equal(1, state.GetProperty("slideIndex").GetInt32());
        Assert.False(state.GetProperty("isBlackScreen").GetBoolean());

        state = Command("{\"command\":\"planItem\",\"index\":1}");
        Assert.Equal("Święty dzień", state.GetProperty("songTitle").GetString());
        Assert.Equal(second.Id, library.SelectedSongId);
        state = Command($"{{\"command\":\"song\",\"id\":\"{first.Id.ToLowerInvariant()}\"}}");
        Assert.Equal("Pierwsza", state.GetProperty("songTitle").GetString());
        Assert.Equal("Pierwsza", Command("{\"command\":\"song\",\"id\":\"22222222-2222-2222-2222-222222222222\"}").GetProperty("songTitle").GetString());

        // Wybór slajdu po zatrzymaniu uruchamia projekcję od tego slajdu.
        Command("{\"command\":\"stop\"}");
        state = Command("{\"command\":\"slide\",\"index\":1}");
        Assert.True(state.GetProperty("isLive").GetBoolean());
        Assert.Equal(1, state.GetProperty("slideIndex").GetInt32());
    }

    [Fact]
    public void SearchIgnoresDiacriticsAndPutsTitlesFirst()
    {
        using var dir = new TempDirectory();
        var (library, _, _) = MakeLibrary(dir);
        library.AddSong(Song.Create("Inna", rawLyrics: "W tekście jest swiety"));
        var results = RemoteBridge.Search("swiety", library);
        Assert.Equal(["Święty dzień", "Inna"], results.Select(r => r.Title));
        Assert.Equal("Drugi tekst", results[0].FirstLine);
        Assert.Empty(RemoteBridge.Search("  ", library));
    }

    [Fact]
    public void TokensAreUrlSafe128Bit()
    {
        var token = RemoteRouter.MakeToken();
        Assert.Equal(22, token.Length);
        Assert.Matches("^[A-Za-z0-9_-]+$", token);
        Assert.NotEqual(token, RemoteRouter.MakeToken());
        Assert.True(RemoteRouter.ConstantTimeEquals("abc", "abc"));
        Assert.False(RemoteRouter.ConstantTimeEquals("abc", "abd"));
        Assert.False(RemoteRouter.ConstantTimeEquals("abc", "abcd"));
    }

    [Fact]
    public void ResponseHeaders()
    {
        var text = Encoding.UTF8.GetString(RemoteHttpResponse.Text("ok", 200).Serialized());
        Assert.StartsWith("HTTP/1.1 200 OK\r\n", text);
        Assert.Contains("Cache-Control: no-store\r\n", text);
        Assert.Contains("Connection: close\r\n", text);
        Assert.EndsWith("\r\n\r\nok", text);
    }

    [Fact]
    public async Task ServerAnswersOverRealTcpAndCountsPhones()
    {
        using var dir = new TempDirectory();
        var (library, _, _) = MakeLibrary(dir);
        using var server = new RemoteServer((request, token, stageToken) =>
            Task.FromResult(RemoteBridge.Router(library, token, stageToken, s => s.Label).Respond(request)));
        server.Start(0);
        Assert.True(server.IsRunning);
        using var http = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{server.Port}") };

        Assert.Equal(System.Net.HttpStatusCode.Forbidden, (await http.GetAsync("/api/state")).StatusCode);
        Assert.Equal(0, server.ConnectedDevices());
        var state = await http.GetStringAsync($"/api/state?t={server.Token}");
        Assert.Contains("\"canStart\":true", state);
        Assert.Equal(1, server.ConnectedDevices());
        Assert.Equal(0, server.ConnectedDevices(DateTime.UtcNow + RemoteServer.ConnectedWindow));

        var posted = await http.PostAsync($"/api/command?t={server.Token}", new StringContent("{\"command\":\"start\"}"));
        Assert.Contains("\"isLive\":true", await posted.Content.ReadAsStringAsync());
        Assert.True(library.IsLive);

        // Nowy kod rozłącza dotychczasowe telefony.
        var oldToken = server.Token;
        server.RegenerateTokens();
        Assert.Equal(System.Net.HttpStatusCode.Forbidden, (await http.GetAsync($"/api/state?t={oldToken}")).StatusCode);
        Assert.Equal(0, server.ConnectedDevices());

        // Drugi serwer na zajętym porcie przechodzi na wolny.
        using var other = new RemoteServer((_, _, _) => Task.FromResult(RemoteHttpResponse.Text("x", 200)));
        other.Start(server.Port!.Value);
        Assert.True(other.IsRunning);
        Assert.NotEqual(server.Port, other.Port);

        server.Stop();
        Assert.False(server.IsRunning);
        await Assert.ThrowsAnyAsync<HttpRequestException>(() => http.GetAsync($"/api/state?t={server.Token}"));
    }

    [Fact]
    public void QrMatchesWebEncoder()
    {
        foreach (var item in Fixtures.Load("qr.json").EnumerateArray())
        {
            var text = item.Str("text")!;
            var expected = item.GetProperty("rows").EnumerateArray().Select(r => r.GetString()).ToArray();
            Assert.Equal(expected, QrCode.Rows(QrCode.Encode(text)));
        }
        Assert.Throws<ArgumentException>(() => QrCode.Encode(new string('x', 400)));
    }
}
