using System.Security.Cryptography;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace CantatePresenter.Core.Updates;

/// <summary>Wydanie z instalatorem dla Windows (z API GitHub Releases).</summary>
public sealed record WindowsRelease(string Version, string PageUrl, string Notes, string SetupUrl, string SetupName, long SetupSize, string SetupSha256);

public sealed class UpdateException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>
/// Aktualizacje w Windows (odpowiednik Sparkle w macOS): najnowsze wydanie z GitHub Releases, instalator Inno Setup
/// pobierany tylko z wydań tego repozytorium przez HTTPS i sprawdzany sumą SHA-256 podaną przez GitHub (pole „digest”).
/// </summary>
public static partial class UpdateChecker
{
    public const string Repository = "andrzejoles/CantatePresenter";
    public const string LatestReleaseApi = $"https://api.github.com/repos/{Repository}/releases/latest";
    public const string ReleasesPage = $"https://github.com/{Repository}/releases/latest";
    private const string DownloadPrefix = $"https://github.com/{Repository}/releases/download/";

    [GeneratedRegex(@"^\d+(\.\d+){1,3}$")]
    private static partial Regex VersionPattern();

    [GeneratedRegex(@"^sha256:([0-9a-f]{64})$")]
    private static partial Regex DigestPattern();

    /// <summary>Wersja z numerów (3.0.0); null dla „dev” i innych.</summary>
    public static Version? ParseVersion(string? text)
    {
        var clean = (text ?? "").Trim().TrimStart('v', 'V');
        return VersionPattern().IsMatch(clean) && Version.TryParse(clean, out var version) ? version : null;
    }

    /// <summary>Czy <paramref name="latest"/> jest nowsza; kompilacja deweloperska („dev”) nigdy się nie aktualizuje.</summary>
    public static bool IsNewer(string latest, string current) =>
        ParseVersion(latest) is Version l && ParseVersion(current) is Version c && Normalize(l) > Normalize(c);

    private static Version Normalize(Version v) => new(v.Major, v.Minor, Math.Max(0, v.Build), Math.Max(0, v.Revision));

    /// <summary>Odpowiedź API releases/latest; null, gdy wydanie nie ma poprawnego instalatora dla Windows.</summary>
    public static WindowsRelease? Parse(string json)
    {
        if (JsonNode.Parse(json) is not JsonObject release) return null;
        if (release["draft"]?.GetValue<bool>() == true || release["prerelease"]?.GetValue<bool>() == true) return null;
        var version = (release["tag_name"]?.GetValue<string>() ?? "").TrimStart('v');
        if (ParseVersion(version) is null) return null;
        var setupName = $"CantatePresenter-Windows-x64-Setup-{version}.exe";
        foreach (var asset in release["assets"] as JsonArray ?? [])
        {
            if (asset?["name"]?.GetValue<string>() != setupName) continue;
            var url = asset["browser_download_url"]?.GetValue<string>() ?? "";
            var digest = DigestPattern().Match(asset["digest"]?.GetValue<string>() ?? "");
            var size = asset["size"]?.GetValue<long>() ?? 0;
            // Tylko pliki z wydań tego repozytorium i z sumą kontrolną.
            if (!url.StartsWith(DownloadPrefix, StringComparison.Ordinal) || !digest.Success || size <= 0) return null;
            var page = release["html_url"]?.GetValue<string>() ?? ReleasesPage;
            return new WindowsRelease(version, page.StartsWith($"https://github.com/{Repository}/", StringComparison.Ordinal) ? page : ReleasesPage,
                release["body"]?.GetValue<string>() ?? "", url, setupName, size, digest.Groups[1].Value);
        }
        return null;
    }

    public static async Task<WindowsRelease?> LatestAsync(HttpClient http, CancellationToken cancellation = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseApi);
        request.Headers.UserAgent.ParseAdd("CantatePresenter-Windows");
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        using var response = await http.SendAsync(request, cancellation);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        return Parse(await response.Content.ReadAsStringAsync(cancellation));
    }

    /// <summary>Pobiera instalator do <paramref name="directory"/> i sprawdza rozmiar i SHA-256; zwraca ścieżkę.</summary>
    public static async Task<string> DownloadSetupAsync(HttpClient http, WindowsRelease release, string directory, Func<string, object[], string> translate,
        IProgress<double>? progress = null, CancellationToken cancellation = default)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, release.SetupName);
        var partial = path + ".part";
        try
        {
            using (var request = new HttpRequestMessage(HttpMethod.Get, release.SetupUrl))
            {
                request.Headers.UserAgent.ParseAdd("CantatePresenter-Windows");
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation);
                response.EnsureSuccessStatusCode();
                await using var source = await response.Content.ReadAsStreamAsync(cancellation);
                await using var target = File.Create(partial);
                var buffer = new byte[81920];
                long total = 0;
                int read;
                while ((read = await source.ReadAsync(buffer, cancellation)) > 0)
                {
                    total += read;
                    if (total > release.SetupSize) break;
                    await target.WriteAsync(buffer.AsMemory(0, read), cancellation);
                    progress?.Report((double)total / release.SetupSize);
                }
            }
            string hash;
            await using (var file = File.OpenRead(partial))
            {
                if (file.Length != release.SetupSize) throw new UpdateException(translate("Pobrany instalator jest niekompletny albo uszkodzony.", []));
                hash = Convert.ToHexString(await SHA256.HashDataAsync(file, cancellation)).ToLowerInvariant();
            }
            if (hash != release.SetupSha256) throw new UpdateException(translate("Pobrany instalator jest niekompletny albo uszkodzony.", []));
            File.Move(partial, path, true);
            return path;
        }
        catch
        {
            try { File.Delete(partial); } catch (IOException) { }
            throw;
        }
    }
}
