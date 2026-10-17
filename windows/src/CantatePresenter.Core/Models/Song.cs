using System.Text.Json.Nodes;
using CantatePresenter.Core.Text;

namespace CantatePresenter.Core.Models;

/// <summary>Slajd pieśni (jak SongSlide w Swift): typ jako stabilny kod, etykieta, tekst, numer zwrotki.</summary>
public sealed record SongSlide(string Id, string Type, string Label, string Text, int? Number)
{
    public static SongSlide FromJson(JsonNode? raw)
    {
        var type = raw?["type"] is null ? SlideTypes.Verse : SlideTypes.From(Json.OptStr(raw["type"]));
        var label = Json.Str(raw?["label"], SlideTypes.PolishName[type]);
        var number = Json.Int(raw?["number"]) ?? LyricsParser.TrailingNumber(label);
        return new SongSlide(Json.IdOrNew(raw?["id"]), type, label, Json.Str(raw?["text"]), number);
    }

    public JsonObject ToJson()
    {
        var json = new JsonObject { ["id"] = Id, ["type"] = Type, ["label"] = Label, ["text"] = Text };
        if (Number is int number) json["number"] = number;
        return json;
    }
}

/// <summary>
/// Pieśń w formacie songs.json z wersji macOS. Pola nieznane tej wersji zostają w <see cref="Extra"/> i wracają przy zapisie,
/// żeby plik po edycji na Windows nadal wczytał się na Macu bez strat.
/// </summary>
public sealed class Song
{
    public string Id { get; set; } = Json.NewId();
    public string Title { get; set; } = "";
    public string Author { get; set; } = "";
    public string Key { get; set; } = "";
    public List<string> Tags { get; set; } = [];
    public string RawLyrics { get; set; } = "";
    public string? Chords { get; set; }

    /// <summary>Pieśń ma arkusz chwytów (pusty albo same spacje się nie liczy), jak Song.hasChords w macOS.</summary>
    public bool HasChords => !string.IsNullOrWhiteSpace(Chords);

    public List<SongSlide> Slides { get; set; } = [];
    public string CreatedAt { get; set; } = Json.IsoDate();
    public string UpdatedAt { get; set; } = Json.IsoDate();
    public string? Source { get; set; }
    public string? Copyright { get; set; }
    public string? CcliNumber { get; set; }
    public JsonObject Extra { get; set; } = [];

    private static readonly HashSet<string> Known = ["id", "title", "author", "key", "tags", "rawLyrics", "chords", "slides", "createdAt", "updatedAt", "source", "copyright", "ccliNumber"];

    public static List<SongSlide> SlidesFromLyrics(string rawLyrics) =>
        LyricsParser.Parse(rawLyrics).Select(s => new SongSlide(Json.NewId(), s.Type, s.Label, s.Text, s.Number)).ToList();

    public static Song Create(string title, string author = "", string key = "", IEnumerable<string>? tags = null, string rawLyrics = "", string? chords = null)
    {
        var now = Json.IsoDate();
        return new Song
        {
            Title = title, Author = author, Key = key, Tags = tags?.ToList() ?? [], RawLyrics = rawLyrics,
            Chords = string.IsNullOrEmpty(chords) ? null : chords, Slides = SlidesFromLyrics(rawLyrics), CreatedAt = now, UpdatedAt = now,
        };
    }

    public static Song FromJson(JsonNode? raw)
    {
        var rawLyrics = Json.Str(raw?["rawLyrics"]);
        var slides = raw?["slides"] is JsonArray array ? array.Select(SongSlide.FromJson).ToList() : [];
        var createdAt = Json.ParseDate(raw?["createdAt"]);
        var song = new Song
        {
            Id = Json.IdOrNew(raw?["id"]),
            Title = Json.Str(raw?["title"]),
            Author = Json.Str(raw?["author"]),
            Key = Json.Str(raw?["key"]),
            Tags = raw?["tags"] is JsonArray tags ? tags.Select(t => Json.OptStr(t)).OfType<string>().ToList() : [],
            RawLyrics = rawLyrics,
            Chords = Json.OptStr(raw?["chords"]),
            CreatedAt = createdAt,
            UpdatedAt = Json.ParseDate(raw?["updatedAt"], createdAt),
            Source = Json.OptStr(raw?["source"]),
            Copyright = Json.OptStr(raw?["copyright"]),
            // Numer CCLI bywa liczbą (inne programy).
            CcliNumber = Json.OptStr(raw?["ccliNumber"]) ?? Json.Int(raw?["ccliNumber"])?.ToString(),
        };
        song.Slides = slides.Count == 0 && rawLyrics.Length > 0 ? SlidesFromLyrics(rawLyrics) : slides;
        if (raw is JsonObject obj)
        {
            foreach (var (name, value) in obj)
            {
                if (!Known.Contains(name)) song.Extra[name] = value?.DeepClone();
            }
        }
        return song;
    }

