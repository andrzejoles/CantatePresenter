using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Updates;
using Xunit;

namespace CantatePresenter.Core.Tests;

public class UpdateTests
{
    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(respond(request));
    }

    private static readonly byte[] SetupBytes = Encoding.UTF8.GetBytes("nie prawdziwy instalator, tylko dane testowe");

    private static string ReleaseJson(string tag = "v3.1.0", string? url = null, string? digest = null, long? size = null, bool draft = false)
    {
        var version = tag.TrimStart('v');
        var name = $"CantatePresenter-Windows-x64-Setup-{version}.exe";
        return new JsonObject
        {
            ["tag_name"] = tag,
            ["draft"] = draft,
            ["prerelease"] = false,
            ["html_url"] = $"https://github.com/andrzejoles/CantatePresenter/releases/tag/{tag}",
            ["body"] = "Zmiany w wydaniu",
            ["assets"] = new JsonArray(
                new JsonObject { ["name"] = "CantatePresenter-3.1.0.dmg", ["browser_download_url"] = "https://github.com/andrzejoles/CantatePresenter/releases/download/v3.1.0/CantatePresenter-3.1.0.dmg", ["size"] = 10, ["digest"] = "sha256:" + new string('0', 64) },
                new JsonObject
                {
                    ["name"] = name,
                    ["browser_download_url"] = url ?? $"https://github.com/andrzejoles/CantatePresenter/releases/download/{tag}/{name}",
                    ["size"] = size ?? SetupBytes.Length,
                    ["digest"] = digest ?? "sha256:" + Convert.ToHexString(SHA256.HashData(SetupBytes)).ToLowerInvariant(),
                }),
        }.ToJsonString();
    }

    [Fact]
    public void ComparesVersions()
    {
        Assert.True(UpdateChecker.IsNewer("3.0.1", "3.0.0"));
        Assert.True(UpdateChecker.IsNewer("v3.10.0", "3.9.5"));
        Assert.True(UpdateChecker.IsNewer("3.1", "3.0.9"));
        Assert.False(UpdateChecker.IsNewer("3.0.0", "3.0.0"));
        Assert.False(UpdateChecker.IsNewer("3.0", "3.0.0"));
        Assert.False(UpdateChecker.IsNewer("2.9.9", "3.0.0"));
        Assert.False(UpdateChecker.IsNewer("3.1.0", "dev"));
        Assert.False(UpdateChecker.IsNewer("nowa", "3.0.0"));
    }

    [Fact]
    public void ParsesOnlyReleasesWithVerifiableWindowsSetup()
    {
        var release = UpdateChecker.Parse(ReleaseJson());
        Assert.NotNull(release);
        Assert.Equal("3.1.0", release.Version);
        Assert.Equal("CantatePresenter-Windows-x64-Setup-3.1.0.exe", release.SetupName);
        Assert.Equal("Zmiany w wydaniu", release.Notes);
        Assert.Equal(SetupBytes.Length, release.SetupSize);
        // Plik spoza wydań repozytorium, brak sumy kontrolnej, szkic albo zły numer: brak aktualizacji.
        Assert.Null(UpdateChecker.Parse(ReleaseJson(url: "https://example.com/CantatePresenter-Windows-x64-Setup-3.1.0.exe")));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(url: "https://github.com/someone/else/releases/download/v3.1.0/CantatePresenter-Windows-x64-Setup-3.1.0.exe")));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(digest: "")));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(digest: "md5:abc")));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(draft: true)));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(tag: "latest")));
        Assert.Null(UpdateChecker.Parse(ReleaseJson(size: 0)));
    }

    [Fact]
    public async Task ChecksLatestReleaseAndDownloadsVerifiedSetup()
    {
        var requests = new List<string>();
        using var http = new HttpClient(new FakeHandler(request =>
        {
            requests.Add(request.RequestUri!.AbsoluteUri);
            Assert.Contains("CantatePresenter", request.Headers.UserAgent.ToString());
            return request.RequestUri.AbsoluteUri == UpdateChecker.LatestReleaseApi
                ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(ReleaseJson()) }
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(SetupBytes) };
        }));
        var release = await UpdateChecker.LatestAsync(http);
        Assert.NotNull(release);
        using var dir = new TempDirectory();
        var path = await UpdateChecker.DownloadSetupAsync(http, release, dir.Path, (key, _) => key);
        Assert.Equal(SetupBytes, await File.ReadAllBytesAsync(path));
        Assert.Equal(["https://api.github.com/repos/andrzejoles/CantatePresenter/releases/latest", release.SetupUrl], requests);
    }

    [Fact]
    public async Task RejectsDamagedDownloadAndLeavesNoFile()
    {
        var release = UpdateChecker.Parse(ReleaseJson())!;
        using var dir = new TempDirectory();
        foreach (var body in new[] { Encoding.UTF8.GetBytes("podmieniony plik o innej treści, ale dłuższy od oryginału!!!"), SetupBytes[..10], SetupBytes.Select(b => (byte)(b ^ 1)).ToArray() })
        {
            using var http = new HttpClient(new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(body) }));
            await Assert.ThrowsAsync<UpdateException>(() => UpdateChecker.DownloadSetupAsync(http, release, dir.Path, (key, _) => key));
            Assert.Empty(Directory.GetFiles(dir.Path));
        }
    }

    [Fact]
    public async Task NoReleaseYetIsNotAnError()
    {
        using var http = new HttpClient(new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.NotFound)));
        Assert.Null(await UpdateChecker.LatestAsync(http));
    }
}
