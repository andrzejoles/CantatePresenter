using System.Net;
using System.Text;
using CantatePresenter.Core.GoogleDrive;
using Xunit;

namespace CantatePresenter.Core.Tests;

/// <summary>Logowanie Google i Dysk jak GoogleOAuthTests w macOS; bez sieci (podstawiony HttpMessageHandler).</summary>
public class GoogleDriveTests
{
    private static string T(string key, object[] args) => string.Format(key, args);

    private sealed class MemoryStore : ICredentialStore
    {
        public string? Value;
        public string? Load() => Value;
        public void Save(string value) => Value = value;
        public void Clear() => Value = null;
    }

    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public readonly List<string> Requests = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add($"{request.Method} {request.RequestUri} {request.Headers.Authorization}");
            return Task.FromResult(respond(request));
        }
    }

    private static HttpResponseMessage Json(string body, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    [Fact]
    public void PkceMatchesRfc7636Vector()
    {
        Assert.Equal("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", GoogleOAuth.Challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"));
        var verifier = GoogleOAuth.NewVerifier();
        Assert.Equal(64, verifier.Length);
        Assert.All(verifier, c => Assert.Contains(c, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"));
        Assert.NotEqual(verifier, GoogleOAuth.NewVerifier());
    }

    [Fact]
    public void AuthorizationUrlUsesLoopbackPkceAndState()
    {
        var url = new Uri(GoogleOAuth.AuthorizationUrl("klient", "http://127.0.0.1:53682", "wyzwanie", "stan"));
        var items = url.Query.TrimStart('?').Split('&').Select(p => p.Split('=')).ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1]));
        Assert.Equal("http://127.0.0.1:53682", items["redirect_uri"]);
        Assert.Equal("wyzwanie", items["code_challenge"]);
        Assert.Equal("S256", items["code_challenge_method"]);
        Assert.Equal("stan", items["state"]);
        Assert.Equal("offline", items["access_type"]);
        Assert.Contains("drive.file", items["scope"]);
        Assert.DoesNotContain("oob", url.ToString());
    }

    [Fact]
    public void CallbackWithCodeDenialAndFavicon()
    {
        var callback = GoogleOAuth.ParseCallback("GET /?state=xyz&code=4%2F0AbCd&scope=email HTTP/1.1", T);
        Assert.Equal(new GoogleOAuthCallback("4/0AbCd", "xyz"), callback);
        Assert.Throws<GoogleOAuthException>(() => GoogleOAuth.ParseCallback("GET /?error=access_denied&state=xyz HTTP/1.1", T));
        Assert.Null(GoogleOAuth.ParseCallback("GET /favicon.ico HTTP/1.1", T));
    }

    [Fact]
    public async Task LoopbackReceivesBrowserRedirect()
    {
        using var loopback = new GoogleOAuthLoopback(T);
        Assert.True(loopback.Port > 0);
        var wait = loopback.WaitForCallbackAsync(TimeSpan.FromSeconds(10));
        using (var favicon = new HttpClient())
        {
            Assert.Equal(HttpStatusCode.NotFound, (await favicon.GetAsync($"{loopback.RedirectUri}/favicon.ico")).StatusCode);
        }
        using var http = new HttpClient();
        var response = await http.GetAsync($"{loopback.RedirectUri}/?code=kod123&state=stan");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("CantatePresenter", await response.Content.ReadAsStringAsync());
        var received = await wait;
        Assert.Equal("kod123", received.Code);
        Assert.Equal("stan", received.State);
    }

    [Fact]
    public async Task LoopbackTimesOut()
    {
        using var loopback = new GoogleOAuthLoopback(T);
        await Assert.ThrowsAsync<GoogleOAuthException>(() => loopback.WaitForCallbackAsync(TimeSpan.FromMilliseconds(200)));
    }

    [Fact]
    public void TokenResponseKeepsOldRefreshToken()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var credentials = new GoogleCredentials { AccessToken = "stary", RefreshToken = "odśwież" };
        credentials.Apply("{\"access_token\":\"nowy\",\"expires_in\":3599}", now, T);
        Assert.Equal("nowy", credentials.AccessToken);
        Assert.Equal("odśwież", credentials.RefreshToken);
        Assert.Equal(now.AddSeconds(3599), credentials.ExpiresAt);
        Assert.Throws<GoogleOAuthException>(() => credentials.Apply("{}", now, T));

        var restored = GoogleCredentials.FromJson(credentials.ToJson());
        Assert.Equal(("nowy", "odśwież", credentials.ExpiresAt), (restored.AccessToken, restored.RefreshToken, restored.ExpiresAt));
        Assert.False(GoogleCredentials.FromJson("nie json").IsSignedIn);
    }

    [Fact]
    public void TokenIsRefreshedAMinuteBeforeExpiry()
    {
        var now = DateTimeOffset.UtcNow;
        GoogleCredentials Expiring(double? seconds) => new() { AccessToken = "a", RefreshToken = "r", ExpiresAt = seconds is double s ? now.AddSeconds(s) : null };
        Assert.False(Expiring(600).NeedsRefresh(now));
        Assert.True(Expiring(30).NeedsRefresh(now));
        Assert.True(Expiring(null).NeedsRefresh(now));
        Assert.True(new GoogleCredentials { RefreshToken = "r" }.NeedsRefresh(now));
    }

    [Fact]
    public async Task UnauthorizedIsRetriedOnceWithFreshToken()
    {
        var tokens = new List<bool>();
        var handler = new FakeHandler(request => request.Headers.Authorization?.Parameter == "świeży"
            ? Json("ok")
            : new HttpResponseMessage(HttpStatusCode.Unauthorized));
        using var http = new HttpClient(handler);
        using var response = await GoogleDriveService.SendAuthorizedAsync(http, () => new HttpRequestMessage(HttpMethod.Get, "https://example.invalid/"),
            force => { tokens.Add(force); return Task.FromResult(force ? "świeży" : "stary"); });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal([false, true], tokens);
    }

    [Fact]
    public void QueryValueEscaping()
    {
        Assert.Equal(@"Kopie O\'Neil", GoogleDriveService.EscapeQueryValue("Kopie O'Neil"));
        Assert.Equal(@"a\\b", GoogleDriveService.EscapeQueryValue(@"a\b"));
    }

    [Fact]
    public void ClientFromConsoleJson()
    {
        Assert.Equal(new GoogleOAuthClient("id.apps.googleusercontent.com", "sekret"),
            GoogleOAuthClient.FromJson("{\"installed\":{\"client_id\":\"id.apps.googleusercontent.com\",\"client_secret\":\"sekret\"}}"));
        Assert.Null(GoogleOAuthClient.FromJson("{\"web\":{}}"));
        Assert.Null(GoogleOAuthClient.FromJson("nie json"));
    }

    [Fact]
    public async Task UploadListAndDownloadThroughTheApi()
    {
        var store = new MemoryStore();
        store.Save(new GoogleCredentials { AccessToken = "token", RefreshToken = "r", ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) }.ToJson());
        string? uploadBody = null;
        var handler = new FakeHandler(request =>
        {
            var url = request.RequestUri!.AbsoluteUri;
            if (url.Contains("upload/drive"))
            {
                uploadBody = request.Content!.ReadAsStringAsync().Result;
                return Json("{\"id\":\"plik1\",\"name\":\"kopia.cantatebackup\"}");
            }
            if (url.Contains("mimeType")) return Json("{\"files\":[{\"id\":\"folder1\",\"name\":\"Kopie\"}]}");
            if (url.Contains("alt=media")) return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) };
            if (url.Contains("in%20parents")) return Json("{\"files\":[{\"id\":\"plik1\",\"name\":\"kopia.cantatebackup\",\"size\":\"3\",\"createdTime\":\"2026-10-17T08:00:00.000Z\"}]}");
            return Json("{}", HttpStatusCode.NotFound);
        });
        using var http = new HttpClient(handler);
        var drive = new GoogleDriveService(new GoogleOAuthClient("id", "s"), store, http, T);
        using var dir = new TempDirectory();
        var archive = dir.File("kopia.cantatebackup");
        await File.WriteAllBytesAsync(archive, [1, 2, 3]);

        var item = await drive.UploadAsync(archive, "Kopie");
        Assert.Equal("plik1", item.Id);
        Assert.Contains("\"parents\":[\"folder1\"]", uploadBody);
        Assert.All(handler.Requests, r => Assert.EndsWith("Bearer token", r));

        var list = await drive.ListAsync("Kopie");
        Assert.Equal(3, Assert.Single(list).Size);
        var downloaded = await drive.DownloadAsync("plik1");
        try
        {
            Assert.Equal([1, 2, 3], await File.ReadAllBytesAsync(downloaded));
            Assert.DoesNotContain("kopia", Path.GetFileName(downloaded));
        }
        finally
        {
            File.Delete(downloaded);
        }
    }

    [Fact]
    public void ApiErrorExplainsDisabledApi()
    {
        var error = GoogleDriveService.ApiError("Błąd", HttpStatusCode.Forbidden,
            "{\"error\":{\"message\":\"Drive API has not been used\",\"errors\":[{\"reason\":\"accessNotConfigured\"}]}}", T);
        Assert.Contains("HTTP 403", error.Message);
        Assert.Contains("Google Drive API nie jest włączone", error.Message);
        Assert.Contains("Drive API has not been used", error.Message);
    }

    [Fact]
    public async Task SignInWithoutBundledClientFails()
    {
        var drive = new GoogleDriveService(null, new MemoryStore(), new HttpClient(), T);
        Assert.False(drive.IsSignInAvailable);
        await Assert.ThrowsAsync<GoogleDriveException>(() => drive.SignInAsync(_ => { }));
    }

    [Fact]
    public async Task SignInExchangesCodeAndStoresTokens()
    {
        var store = new MemoryStore();
        string? tokenBody = null;
        var handler = new FakeHandler(request =>
        {
            if (request.RequestUri!.ToString() == GoogleOAuth.TokenEndpoint)
            {
                tokenBody = request.Content!.ReadAsStringAsync().Result;
                return Json("{\"access_token\":\"a1\",\"refresh_token\":\"r1\",\"expires_in\":3600,\"scope\":\"https://www.googleapis.com/auth/drive.file openid\"}");
            }
            return Json("{\"email\":\"organista@example.com\"}");
        });
        using var http = new HttpClient(handler);
        var drive = new GoogleDriveService(new GoogleOAuthClient("id", "s"), store, http, T);
        using var browser = new HttpClient();
        var email = await drive.SignInAsync(url =>
        {
            // Przeglądarka: Google przekierowuje na loopback z kodem i tym samym state.
            var query = new Uri(url).Query.TrimStart('?').Split('&').Select(p => p.Split('=')).ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1]));
            _ = browser.GetAsync($"{query["redirect_uri"]}/?code=kod&state={Uri.EscapeDataString(query["state"])}");
        });
        Assert.Equal("organista@example.com", email);
        Assert.Contains("code_verifier=", tokenBody);
        Assert.Contains("grant_type=authorization_code", tokenBody);
        Assert.True(drive.IsSignedIn);
        Assert.Equal("r1", GoogleCredentials.FromJson(store.Value).RefreshToken);
        drive.SignOut();
        Assert.False(drive.IsSignedIn);
    }
}
