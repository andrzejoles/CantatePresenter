using System;
using System.Text.Json.Serialization;

namespace CantatePresenter.Models
{
    public class ShortcutSettings
    {
        [JsonPropertyName("nextSlideKey")]
        public int NextSlideKey { get; set; } = 49; // Space

        [JsonPropertyName("prevSlideKey")]
        public int PrevSlideKey { get; set; } = 123; // Left Arrow

        [JsonPropertyName("prevSongKey")]
        public int PrevSongKey { get; set; } = 33; // [

        [JsonPropertyName("nextSongKey")]
        public int NextSongKey { get; set; } = 30; // ]

        [JsonPropertyName("startPresentationKey")]
        public int StartPresentationKey { get; set; } = 36; // Return

        [JsonPropertyName("stopPresentationKey")]
        public int StopPresentationKey { get; set; } = 53; // Escape

        [JsonPropertyName("blackScreenKey")]
        public int BlackScreenKey { get; set; } = 11; // B

        [JsonPropertyName("clearTextKey")]
        public int ClearTextKey { get; set; } = 8; // C
    }

    public class GoogleDriveSettings
    {
        [JsonPropertyName("isEnabled")]
        public bool IsEnabled { get; set; } = false;

        [JsonPropertyName("accountEmail")]
        public string AccountEmail { get; set; } = "";

        [JsonPropertyName("clientId")]
        public string ClientId { get; set; } = "";

        [JsonPropertyName("clientSecret")]
        public string ClientSecret { get; set; } = "";

        [JsonPropertyName("accessToken")]
        public string AccessToken { get; set; } = "";

        [JsonPropertyName("refreshToken")]
        public string RefreshToken { get; set; } = "";

        [JsonPropertyName("targetFolder")]
        public string TargetFolder { get; set; } = "CantatePresenter_Backups";

        [JsonPropertyName("autoBackupOnExit")]
        public bool AutoBackupOnExit { get; set; } = false;
    }

    public class AppSettings
    {
        [JsonPropertyName("appLanguage")]
        public string AppLanguage { get; set; } = "pl";

        [JsonPropertyName("verticalAlignment")]
        public string VerticalAlignment { get; set; } = "center";

        [JsonPropertyName("activeLogoId")]
        public string ActiveLogoId { get; set; } = "equipes_notre_dame";

        [JsonPropertyName("selectedScreenIndex")]
        public int SelectedScreenIndex { get; set; } = 1;

        [JsonPropertyName("fontFamily")]
        public string FontFamily { get; set; } = "Segoe UI";

        [JsonPropertyName("uiScale")]
        public double UiScale { get; set; } = 1.0;

        [JsonPropertyName("standbyHtmlPath")]
        public string StandbyHtmlPath { get; set; } = "";

        [JsonPropertyName("textAlignment")]
        public string TextAlignment { get; set; } = "center";

        [JsonPropertyName("isBold")]
        public bool IsBold { get; set; } = true;

        [JsonPropertyName("marginPercent")]
        public double MarginPercent { get; set; } = 0.07;

        [JsonPropertyName("lineSpacingFactor")]
        public double LineSpacingFactor { get; set; } = 1.15;

        [JsonPropertyName("bottomBarHeight")]
        public double BottomBarHeight { get; set; } = 64.0;

        [JsonPropertyName("textColorHex")]
        public string TextColorHex { get; set; } = "#FFFFFF";

        [JsonPropertyName("backgroundColorHex")]
        public string BackgroundColorHex { get; set; } = "#000000";

        [JsonPropertyName("isWindowedPreviewEnabled")]
        public bool IsWindowedPreviewEnabled { get; set; } = false;

        [JsonPropertyName("hasShadow")]
        public bool HasShadow { get; set; } = true;

        [JsonPropertyName("onlineSearchLanguage")]
        public string OnlineSearchLanguage { get; set; } = "pl";

        [JsonPropertyName("dictationLanguage")]
        public string DictationLanguage { get; set; } = "pl-PL";

        [JsonPropertyName("googleDrive")]
        public GoogleDriveSettings GoogleDrive { get; set; } = new();

        [JsonPropertyName("shortcuts")]
        public ShortcutSettings Shortcuts { get; set; } = new();
    }
}