    public JsonObject ToJson()
    {
        var json = new JsonObject();
        foreach (var (name, value) in Extra) json[name] = value?.DeepClone();
        json["id"] = Id;
        json["title"] = Title;
        json["author"] = Author;
        json["key"] = Key;
        json["tags"] = new JsonArray(Tags.Select(t => (JsonNode?)t).ToArray());
        json["rawLyrics"] = RawLyrics;
        if (Chords is not null) json["chords"] = Chords;
        json["slides"] = new JsonArray(Slides.Select(s => (JsonNode?)s.ToJson()).ToArray());
        json["createdAt"] = CreatedAt;
        json["updatedAt"] = UpdatedAt;
        if (Source is not null) json["source"] = Source;
        if (Copyright is not null) json["copyright"] = Copyright;
        if (CcliNumber is not null) json["ccliNumber"] = CcliNumber;
        return json;
    }

    /// <summary>Nowy tekst: slajdy liczone od nowa, data zmiany.</summary>
    public void UpdateLyrics(string rawLyrics)
    {
        RawLyrics = rawLyrics;
        Slides = SlidesFromLyrics(rawLyrics);
        UpdatedAt = Json.IsoDate();
    }
}

public sealed record PlanItem(string Id, string SongId, string Note)
{
    public JsonObject Extra { get; init; } = [];
}

/// <summary>Plan nabożeństwa w formacie plans.json z wersji macOS.</summary>
public sealed class ServicePlan
{
    public string Id { get; set; } = Json.NewId();
    public string Name { get; set; } = "";
    public List<PlanItem> Items { get; set; } = [];
    public string CreatedAt { get; set; } = Json.IsoDate();
    public string UpdatedAt { get; set; } = Json.IsoDate();
    public JsonObject Extra { get; set; } = [];

    public static ServicePlan Create(string name) => new() { Name = name };

    public static ServicePlan? FromJson(JsonNode? raw)
    {
        if (raw is not JsonObject obj) return null;
        var createdAt = Json.ParseDate(obj["createdAt"]);
        var plan = new ServicePlan
        {
            Id = Json.IdOrNew(obj["id"]),
            Name = Json.Str(obj["name"], "Nowy plan"),
            CreatedAt = createdAt,
            UpdatedAt = Json.ParseDate(obj["updatedAt"], createdAt),
            // Pozycja bez songId jest pomijana (w Swift to pole wymagane).
            Items = (obj["items"] as JsonArray ?? []).OfType<JsonObject>().Where(i => Json.IsUuid(i["songId"])).Select(i =>
            {
                var extra = new JsonObject();
                foreach (var (name, value) in i) if (name is not ("id" or "songId" or "note")) extra[name] = value?.DeepClone();
                return new PlanItem(Json.IdOrNew(i["id"]), Json.OptStr(i["songId"])!.ToUpperInvariant(), Json.Str(i["note"])) { Extra = extra };
            }).ToList(),
        };
        foreach (var (name, value) in obj)
        {
            if (name is not ("id" or "name" or "items" or "createdAt" or "updatedAt")) plan.Extra[name] = value?.DeepClone();
        }
        return plan;
    }

    public JsonObject ToJson()
    {
        var json = new JsonObject();
        foreach (var (name, value) in Extra) json[name] = value?.DeepClone();
        json["id"] = Id;
        json["name"] = Name;
        json["items"] = new JsonArray(Items.Select(i =>
        {
            var item = new JsonObject();
            foreach (var (name, value) in i.Extra) item[name] = value?.DeepClone();
            item["id"] = i.Id;
            item["songId"] = i.SongId;
            item["note"] = i.Note;
            return (JsonNode?)item;
        }).ToArray());
        json["createdAt"] = CreatedAt;
        json["updatedAt"] = UpdatedAt;
        return json;
    }
}
