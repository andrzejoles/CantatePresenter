using System.Text.Json.Nodes;
using CantatePresenter.Core.Input;

namespace CantatePresenter.Core.Models;

/// <summary>
/// settings.json wspólny z macOS i wersją webową. Cały obiekt JSON jest zachowywany (pola tylko z macOS, np. ekran
/// czy Dysk Google, wracają bez zmian), a te same klucze i wartości domyślne mają typowane właściwości.
/// </summary>
public sealed class AppSettings
{
    /// <summary>Wersja formatu danych, jak DataSchema.current w macOS.</summary>
    public const int SchemaVersionCurrent = 1;

    private readonly JsonObject json;

    private AppSettings(JsonObject json) => this.json = json;

    public static AppSettings Default() => FromJson(new JsonObject());

    /// <summary>Tolerancyjny odczyt: wartości spoza zakresu i nieznane kody dostają wartości domyślne (jak normalizeSettings).</summary>
    public static AppSettings FromJson(JsonNode? raw)
    {
        var input = raw is JsonObject obj ? (JsonObject)obj.DeepClone() : new JsonObject();
        var settings = new AppSettings(input);
        settings.OriginalSchemaVersion = Json.Int(input["schemaVersion"]) ?? 0;
        settings.Normalize();
        return settings;
    }

    /// <summary>Wersja formatu w pliku przed wczytaniem (0 dla plików sprzed pola schemaVersion).</summary>
    public int OriginalSchemaVersion { get; private set; }

    private void Normalize()
    {
        static double Clamp(double? v, double def, double min, double max) => v is double d ? Math.Min(max, Math.Max(min, d)) : def;
        json["fontFamily"] = Json.Str(json["fontFamily"], "Helvetica Neue");
        json["isBold"] = Json.Bool(json["isBold"]) ?? true;
        json["textColorHex"] = Json.Str(json["textColorHex"], "#FFFFFF");
        json["backgroundColorHex"] = Json.Str(json["backgroundColorHex"], "#000000");
        json["hasShadow"] = Json.Bool(json["hasShadow"]) ?? true;
        json["textAlignment"] = Json.Str(json["textAlignment"]).ToLowerInvariant() switch
        {
            "left" or "lewo" => "left",
            "right" or "prawo" => "right",
            _ => "center",
        };
        var vertical = Json.Str(json["verticalAlignment"]).ToLowerInvariant();
        json["verticalAlignment"] = vertical is "top" or "center" or "bottom" ? vertical : "center";
        json["marginPercent"] = Clamp(Json.Number(json["marginPercent"]), 0.07, 0, 0.3);
        json["lineSpacingFactor"] = Clamp(Json.Number(json["lineSpacingFactor"]), 1.15, 0.8, 2);
        json["uiScale"] = Clamp(Json.Number(json["uiScale"]), 1.0, 0.7, 2);
        json["appLanguage"] = Json.Str(json["appLanguage"], "pl");
        json["activeLogoId"] = Json.Str(json["activeLogoId"], "light_of_glory");
        json["ccliLicenseNumber"] = Json.Str(json["ccliLicenseNumber"]);
        var placement = Json.Str(json["copyrightNoticePlacement"]);
        json["copyrightNoticePlacement"] = placement is "none" or "firstSlide" or "lastSlide" or "allSlides" ? placement : "firstSlide";
        json["musicianFontSize"] = Clamp(Json.Number(json["musicianFontSize"]), 30, 14, 80);
        json["musicianTranspose"] = (Json.Int(json["musicianTranspose"]) ?? 0) % 12;
        json["onlineSearchLanguage"] = Json.Str(json["onlineSearchLanguage"], "pl");
        json["dictationLanguage"] = Json.Str(json["dictationLanguage"], "pl-PL");
        json["dictationOnDeviceOnly"] = Json.Bool(json["dictationOnDeviceOnly"]) ?? false;
        var shortcuts = json["shortcuts"] as JsonObject ?? new JsonObject();
        var defaults = new ShortcutSettings();
        int Key(string name, int fallback) => Json.Int(shortcuts[name]) is int v && v is >= 0 and < 65536 ? v : fallback;
        Shortcuts = new ShortcutSettings(
            Key("nextSlideKey", defaults.NextSlideKey), Key("prevSlideKey", defaults.PrevSlideKey), Key("prevSongKey", defaults.PrevSongKey),
            Key("nextSongKey", defaults.NextSongKey), Key("startPresentationKey", defaults.StartPresentationKey),
            Key("stopPresentationKey", defaults.StopPresentationKey), Key("blackScreenKey", defaults.BlackScreenKey), Key("clearTextKey", defaults.ClearTextKey));
        json["schemaVersion"] = SchemaVersionCurrent;
    }

    public ShortcutSettings Shortcuts
    {
        get => shortcutsValue;
        set
        {
            shortcutsValue = value;
            var shortcuts = json["shortcuts"] as JsonObject ?? new JsonObject();
            shortcuts["nextSlideKey"] = value.NextSlideKey;
            shortcuts["prevSlideKey"] = value.PrevSlideKey;
            shortcuts["prevSongKey"] = value.PrevSongKey;
            shortcuts["nextSongKey"] = value.NextSongKey;
            shortcuts["startPresentationKey"] = value.StartPresentationKey;
            shortcuts["stopPresentationKey"] = value.StopPresentationKey;
            shortcuts["blackScreenKey"] = value.BlackScreenKey;
            shortcuts["clearTextKey"] = value.ClearTextKey;
            json["shortcuts"] = shortcuts;
        }
    }
    private ShortcutSettings shortcutsValue = new();

