namespace CantatePresenter.Core.Data;

/// <summary>
/// Katalog danych jak AppPaths w macOS (K2): %APPDATA%\CantatePresenter albo katalog ze zmiennej CANTATE_DATA_DIR
/// (próby na kopii danych). Te same nazwy plików co w macOS i w kopii zapasowej.
/// </summary>
public sealed class AppPaths(string dataDirectory)
{
    public string DataDirectory { get; } = dataDirectory;
    public string SongsFile => Path.Combine(DataDirectory, "songs.json");
    public string PlansFile => Path.Combine(DataDirectory, "plans.json");
    public string SettingsFile => Path.Combine(DataDirectory, "settings.json");
    public string CcliUsageFile => Path.Combine(DataDirectory, "ccli_usage.json");

    public static AppPaths Default()
    {
        var overridden = Environment.GetEnvironmentVariable("CANTATE_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(overridden)) return new AppPaths(overridden);
        return new AppPaths(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CantatePresenter"));
    }
}
