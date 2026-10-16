using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace CantatePresenter.Core.Remote;

/// <summary>Polecenia z pilota (kody w JSON stałe, jak RemoteCommand w macOS).</summary>
public abstract record RemoteCommand
{
    public sealed record Next : RemoteCommand;
    public sealed record Previous : RemoteCommand;
    public sealed record NextSong : RemoteCommand;
    public sealed record PreviousSong : RemoteCommand;
    public sealed record Black : RemoteCommand;
    public sealed record ClearText : RemoteCommand;
    public sealed record Stop : RemoteCommand;
    /// <summary>Uruchomienie albo wznowienie projekcji po zatrzymaniu.</summary>
    public sealed record Start : RemoteCommand;
    public sealed record Slide(int Index) : RemoteCommand;
    public sealed record PlanItem(int Index) : RemoteCommand;
    /// <summary>Pieśń z wyszukiwania: {"command":"song","id":"&lt;UUID&gt;"}.</summary>
    public sealed record Song(string Id) : RemoteCommand;

    /// <summary>Treść POST: {"command":"next"} albo {"command":"slide","index":2}.</summary>
    public static RemoteCommand? FromJson(byte[] body)
    {
        JsonObject? json;
        try
        {
            json = JsonNode.Parse(body) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
        if (json?["command"] is not JsonValue nameValue || !nameValue.TryGetValue<string>(out var name)) return null;
        int? index = json["index"] is JsonValue indexValue && indexValue.TryGetValue<int>(out var i) ? i : null;
        return name switch
        {
            "next" => new Next(),
            "previous" => new Previous(),
            "nextSong" => new NextSong(),
            "previousSong" => new PreviousSong(),
            "black" => new Black(),
            "clearText" => new ClearText(),
            "stop" => new Stop(),
            "start" => new Start(),
            "song" => json["id"] is JsonValue id && id.TryGetValue<string>(out var text) && Guid.TryParse(text, out _) ? new Song(text) : null,
            "slide" => index is >= 0 ? new Slide(index.Value) : null,
            "planItem" => index is >= 0 ? new PlanItem(index.Value) : null,
            _ => null,
        };
    }
}

/// <summary>Stan prezentacji wysyłany do telefonu (pola jak RemoteState w macOS).</summary>
public sealed record RemoteState(bool IsLive, bool IsBlackScreen, bool IsClearText, string SongTitle, int SlideIndex, string SlideText,
    IReadOnlyList<RemoteSlideInfo> Slides, string PlanName, IReadOnlyList<RemotePlanEntry> Plan, IReadOnlyDictionary<string, string> Labels,
    bool CanStart, string StartTitle);

public sealed record RemoteSlideInfo(string Label, string Preview);

public sealed record RemotePlanEntry(string Title, bool IsCurrent);

public sealed record RemoteSearchResult(string Id, string Title, string Author, string FirstLine);

/// <summary>Obsługa żądań pilota: strona, stan i polecenia. Każde żądanie musi mieć token z kodu QR (?t=).</summary>
public sealed class RemoteRouter(string token, string? stageToken = null)
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DictionaryKeyPolicy = null,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static byte[] Encode<T>(T value) => JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);

    public required Func<string> Page { get; init; }
    public required Func<RemoteState> State { get; init; }
    public required Action<RemoteCommand> Perform { get; init; }
    public Func<string> StagePage { get; init; } = () => "";
    public Func<int, byte[]> StageState { get; init; } = _ => "{}"u8.ToArray();
    public Func<string, byte[]> Search { get; init; } = _ => "[]"u8.ToArray();
    public Func<string> Forbidden { get; init; } = () => "Forbidden";

    public RemoteHttpResponse Respond(RemoteHttpRequest request)
    {
        var given = request.Query.GetValueOrDefault("t", "");
        var isController = ConstantTimeEquals(given, token);
        var isMusician = stageToken is not null && ConstantTimeEquals(given, stageToken);
        if (request.Path is "/stage" or "/api/stage" && (isController || isMusician))
        {
            if (request.Method != "GET") return RemoteHttpResponse.Text("Method not allowed", 405);
            if (request.Path == "/stage") return RemoteHttpResponse.Html(StagePage());
            var semitones = int.TryParse(request.Query.GetValueOrDefault("transpose", "0"), out var value) ? Math.Clamp(value, -11, 11) : 0;
            return RemoteHttpResponse.Json(StageState(semitones));
        }
        if (!isController) return RemoteHttpResponse.Text(Forbidden(), 403);
        switch (request.Method, request.Path)
        {
            case ("GET", "/"):
                return RemoteHttpResponse.Html(Page());
            case ("GET", "/api/state"):
                return RemoteHttpResponse.Json(Encode(State()));
            case ("POST", "/api/command"):
                if (RemoteCommand.FromJson(request.Body) is not RemoteCommand command) return RemoteHttpResponse.Text("Unknown command", 400);
                Perform(command);
                return RemoteHttpResponse.Json(Encode(State()));
            case ("GET", "/api/search"):
                return RemoteHttpResponse.Json(Search(request.Query.GetValueOrDefault("q", "")));
            case (_, "/" or "/api/state" or "/api/command" or "/api/search"):
                return RemoteHttpResponse.Text("Method not allowed", 405);
            default:
                return RemoteHttpResponse.Text("Not found", 404);
        }
    }

    /// <summary>Porównanie bez wczesnego wyjścia, żeby czas odpowiedzi nie zdradzał zgodnych znaków tokenu.</summary>
    public static bool ConstantTimeEquals(string a, string b) =>
        CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));

    /// <summary>Losowy token (128 bitów) do adresu w kodzie QR, bez znaków wymagających kodowania.</summary>
    public static string MakeToken() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(16)).Replace('+', '-').Replace('/', '_').TrimEnd('=');
}
