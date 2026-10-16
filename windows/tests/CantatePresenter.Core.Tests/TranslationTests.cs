using System.Text.RegularExpressions;
using CantatePresenter.Core.Localization;
using Xunit;

namespace CantatePresenter.Core.Tests;

/// <summary>Każdy tekst interfejsu Windows (L("…"), Translate("…")) ma tłumaczenie we wspólnym katalogu z macOS.</summary>
public class TranslationTests
{
    [Fact]
    public void EveryWindowsTextIsInTheCatalog()
    {
        var root = Path.GetDirectoryName(Fixtures.Directory)!;
        root = Path.GetDirectoryName(root)!;
        var catalog = Catalog.Load(Path.Combine(root, "Sources", "CantatePresenterCore", "Resources", "Localizable.xcstrings"));
        var pattern = new Regex(@"\b(?:L|Translate)\(""((?:[^""\\]|\\.)*)""");
        var missing = new List<string>();
        foreach (var file in Directory.GetFiles(Path.Combine(root, "windows", "src"), "*.cs", SearchOption.AllDirectories))
        {
            foreach (Match match in pattern.Matches(File.ReadAllText(file)))
            {
                var key = Regex.Unescape(match.Groups[1].Value);
                if (key != "…" && !catalog.Contains(key)) missing.Add($"{Path.GetFileName(file)}: {key}");
            }
        }
        Assert.Empty(missing);

        catalog.Language = "en";
        Assert.Equal("Screen 2", catalog.T("Ekran {0}", 2));
        catalog.Language = "pl";
        Assert.Equal("Ekran 2", catalog.T("Ekran {0}", 2));
    }
}
