using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace CantatePresenter.Models
{
    public class BackupManifest
    {
        [JsonPropertyName("version")]
        public string Version { get; set; } = "1.0.0";

        [JsonPropertyName("appName")]
        public string AppName { get; set; } = "CantatePresenter";

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("deviceName")]
        public string DeviceName { get; set; } = Environment.MachineName;

        [JsonPropertyName("songsCount")]
        public int SongsCount { get; set; } = 0;

        [JsonPropertyName("plansCount")]
        public int PlansCount { get; set; } = 0;

        [JsonPropertyName("activeLogoId")]
        public string ActiveLogoId { get; set; } = "";

        [JsonPropertyName("appLanguage")]
        public string AppLanguage { get; set; } = "pl";

        [JsonPropertyName("includedFiles")]
        public List<string> IncludedFiles { get; set; } = new();

        [JsonPropertyName("comment")]
        public string? Comment { get; set; }
    }
}
