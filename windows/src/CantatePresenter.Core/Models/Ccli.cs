using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

namespace CantatePresenter.Core.Models;

/// <summary>Jedno wyświetlenie pieśni z numerem CCLI (ccli_usage.json, jak CCLIUsageEntry w macOS).</summary>
public sealed record CcliUsageEntry(string Id, string Date, string Title, string Author, string CcliNumber, string? Copyright)
{
    public static CcliUsageEntry FromJson(JsonNode? raw) => new(
        Json.IdOrNew(raw?["id"]), Json.ParseDate(raw?["date"]), Json.Str(raw?["title"]), Json.Str(raw?["author"]),
        Json.OptStr(raw?["ccliNumber"]) ?? Json.Int(raw?["ccliNumber"])?.ToString() ?? "", Json.OptStr(raw?["copyright"]));

    public JsonObject ToJson()
    {
        var json = new JsonObject { ["id"] = Id, ["date"] = Date, ["title"] = Title, ["author"] = Author, ["ccliNumber"] = CcliNumber };
        if (Copyright is not null) json["copyright"] = Copyright;
        return json;
    }
}

/// <summary>Raport użycia do ręcznego zgłoszenia w CCLI i informacja o prawach na slajdzie (jak w macOS).</summary>
public static class Ccli
{
    /// <summary>Nowy wpis, najwyżej jeden na pieśń dziennie (jedno nabożeństwo = jedno użycie), w lokalnej strefie czasowej.</summary>
    public static CcliUsageEntry? UsageEntry(Song song, DateTimeOffset date, IEnumerable<CcliUsageEntry> existing)
    {
        var number = (song.CcliNumber ?? "").Trim();
        if (number.Length == 0) return null;
        var day = date.ToLocalTime().Date;
        if (existing.Any(e => e.CcliNumber == number && DateTimeOffset.Parse(e.Date, CultureInfo.InvariantCulture).ToLocalTime().Date == day)) return null;
        return new CcliUsageEntry(Json.NewId(), Json.IsoDate(date), song.Title, song.Author, number, song.Copyright);
    }

    private static string Escape(string field) =>
        field.IndexOfAny([',', '"', '\n', '\r']) >= 0 ? "\"" + field.Replace("\"", "\"\"") + "\"" : field;

    /// <summary>CSV jak w macOS: nagłówki po angielsku (format danych), wiersze po dacie, CRLF.</summary>
    public static string UsageCsv(IEnumerable<CcliUsageEntry> entries)
    {
        var builder = new StringBuilder("Date,Title,Authors,CCLI Song Number,Copyright\r\n");
        foreach (var e in entries.OrderBy(e => DateTimeOffset.Parse(e.Date, CultureInfo.InvariantCulture)))
        {
            var day = DateTimeOffset.Parse(e.Date, CultureInfo.InvariantCulture).ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            builder.Append(string.Join(",", new[] { day, e.Title, e.Author, e.CcliNumber, e.Copyright ?? "" }.Select(Escape))).Append("\r\n");
        }
        return builder.ToString();
    }

    /// <summary>Linia © na slajdzie dla pieśni z numerem CCLI (CopyrightNotice w macOS).</summary>
    public static string? Notice(Song song, int slideIndex, AppSettings settings, Func<string, object[], string> t)
    {
        var ccli = (song.CcliNumber ?? "").Trim();
        if (ccli.Length == 0) return null;
        var placement = settings.CopyrightNoticePlacement;
        var shown = placement == "allSlides" || (placement == "firstSlide" && slideIndex == 0) || (placement == "lastSlide" && slideIndex == song.Slides.Count - 1);
        if (!shown) return null;
        var parts = new List<string> { song.Title };
        if (song.Author.Trim().Length > 0) parts.Add(song.Author.Trim());
        if ((song.Copyright ?? "").Trim().Length > 0) parts.Add(song.Copyright!.Trim());
        parts.Add(t("Pieśń CCLI nr {0}", [ccli]));
        if (settings.CcliLicenseNumber.Trim().Length > 0) parts.Add(t("Licencja CCLI nr {0}", [settings.CcliLicenseNumber.Trim()]));
        return string.Join(" · ", parts);
    }
}
