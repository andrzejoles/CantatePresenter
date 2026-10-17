using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.GoogleDrive;

/// <summary>Błąd Dysku Google z komunikatem dla użytkownika.</summary>
public sealed class GoogleDriveException(string message) : Exception(message);

/// <summary>Kopia zapasowa w folderze na Dysku.</summary>
public sealed record RemoteBackupItem(string Id, string Name, long? Size, DateTimeOffset? CreatedTime);

/// <summary>
/// Kopie zapasowe na Dysku Google użytkownika, jak GoogleDriveService w macOS: logowanie w przeglądarce (loopback + PKCE),
/// odświeżanie tokenu, folder kopii, wysyłanie, lista i pobieranie. Uprawnienie <c>drive.file</c>: aplikacja widzi tylko
/// pliki, które sama utworzyła.
/// </summary>
public sealed class GoogleDriveService(GoogleOAuthClient? client, ICredentialStore store, HttpClient http, Func<string, object[], string> translate)
{
    private const string FilesEndpoint = "https://www.googleapis.com/drive/v3/files";
    private const string UploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart";
    private const string UserInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo";

    private readonly Func<string, object[], string> Translate = translate;

    /// <summary>Czy ta kompilacja ma wbudowanego klienta OAuth.</summary>
    public bool IsSignInAvailable => client is not null;

    public bool IsSignedIn => Credentials().IsSignedIn;

    private GoogleCredentials Credentials() => GoogleCredentials.FromJson(store.Load());

    private GoogleOAuthClient Client() => client ?? throw new GoogleDriveException(Translate("Ta wersja aplikacji nie ma skonfigurowanego logowania Google.", []));

    // MARK: - Logowanie (W3: loopback + PKCE)

