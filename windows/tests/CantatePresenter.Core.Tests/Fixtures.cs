using System.Text.Json;

namespace CantatePresenter.Core.Tests;

/// <summary>Wspólne pliki testowe z shared/fixtures (wzorcem jest wersja macOS; sprawdzają je też testy Swift i JS).</summary>
public static class Fixtures
{
    public static string Directory
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && !System.IO.Directory.Exists(Path.Combine(dir.FullName, "shared", "fixtures"))) dir = dir.Parent;
            return Path.Combine(dir?.FullName ?? throw new DirectoryNotFoundException("shared/fixtures"), "shared", "fixtures");
        }
    }

    public static string PathOf(string name) => Path.Combine(Directory, name);

    public static JsonElement Load(string name) => JsonDocument.Parse(File.ReadAllText(PathOf(name))).RootElement;

    public static string? Str(this JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
