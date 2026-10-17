using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.GoogleDrive;

/// <summary>Błąd logowania Google z komunikatem dla użytkownika.</summary>
public sealed class GoogleOAuthException(string message) : Exception(message);

/// <summary>Klient OAuth aplikacji („Aplikacja komputerowa”), ten sam co w macOS, wbudowany przy budowaniu.</summary>
public sealed record GoogleOAuthClient(string Id, string Secret)
{
    /// <summary>Plik pobrany z Google Cloud Console (obiekt „installed”); null, gdy brak identyfikatora.</summary>
    public static GoogleOAuthClient? FromJson(string json)
    {
        try
        {
            var installed = JsonNode.Parse(json)?["installed"];
            var id = Json.Str(installed?["client_id"]);
            return id.Length == 0 ? null : new GoogleOAuthClient(id, Json.Str(installed?["client_secret"]));
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}

/// <summary>Przekierowanie z przeglądarki po zalogowaniu.</summary>
public sealed record GoogleOAuthCallback(string Code, string State);

/// <summary>
/// Logowanie Google dla aplikacji desktopowej jak GoogleOAuth w macOS (W3): przekierowanie na loopback
/// <c>http://127.0.0.1:&lt;port&gt;</c> z PKCE i <c>state</c>.
/// </summary>
public static class GoogleOAuth
{
    public const string AuthorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth";
    public const string TokenEndpoint = "https://oauth2.googleapis.com/token";
    public const string DriveScope = "https://www.googleapis.com/auth/drive.file";
    public const string Scopes = DriveScope + " https://www.googleapis.com/auth/userinfo.email";

    private const string VerifierAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

    /// <summary>Losowy weryfikator PKCE (64 znaki z alfabetu RFC 7636).</summary>
    public static string NewVerifier() => new(Enumerable.Range(0, 64).Select(_ => VerifierAlphabet[RandomNumberGenerator.GetInt32(VerifierAlphabet.Length)]).ToArray());

    /// <summary><c>BASE64URL(SHA256(verifier))</c> bez dopełnienia (metoda S256).</summary>
    public static string Challenge(string verifier) => Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));

    public static string RandomState() => Base64Url(RandomNumberGenerator.GetBytes(24));

    public static string Base64Url(byte[] data) => Convert.ToBase64String(data).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static string Encode(string value)
    {
        var builder = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(value))
        {
            var c = (char)b;
            if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '.' or '_' or '~') builder.Append(c);
            else builder.Append('%').Append(b.ToString("X2"));
        }
        return builder.ToString();
    }

    public static string AuthorizationUrl(string clientId, string redirectUri, string codeChallenge, string state)
    {
        var items = new (string, string)[]
        {
            ("client_id", clientId), ("redirect_uri", redirectUri), ("response_type", "code"), ("scope", Scopes),
            ("code_challenge", codeChallenge), ("code_challenge_method", "S256"), ("state", state),
            ("access_type", "offline"), ("prompt", "consent"),
        };
        return AuthorizationEndpoint + "?" + string.Join("&", items.Select(i => $"{i.Item1}={Encode(i.Item2)}"));
    }

    /// <summary>Treść <c>application/x-www-form-urlencoded</c> do endpointu tokenu (puste wartości pomijane).</summary>
    public static string TokenRequestBody(IReadOnlyDictionary<string, string> parameters) =>
        string.Join("&", parameters.Where(p => p.Value.Length > 0).OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => $"{p.Key}={Encode(p.Value)}"));

    /// <summary>Odczyt pierwszej linii żądania, np. <c>GET /?code=…&amp;state=… HTTP/1.1</c>; null, gdy brak kodu (np. /favicon.ico).</summary>
    public static GoogleOAuthCallback? ParseCallback(string requestLine, Func<string, object[], string> Translate)
    {
        var parts = requestLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return null;
        var query = parts[1].Contains('?') ? parts[1][(parts[1].IndexOf('?') + 1)..] : "";
        var items = new Dictionary<string, string>();
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var separator = pair.IndexOf('=');
            var name = Uri.UnescapeDataString((separator < 0 ? pair : pair[..separator]).Replace('+', ' '));
            var value = separator < 0 ? "" : Uri.UnescapeDataString(pair[(separator + 1)..].Replace('+', ' '));
            items.TryAdd(name, value);
        }
        if (items.TryGetValue("error", out var error)) throw new GoogleOAuthException(Translate("Google odmówił dostępu: {0}.", [error]));
        return items.TryGetValue("code", out var code) && code.Length > 0 ? new GoogleOAuthCallback(code, items.GetValueOrDefault("state", "")) : null;
    }
}