    /// <summary>Otwiera logowanie w przeglądarce (<paramref name="openBrowser"/>), odbiera kod i zapisuje tokeny. Zwraca adres e-mail konta.</summary>
    public async Task<string> SignInAsync(Action<string> openBrowser, CancellationToken cancellation = default)
    {
        var oauth = Client();
        var verifier = GoogleOAuth.NewVerifier();
        var state = GoogleOAuth.RandomState();
        using var loopback = new GoogleOAuthLoopback(Translate);
        openBrowser(GoogleOAuth.AuthorizationUrl(oauth.Id, loopback.RedirectUri, GoogleOAuth.Challenge(verifier), state));
        var callback = await loopback.WaitForCallbackAsync(TimeSpan.FromMinutes(5), cancellation);
        if (callback.State != state) throw new GoogleOAuthException(Translate("Odpowiedź logowania nie pasuje do tego żądania (parametr state). Spróbuj ponownie.", []));

        var (status, body) = await PostTokenAsync(new Dictionary<string, string>
        {
            ["code"] = callback.Code, ["client_id"] = oauth.Id, ["client_secret"] = oauth.Secret, ["code_verifier"] = verifier,
            ["redirect_uri"] = loopback.RedirectUri, ["grant_type"] = "authorization_code",
        }, cancellation);
        if (!IsSuccess(status)) throw new GoogleOAuthException(Translate("Błąd wymiany kodu autoryzacji: {0}", [body]));
        // Google pozwala odznaczyć uprawnienia na ekranie zgody; bez Dysku kopie nie zadziałają.
        var granted = TryParse(body)?["scope"] is JsonNode scope ? Json.Str(scope) : "";
        if (granted.Length > 0 && !granted.Contains(GoogleOAuth.DriveScope))
            throw new GoogleOAuthException(Translate("Nie udzielono dostępu do Dysku Google. Połącz ponownie i na ekranie zgody zaznacz dostęp do plików na Dysku.", []));
        var credentials = Credentials();
        credentials.Apply(body, DateTimeOffset.UtcNow, Translate);
        store.Save(credentials.ToJson());
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, UserInfoEndpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credentials.AccessToken);
            using var response = await http.SendAsync(request, cancellation);
            return response.IsSuccessStatusCode ? Json.Str(TryParse(await response.Content.ReadAsStringAsync(cancellation))?["email"]) : "";
        }
        catch (HttpRequestException)
        {
            return "";
        }
    }

    /// <summary>Usuwa tokeny użytkownika.</summary>
    public void SignOut() => store.Clear();

    private async Task<(HttpStatusCode Status, string Body)> PostTokenAsync(Dictionary<string, string> parameters, CancellationToken cancellation)
    {
        using var content = new StringContent(GoogleOAuth.TokenRequestBody(parameters), Encoding.UTF8, "application/x-www-form-urlencoded");
        using var response = await http.PostAsync(GoogleOAuth.TokenEndpoint, content, cancellation);
        return (response.StatusCode, await response.Content.ReadAsStringAsync(cancellation));
    }

    /// <summary>Ważny token; odświeżany przed wygaśnięciem albo na żądanie (po 401).</summary>
    public async Task<string> AccessTokenAsync(bool forceRefresh = false, CancellationToken cancellation = default)
    {
        var credentials = Credentials();
        if (!forceRefresh && !credentials.NeedsRefresh(DateTimeOffset.UtcNow)) return credentials.AccessToken;
        if (credentials.RefreshToken.Length == 0) throw new GoogleDriveException(Translate("Brak połączenia z kontem Google. Połącz konto w Ustawieniach → Dysk Google.", []));
        var oauth = Client();
        var (status, body) = await PostTokenAsync(new Dictionary<string, string>
        {
            ["client_id"] = oauth.Id, ["client_secret"] = oauth.Secret, ["refresh_token"] = credentials.RefreshToken, ["grant_type"] = "refresh_token",
        }, cancellation);
        if (!IsSuccess(status)) throw new GoogleDriveException(Translate("Nie udało się odświeżyć tokenu Google: {0}", [body]));
        credentials.Apply(body, DateTimeOffset.UtcNow, Translate);
        store.Save(credentials.ToJson());
        return credentials.AccessToken;
    }

    // MARK: - Żądania z tokenem

    /// <summary>Wysyła żądanie z tokenem; po 401 wymusza odświeżenie i ponawia raz (W3). Żądanie budowane od nowa przy ponowieniu.</summary>
    public static async Task<HttpResponseMessage> SendAuthorizedAsync(HttpClient http, Func<HttpRequestMessage> makeRequest, Func<bool, Task<string>> token, CancellationToken cancellation = default)
    {
        var request = makeRequest();
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await token(false));
        var response = await http.SendAsync(request, cancellation);
        if (response.StatusCode != HttpStatusCode.Unauthorized) return response;
        response.Dispose();
        var retry = makeRequest();
        retry.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await token(true));
        return await http.SendAsync(retry, cancellation);
    }

    private async Task<(HttpStatusCode Status, string Body, byte[] Bytes)> SendAsync(Func<HttpRequestMessage> makeRequest, CancellationToken cancellation)
    {
        using var response = await SendAuthorizedAsync(http, makeRequest, force => AccessTokenAsync(force, cancellation), cancellation);
        var bytes = await response.Content.ReadAsByteArrayAsync(cancellation);
        return (response.StatusCode, Encoding.UTF8.GetString(bytes), bytes);
    }

    private static bool IsSuccess(HttpStatusCode status) => (int)status is >= 200 and < 300;

    private static JsonNode? TryParse(string text)
    {
        try
        {
            return JsonNode.Parse(text);
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }

    /// <summary>Błąd API Dysku z powodem podanym przez Google i wskazówką dla typowych przyczyn (jak apiError w macOS).</summary>
    public static GoogleDriveException ApiError(string summary, HttpStatusCode status, string body, Func<string, object[], string> Translate)
    {
        var message = body;
        var reason = "";
        if (TryParse(body)?["error"] is JsonObject error)
        {
            message = Json.Str(error["message"], body);
            reason = Json.OptStr((error["errors"] as JsonArray)?.FirstOrDefault()?["reason"])
                ?? (error["details"] as JsonArray)?.Select(d => Json.OptStr(d?["reason"])).FirstOrDefault(r => r is not null) ?? "";
        }
        var hint = reason switch
        {
            "accessNotConfigured" or "SERVICE_DISABLED" => Translate("Google Drive API nie jest włączone w projekcie Google Cloud aplikacji.", []),
            "insufficientPermissions" or "ACCESS_TOKEN_SCOPE_INSUFFICIENT" => Translate("Brak zgody na dostęp do Dysku. Rozłącz konto, połącz ponownie i zaznacz dostęp do plików na Dysku.", []),
            "authError" or "UNAUTHENTICATED" => Translate("Sesja Google wygasła. Rozłącz konto i połącz ponownie.", []),
            _ => "",
        };
        var parts = new[] { $"{summary} (HTTP {(int)status}).", hint, message.Length == 0 ? "" : Translate("Odpowiedź Google: {0}", [message]) };
        return new GoogleDriveException(string.Join(" ", parts.Where(p => p.Length > 0)));
    }

    /// <summary>Wartość w zapytaniu <c>q</c> Dysku: escapowanie <c>\</c> i <c>'</c> (W3).</summary>
    public static string EscapeQueryValue(string value) => value.Replace("\\", "\\\\").Replace("'", "\\'");

    // MARK: - Folder, wysyłanie, lista, pobieranie

    public async Task<string> FolderIdAsync(string folderName, CancellationToken cancellation = default)
    {
        var query = $"name = '{EscapeQueryValue(folderName)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
        var (status, body, _) = await SendAsync(() => new HttpRequestMessage(HttpMethod.Get, $"{FilesEndpoint}?q={Uri.EscapeDataString(query)}&fields=files(id,name)"), cancellation);
        if (IsSuccess(status) && (TryParse(body)?["files"] as JsonArray)?.FirstOrDefault()?["id"] is JsonNode id) return Json.Str(id);

        var metadata = new JsonObject
        {
            ["name"] = folderName,
            ["mimeType"] = "application/vnd.google-apps.folder",
            ["description"] = Translate("Kopie zapasowe bazy pieśni i ustawień aplikacji CantatePresenter", []),
        }.ToJsonString();
        var (createStatus, createBody, _) = await SendAsync(() => new HttpRequestMessage(HttpMethod.Post, FilesEndpoint)
        {
            Content = new StringContent(metadata, Encoding.UTF8, "application/json"),
        }, cancellation);
        if (!IsSuccess(createStatus) || Json.OptStr(TryParse(createBody)?["id"]) is not string newId)
            throw ApiError(Translate("Nie udało się utworzyć folderu kopii zapasowych na Dysku Google", []), createStatus, createBody, Translate);
        return newId;
    }

    public async Task<RemoteBackupItem> UploadAsync(string archivePath, string folderName, CancellationToken cancellation = default)
    {
        var folderId = await FolderIdAsync(folderName, cancellation);
        var name = Path.GetFileName(archivePath);
        var data = await File.ReadAllBytesAsync(archivePath, cancellation);
        var metadata = new JsonObject
        {
            ["name"] = name,
            ["parents"] = new JsonArray(folderId),
            ["mimeType"] = "application/zip",
            ["description"] = Translate("CantatePresenter Pełny Backup (baza pieśni, chwyty, ustawienia, standby, języki, loga)", []),
        }.ToJsonString();
        HttpRequestMessage Request()
        {
            var content = new MultipartContent("related", "CantateBackupBoundary" + Guid.NewGuid().ToString("N"));
            content.Add(new StringContent(metadata, Encoding.UTF8, "application/json"));
            var file = new ByteArrayContent(data);
            file.Headers.ContentType = new MediaTypeHeaderValue("application/zip");
            content.Add(file);
            return new HttpRequestMessage(HttpMethod.Post, UploadEndpoint) { Content = content };
        }
        var (status, body, _) = await SendAsync(Request, cancellation);
        var json = TryParse(body);
        if (!IsSuccess(status) || Json.OptStr(json?["id"]) is not string id)
            throw ApiError(Translate("Błąd przesyłania kopii na Dysk Google", []), status, body, Translate);
        return new RemoteBackupItem(id, Json.Str(json?["name"], name), long.TryParse(Json.OptStr(json?["size"]), out var size) ? size : data.LongLength, DateTimeOffset.Now);
    }

    public async Task<List<RemoteBackupItem>> ListAsync(string folderName, CancellationToken cancellation = default)
    {
        var folderId = await FolderIdAsync(folderName, cancellation);
        var query = $"'{EscapeQueryValue(folderId)}' in parents and trashed = false";
        var (status, body, _) = await SendAsync(() => new HttpRequestMessage(HttpMethod.Get,
            $"{FilesEndpoint}?q={Uri.EscapeDataString(query)}&fields=files(id,name,size,createdTime,modifiedTime)&orderBy=createdTime%20desc"), cancellation);
        if (!IsSuccess(status) || TryParse(body)?["files"] is not JsonArray files)
            throw ApiError(Translate("Błąd odczytu listy kopii z Dysku Google", []), status, body, Translate);
        return files.OfType<JsonObject>()
            .Where(f => Json.OptStr(f["id"]) is not null && Json.OptStr(f["name"]) is not null)
            .Select(f => new RemoteBackupItem(Json.Str(f["id"]), Json.Str(f["name"]),
                long.TryParse(Json.OptStr(f["size"]), out var size) ? size : null,
                DateTimeOffset.TryParse(Json.OptStr(f["createdTime"]) ?? Json.OptStr(f["modifiedTime"]), out var created) ? created : null))
            .ToList();
    }

    /// <summary>Pobiera kopię do pliku tymczasowego; nazwa z Dysku nie trafia do ścieżki (W3).</summary>
    public async Task<string> DownloadAsync(string fileId, CancellationToken cancellation = default)
    {
        var (status, body, bytes) = await SendAsync(() => new HttpRequestMessage(HttpMethod.Get, $"{FilesEndpoint}/{Uri.EscapeDataString(fileId)}?alt=media"), cancellation);
        if (!IsSuccess(status)) throw ApiError(Translate("Błąd pobierania kopii z Dysku Google", []), status, body, Translate);
        var path = Path.Combine(Path.GetTempPath(), $"CantateDriveBackup_{Guid.NewGuid()}.cantatebackup");
        await File.WriteAllBytesAsync(path, bytes, cancellation);
        return path;
    }
}
