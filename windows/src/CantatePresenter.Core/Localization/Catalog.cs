using System.Globalization;
using System.Text.Json.Nodes;

namespace CantatePresenter.Core.Localization;

/// <summary>
/// Tłumaczenia z tego samego String Catalog co macOS i wersja webowa (Localizable.xcstrings): kluczem jest polski tekst,
/// wartości wstawiane jako {0}, {1}. Brak tłumaczenia = tekst polski.
/// </summary>
public sealed class Catalog
{
    public static readonly (string Code, string Name)[] Languages =
        [("pl", "Polski"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("uk", "Українська")];

    private readonly Dictionary<string, Dictionary<string, string>> strings = [];

    public string Language { get; set; } = "pl";

    public static Catalog Load(string path)
    {
        var catalog = new Catalog();
        if (!File.Exists(path)) return catalog;
        var root = JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
        foreach (var (key, entry) in root?["strings"] as JsonObject ?? [])
        {
            var values = new Dictionary<string, string>();
            foreach (var (language, localization) in entry?["localizations"] as JsonObject ?? [])
            {
                if (localization?["stringUnit"]?["value"]?.GetValue<string>() is string value) values[language] = value;
            }
            catalog.strings[key] = values;
        }
        return catalog;
    }

    public bool Contains(string key) => strings.ContainsKey(key);

    public string T(string key, params object[] args)
    {
        var template = Language != "pl" && strings.TryGetValue(key, out var values) && values.TryGetValue(Language, out var value) ? value : key;
        for (var i = 0; i < args.Length; i++) template = template.Replace("{" + i + "}", Convert.ToString(args[i], CultureInfo.CurrentCulture));
        return template;
    }
}
