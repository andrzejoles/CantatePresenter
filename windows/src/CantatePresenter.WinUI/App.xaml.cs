using System.Reflection;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.Localization;
using CantatePresenter.Core.Models;
using Microsoft.UI.Xaml;

namespace CantatePresenter.WinUI;

/// <summary>Logo planszy startowej (web/logos.json, eksport LogoCatalog z macOS).</summary>
public sealed record Logo(string Id, string Name, string Svg);

/// <summary>Usługi wspólne dla okien: dane, tłumaczenia, logo, wersja.</summary>
public static class Services
{
    public static Library Library { get; private set; } = null!;
    public static Catalog Catalog { get; private set; } = new();
    public static IReadOnlyList<Logo> Logos { get; private set; } = [];

    /// <summary>Wersja z kompilacji (scripts/version.sh w CI), jak CFBundleShortVersionString w macOS.</summary>
    public static string Version { get; } =
        typeof(Services).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "dev";

    public static string ResourcePath(string name) => Path.Combine(AppContext.BaseDirectory, "Resources", name);

    public static void Start()
    {
        Catalog = Catalog.Load(ResourcePath("Localizable.xcstrings"));
        Library = new Library(AppPaths.Default()) { Translate = (key, args) => Catalog.T(key, args) };
        Catalog.Language = Library.Settings.AppLanguage;
        try
        {
            Logos = (JsonNode.Parse(File.ReadAllText(ResourcePath("logos.json"))) as JsonArray ?? [])
                .Select(l => new Logo(Json.Str(l?["id"]), Json.Str(l?["name"]), Json.Str(l?["svg"]))).ToList();
        }
        catch (Exception error) when (error is IOException or System.Text.Json.JsonException)
        {
            Logos = [];
        }
    }

    /// <summary>Tekst interfejsu: kluczem jest polski tekst (jak L("…") w macOS).</summary>
    public static string L(string key, params object[] args) => Catalog.T(key, args);

    public static Logo? ActiveLogo => Logos.FirstOrDefault(l => l.Id == Library.Settings.ActiveLogoId) ?? Logos.FirstOrDefault();
}

public partial class App : Application
{
    private MainWindow? window;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            // Zapis do dziennika obok danych; aplikacja nie znika bez śladu.
            try
            {
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "CantatePresenter-error.log"), $"{DateTime.Now:O} {e.Exception}\n");
            }
            catch (IOException)
            {
            }
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Services.Start();
        window = new MainWindow();
        window.Activate();
        var arguments = Environment.GetCommandLineArgs();
        var smoke = Array.IndexOf(arguments, "--smoke-test");
        if (smoke >= 0 && smoke + 1 < arguments.Length) _ = SmokeTest.RunAsync(window, arguments[smoke + 1]);
    }
}
