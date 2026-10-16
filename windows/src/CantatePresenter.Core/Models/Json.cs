using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CantatePresenter.Core.Models;

/// <summary>Pomocnicze funkcje JSON: tolerancyjny odczyt jak dekodery w Swift (K1) i daty jak w Foundation.</summary>
public static class Json
{
    /// <summary>Różnica między epoką Unix a datą odniesienia Foundation (2001-01-01), w sekundach.</summary>
    private const double ReferenceDateOffset = 978307200;

    public static readonly JsonSerializerOptions Pretty = new() { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public static string NewId() => Guid.NewGuid().ToString().ToUpperInvariant();

    /// <summary>Data w formacie zapisywanym przez wersję macOS (ISO 8601 bez ułamków, UTC).</summary>
    public static string IsoDate(DateTimeOffset? date = null) =>
        (date ?? DateTimeOffset.UtcNow).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    /// <summary>Data z JSON: ISO 8601 (z ułamkami sekund lub bez) albo liczba sekund od 2001-01-01.</summary>
    public static string ParseDate(JsonNode? value, string? fallback = null)
    {
        if (value is JsonValue v)
        {
            if (v.TryGetValue<double>(out var seconds) && double.IsFinite(seconds))
                return IsoDate(DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Round((seconds + ReferenceDateOffset) * 1000)));
            if (v.TryGetValue<string>(out var text) && DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date))
                return IsoDate(date);
        }
        return fallback ?? IsoDate();
    }

    public static string Str(JsonNode? node, string fallback = "") =>
        node is JsonValue v && v.TryGetValue<string>(out var s) ? s : fallback;

    public static string? OptStr(JsonNode? node) => node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public static bool IsUuid(JsonNode? node) => OptStr(node) is string s && Guid.TryParseExact(s, "D", out _);

    public static string IdOrNew(JsonNode? node) => IsUuid(node) ? OptStr(node)!.ToUpperInvariant() : NewId();

    public static int? Int(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<double>(out var d) && d == Math.Floor(d) && Math.Abs(d) < int.MaxValue ? (int)d : null;

    public static double? Number(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<double>(out var d) && double.IsFinite(d) ? d : null;

    public static bool? Bool(JsonNode? node) => node is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;
}
