using System.Text;

namespace CantatePresenter.Core.Remote;

/// <summary>
/// Minimalne żądanie HTTP/1.1 dla pilota ze smartfona (jak RemoteHTTPRequest w macOS): GET/POST, zapytanie, treść.
/// </summary>
public sealed record RemoteHttpRequest(string Method, string Path, IReadOnlyDictionary<string, string> Query,
    IReadOnlyDictionary<string, string> Headers, byte[] Body)
{
    /// <summary>Największe przyjmowane żądanie; pilot wysyła krótkie polecenia JSON.</summary>
    public const int MaxSize = 64 * 1024;

    public enum Status { Incomplete, Invalid, Complete }

    /// <summary>Parsuje bufor z połączenia; Incomplete, gdy brakuje jeszcze nagłówków albo treści.</summary>
    public static (Status Status, RemoteHttpRequest? Request) Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length > MaxSize) return (Status.Invalid, null);
        var headerEnd = data.IndexOf("\r\n\r\n"u8);
        if (headerEnd < 0) return (Status.Incomplete, null);
        string head;
        try
        {
            head = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(data[..headerEnd]);
        }
        catch (DecoderFallbackException)
        {
            return (Status.Invalid, null);
        }
        var lines = head.Split("\r\n");
        var requestLine = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (requestLine.Length != 3 || !requestLine[2].StartsWith("HTTP/1.", StringComparison.Ordinal)) return (Status.Invalid, null);

        var headers = new Dictionary<string, string>();
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon < 0) continue;
            headers[line[..colon].Trim().ToLowerInvariant()] = line[(colon + 1)..].Trim();
        }
        var length = headers.TryGetValue("content-length", out var value) ? (int.TryParse(value, out var parsed) ? parsed : -1) : 0;
        if (length < 0) return (Status.Invalid, null);
        var bodyStart = headerEnd + 4;
        if (data.Length - bodyStart < length) return (Status.Incomplete, null);

        var target = requestLine[1];
        var questionMark = target.IndexOf('?');
        var path = questionMark >= 0 ? target[..questionMark] : target;
        var query = new Dictionary<string, string>();
        if (questionMark >= 0)
        {
            foreach (var pair in target[(questionMark + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var equals = pair.IndexOf('=');
                var name = Unescape(equals >= 0 ? pair[..equals] : pair);
                query[name] = equals >= 0 ? Unescape(pair[(equals + 1)..]) : "";
            }
        }
        return (Status.Complete, new RemoteHttpRequest(requestLine[0].ToUpperInvariant(), Unescape(path), query, headers,
            data.Slice(bodyStart, length).ToArray()));
    }

    /// <summary>Jak URLComponents w macOS: dekodowanie %XX, „+” zostaje plusem.</summary>
    private static string Unescape(string text)
    {
        try
        {
            return Uri.UnescapeDataString(text);
        }
        catch (UriFormatException)
        {
            return text;
        }
    }
}

public sealed record RemoteHttpResponse(int Status, string ContentType, byte[] Body)
{
    public static RemoteHttpResponse Text(string text, int status) => new(status, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes(text));

    public static RemoteHttpResponse Json(byte[] body) => new(200, "application/json; charset=utf-8", body);

    public static RemoteHttpResponse Html(string html) => new(200, "text/html; charset=utf-8", Encoding.UTF8.GetBytes(html));

    /// <summary>Odpowiedź z nagłówkami: bez pamięci podręcznej (stan zmienia się co chwilę) i z zamknięciem połączenia.</summary>
    public byte[] Serialized()
    {
        var reason = Status switch
        {
            200 => "OK",
            400 => "Bad Request",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            _ => "Error",
        };
        var head = string.Join("\r\n",
            $"HTTP/1.1 {Status} {reason}",
            $"Content-Type: {ContentType}",
            $"Content-Length: {Body.Length}",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Referrer-Policy: no-referrer",
            "Connection: close",
            "", "");
        return [.. Encoding.ASCII.GetBytes(head), .. Body];
    }
}
