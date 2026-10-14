using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace CantatePresenter.Models
{
    public class ServicePlanItem
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("songId")]
        public Guid SongId { get; set; }

        [JsonPropertyName("note")]
        public string Note { get; set; } = "";
    }

    public class ServicePlan
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("name")]
        public string Name { get; set; } = "Nowy zestaw pieśni";

        [JsonPropertyName("items")]
        public List<ServicePlanItem> Items { get; set; } = new();

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("updatedAt")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