/// <summary>Tokeny Google użytkownika. Tylko w Menedżerze poświadczeń Windows, nigdy w settings.json ani w kopiach (W4).</summary>
public sealed class GoogleCredentials
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTimeOffset? ExpiresAt { get; set; }

    public bool IsSignedIn => RefreshToken.Length > 0 || AccessToken.Length > 0;

    /// <summary>Odświeżamy minutę przed wygaśnięciem; token bez znanego terminu też odświeżamy (W3).</summary>
    public bool NeedsRefresh(DateTimeOffset now) => AccessToken.Length == 0 || ExpiresAt is not DateTimeOffset expires || (expires - now).TotalSeconds < 60;

    /// <summary>Zapisuje odpowiedź z endpointu tokenu. Przy odświeżeniu Google zwykle nie zwraca nowego refresh tokenu.</summary>
    public void Apply(string tokenResponse, DateTimeOffset now, Func<string, object[], string> Translate)
    {
        JsonNode? json;
        try
        {
            json = JsonNode.Parse(tokenResponse);
        }
        catch (System.Text.Json.JsonException)
        {
            json = null;
        }
        var access = Json.OptStr(json?["access_token"]);
        if (string.IsNullOrEmpty(access)) throw new GoogleOAuthException(Translate("Brak access_token w odpowiedzi Google", []));
        AccessToken = access;
        if (Json.OptStr(json?["refresh_token"]) is { Length: > 0 } refresh) RefreshToken = refresh;
        ExpiresAt = Json.Number(json?["expires_in"]) is double seconds ? now.AddSeconds(seconds) : null;
    }

    public string ToJson() => new JsonObject
    {
        ["accessToken"] = AccessToken,
        ["refreshToken"] = RefreshToken,
        ["expiresAt"] = ExpiresAt?.ToUnixTimeSeconds(),
    }.ToJsonString();

    public static GoogleCredentials FromJson(string? text)
    {
        try
        {
            var json = text is null ? null : JsonNode.Parse(text);
            return new GoogleCredentials
            {
                AccessToken = Json.Str(json?["accessToken"]),
                RefreshToken = Json.Str(json?["refreshToken"]),
                ExpiresAt = Json.Number(json?["expiresAt"]) is double seconds ? DateTimeOffset.FromUnixTimeSeconds((long)seconds) : null,
            };
        }
        catch (System.Text.Json.JsonException)
        {
            return new GoogleCredentials();
        }
    }
}

/// <summary>Miejsce na tokeny (w Windows: Menedżer poświadczeń; w testach: pamięć).</summary>
public interface ICredentialStore
{
    string? Load();
    void Save(string value);
    void Clear();
}

/// <summary>Jednorazowy serwer HTTP na 127.0.0.1 z losowym portem, który odbiera przekierowanie z przeglądarki.</summary>
public sealed class GoogleOAuthLoopback : IDisposable
{
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    private readonly Func<string, object[], string> Translate;

    public GoogleOAuthLoopback(Func<string, object[], string> translate)
    {
        Translate = translate;
        listener.Start();
    }

    public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;

    public string RedirectUri => $"http://127.0.0.1:{Port}";

    /// <summary>Czeka na przekierowanie z kodem; inne żądania (np. /favicon.ico) dostają 404.</summary>
    public async Task<GoogleOAuthCallback> WaitForCallbackAsync(TimeSpan timeout, CancellationToken cancellation = default)
    {
        using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        limit.CancelAfter(timeout);
        try
        {
            while (true)
            {
                using var client = await listener.AcceptTcpClientAsync(limit.Token);
                using var stream = client.GetStream();
                var buffer = new byte[16 * 1024];
                var read = 0;
                using (var readLimit = CancellationTokenSource.CreateLinkedTokenSource(limit.Token))
                {
                    readLimit.CancelAfter(TimeSpan.FromSeconds(5));
                    try
                    {
                        while (read < buffer.Length)
                        {
                            var count = await stream.ReadAsync(buffer.AsMemory(read), readLimit.Token);
                            if (count == 0) break;
                            read += count;
                            if (Encoding.ASCII.GetString(buffer, 0, read).Contains("\r\n")) break;
                        }
                    }
                    catch (OperationCanceledException) when (!limit.IsCancellationRequested)
                    {
                        continue;
                    }
                }
                var requestLine = Encoding.UTF8.GetString(buffer, 0, read).Split("\r\n")[0];
                GoogleOAuthCallback? callback = null;
                string? failure = null;
                try
                {
                    callback = GoogleOAuth.ParseCallback(requestLine, Translate);
                }
                catch (GoogleOAuthException error)
                {
                    failure = error.Message;
                }
                var body = callback is not null ? Translate("Zalogowano. Możesz zamknąć tę kartę i wrócić do CantatePresenter.", [])
                    : failure is not null ? Translate("Logowanie nie powiodło się: {0}", [failure]) : "";
                var html = $"<!doctype html><meta charset=\"utf-8\"><title>CantatePresenter</title><body style=\"font-family:Segoe UI,sans-serif;padding:40px\"><h2>CantatePresenter</h2><p>{WebUtility.HtmlEncode(body)}</p></body>";
                var status = callback is null && failure is null ? "404 Not Found" : "200 OK";
                var response = Encoding.UTF8.GetBytes($"HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {Encoding.UTF8.GetByteCount(html)}\r\nConnection: close\r\n\r\n{html}");
                await stream.WriteAsync(response, limit.Token);
                if (failure is not null) throw new GoogleOAuthException(failure);
                if (callback is not null) return callback;
            }
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        {
            throw new GoogleOAuthException(Translate("Logowanie nie zostało dokończone w przeglądarce w wyznaczonym czasie.", []));
        }
    }

    public void Dispose() => listener.Stop();
}
