using System.Reflection;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Data;
using CantatePresenter.Core.GoogleDrive;
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
    public static GoogleDriveService Drive { get; private set; } = null!;
    /// <summary>Aplikacja się zamyka: okna pomocnicze mogą się naprawdę zamknąć (zamiast chować).</summary>
    public static bool AppClosing { get; set; }

    /// <summary>Klient OAuth wbudowany przy budowaniu (google-oauth-client.json, jak Info.plist w macOS); null bez pliku.</summary>
    public static GoogleOAuthClient? BundledGoogleClient()
    {
        using var stream = typeof(Services).Assembly.GetManifestResourceStream("google-oauth-client.json");
        if (stream is null) return null;
        using var reader = new StreamReader(stream);
        return GoogleOAuthClient.FromJson(reader.ReadToEnd());
    }

    /// <summary>Wersja z kompilacji (scripts/version.sh w CI), jak CFBundleShortVersionString w macOS.</summary>
    public static string Version { get; } =
        typeof(Services).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "dev";

    public static string ResourcePath(string name) => Path.Combine(AppContext.BaseDirectory, "Resources", name);

    public static void Start()
    {
        Catalog = Catalog.Load(ResourcePath("Localizable.xcstrings"));
        Library = new Library(AppPaths.Default()) { Translate = (key, args) => Catalog.T(key, args) };
        Catalog.Language = Library.Settings.AppLanguage;
        Drive = new GoogleDriveService(BundledGoogleClient(), WindowsCredentialStore.GoogleDrive, new HttpClient { Timeout = TimeSpan.FromMinutes(3) }, (key, args) => Catalog.T(key, args));
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

    /// <summary>Tekst z katalogu wspólnego z macOS, ze skrótami zapisanymi po windowsowemu (⌘E → Ctrl+E, Cmd ? → F1).</summary>
    public static string Lw(string key, params object[] args) => L(key, args)
        .Replace("⌘+Return", "Ctrl+Enter").Replace("Cmd ?", "F1").Replace("Cmd E", "Ctrl+E").Replace("⌘", "Ctrl+").Replace("Cmd ", "Ctrl ");

    /// <summary>Ślad kroków dla próby w CI (CANTATE_TRACE = plik); bez zmiennej nic nie robi.</summary>
    public static void Trace(string step)
    {
        var path = Environment.GetEnvironmentVariable("CANTATE_TRACE");
        if (string.IsNullOrEmpty(path)) return;
        try { File.AppendAllText(path, $"{DateTime.Now:HH:mm:ss.fff} {step}\n"); } catch (IOException) { }
    }

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
                var arguments = Environment.GetCommandLineArgs();
                var smoke = Array.IndexOf(arguments, "--smoke-test");
                if (smoke >= 0 && smoke + 1 < arguments.Length)
                {
                    Directory.CreateDirectory(arguments[smoke + 1]);
                    File.AppendAllText(Path.Combine(arguments[smoke + 1], "unhandled.txt"), e.Exception + "\n");
                }
            }
            catch (IOException)
            {
            }
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var arguments = Environment.GetCommandLineArgs();
        var smoke = Array.IndexOf(arguments, "--smoke-test");
        var smokeDirectory = smoke >= 0 && smoke + 1 < arguments.Length ? arguments[smoke + 1] : null;
        try
        {
            Services.Trace("OnLaunched");
            if (Environment.GetEnvironmentVariable("CANTATE_TRACE") is { Length: > 0 })
            {
                AppDomain.CurrentDomain.FirstChanceException += (_, e) =>
                    Services.Trace($"wyjątek: {e.Exception.GetType().Name}: {e.Exception.Message}\n{string.Join("\n", Environment.StackTrace.Split('\n').Where(l => l.Contains("CantatePresenter") || l.Contains("Microsoft.UI")).Take(14))}");
            }
            Services.Start();
            Services.Trace("Services.Start");
            window = new MainWindow();
            Services.Trace("new MainWindow");
            window.Activate();
            Services.Trace("Activate");
            DebugSettings.BindingFailed += (_, e) => Services.Trace("BindingFailed " + e.Message);
            DebugSettings.XamlResourceReferenceFailed += (_, e) => Services.Trace("XamlResourceReferenceFailed " + e.Message);
            window.DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => Services.Trace("pierwsza pętla UI"));
        }
        catch (Exception error) when (smokeDirectory is not null)
        {
            // Próba w CI: błąd startu trafia do raportu zamiast cichego zamknięcia.
            Directory.CreateDirectory(smokeDirectory);
            File.WriteAllText(Path.Combine(smokeDirectory, "report.json"),
                new System.Text.Json.Nodes.JsonObject { ["exception"] = error.ToString(), ["failures"] = new System.Text.Json.Nodes.JsonArray("startup") }.ToJsonString());
            Exit();
            return;
        }
        if (smokeDirectory is not null) _ = SmokeTest.RunAsync(window, smokeDirectory);
        else _ = Updater.CheckOnStartAsync(window);
    }
}