    public string FontFamily { get => Json.Str(json["fontFamily"]); set => json["fontFamily"] = value; }
    public bool IsBold { get => Json.Bool(json["isBold"]) ?? true; set => json["isBold"] = value; }
    public string TextColorHex { get => Json.Str(json["textColorHex"]); set => json["textColorHex"] = value; }
    public string BackgroundColorHex { get => Json.Str(json["backgroundColorHex"]); set => json["backgroundColorHex"] = value; }
    public bool HasShadow { get => Json.Bool(json["hasShadow"]) ?? true; set => json["hasShadow"] = value; }
    /// <summary>„left”, „center” albo „right”.</summary>
    public string TextAlignment { get => Json.Str(json["textAlignment"]); set => json["textAlignment"] = value; }
    /// <summary>„top”, „center” albo „bottom”.</summary>
    public string VerticalAlignment { get => Json.Str(json["verticalAlignment"]); set => json["verticalAlignment"] = value; }
    public double MarginPercent { get => Json.Number(json["marginPercent"]) ?? 0.07; set => json["marginPercent"] = Math.Clamp(value, 0, 0.3); }
    public double LineSpacingFactor { get => Json.Number(json["lineSpacingFactor"]) ?? 1.15; set => json["lineSpacingFactor"] = Math.Clamp(value, 0.8, 2); }
    public double UiScale { get => Json.Number(json["uiScale"]) ?? 1; set => json["uiScale"] = Math.Clamp(value, 0.7, 2); }
    public string AppLanguage { get => Json.Str(json["appLanguage"], "pl"); set => json["appLanguage"] = value; }
    public string ActiveLogoId { get => Json.Str(json["activeLogoId"]); set => json["activeLogoId"] = value; }
    public string CcliLicenseNumber { get => Json.Str(json["ccliLicenseNumber"]); set => json["ccliLicenseNumber"] = value; }
    /// <summary>„none”, „firstSlide”, „lastSlide” albo „allSlides”.</summary>
    public string CopyrightNoticePlacement { get => Json.Str(json["copyrightNoticePlacement"]); set => json["copyrightNoticePlacement"] = value; }
    public double MusicianFontSize { get => Json.Number(json["musicianFontSize"]) ?? 30; set => json["musicianFontSize"] = Math.Clamp(value, 14, 80); }
    public int MusicianTranspose { get => Json.Int(json["musicianTranspose"]) ?? 0; set => json["musicianTranspose"] = value % 12; }
    public string OnlineSearchLanguage { get => Json.Str(json["onlineSearchLanguage"], "pl"); set => json["onlineSearchLanguage"] = value; }
    /// <summary>Ekran projekcji w Windows (nazwa urządzenia monitora); macOS używa własnych pól.</summary>
    public string WindowsScreenDevice { get => Json.Str(json["windowsScreenDevice"]); set => json["windowsScreenDevice"] = value; }

    public string DictationLanguage { get => Json.Str(json["dictationLanguage"], "pl-PL"); set => json["dictationLanguage"] = value; }
    public bool DictationOnDeviceOnly { get => Json.Bool(json["dictationOnDeviceOnly"]) ?? false; set => json["dictationOnDeviceOnly"] = value; }

    /// <summary>Kopie na Dysku Google (obiekt „googleDrive” jak GoogleDriveSettings w macOS). Tokeny nigdy tu nie trafiają.</summary>
    public GoogleDriveSettings GoogleDrive => new(json["googleDrive"] as JsonObject ?? (JsonObject)(json["googleDrive"] = new JsonObject()));

    public JsonObject ToJson() => (JsonObject)json.DeepClone();
}

/// <summary>Widok na obiekt „googleDrive” w settings.json; pozostałe pola (np. ze starszych wersji macOS) zostają bez zmian.</summary>
public sealed class GoogleDriveSettings(JsonObject json)
{
    public const string DefaultFolder = "CantatePresenter_Backups";

    public bool IsEnabled { get => Json.Bool(json["isEnabled"]) ?? false; set { Fill(); json["isEnabled"] = value; } }
    /// <summary>Adres konta ustawiany po zalogowaniu; tylko do wyświetlenia.</summary>
    public string AccountEmail { get => Json.Str(json["accountEmail"]); set { Fill(); json["accountEmail"] = value; } }
    public string TargetFolder { get => Json.Str(json["targetFolder"], DefaultFolder); set { Fill(); json["targetFolder"] = value; } }
    /// <summary>Folder do zapytań: pusta nazwa oznacza domyślny folder, jak w macOS.</summary>
    public string FolderName => TargetFolder.Trim().Length > 0 ? TargetFolder.Trim() : DefaultFolder;
    public bool AutoBackupOnExit { get => Json.Bool(json["autoBackupOnExit"]) ?? false; set { Fill(); json["autoBackupOnExit"] = value; } }
    /// <summary>Data ostatniej kopii (ISO 8601, jak daty w plikach macOS).</summary>
    public string? LastBackupDate { get => Json.OptStr(json["lastBackupDate"]); set { Fill(); json["lastBackupDate"] = value; } }

    /// <summary>Komplet pól jak przy zapisie z macOS.</summary>
    private void Fill()
    {
        json["isEnabled"] ??= false;
        json["accountEmail"] ??= "";
        json["targetFolder"] ??= DefaultFolder;
        json["autoBackupOnExit"] ??= false;
    }
}
