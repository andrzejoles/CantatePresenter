using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using CantatePresenter.Models;

namespace CantatePresenter.Services
{
    public static class SongExporter
    {
        public static string ExportToJSON(List<Song> songs)
        {
            var options = new JsonSerializerOptions
            {
                WriteIndented = true,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            };
            return JsonSerializer.Serialize(songs, options);
        }

        public static void ExportToFile(List<Song> songs, string filePath)
        {
            var json = ExportToJSON(songs);
            File.WriteAllText(filePath, json, Encoding.UTF8);
        }

        public static void ExportToFolder(List<Song> songs, string targetDirectory)
        {
            if (!Directory.Exists(targetDirectory))
                Directory.CreateDirectory(targetDirectory);

            foreach (var song in songs)
            {
                var safeTitle = string.Join("_", song.Title.Split(Path.GetInvalidFileNameChars())).Trim();
                if (string.IsNullOrEmpty(safeTitle)) safeTitle = "Piesn_" + song.Id;
                var filePath = Path.Combine(targetDirectory, $"{safeTitle}.txt");

                var sb = new StringBuilder();
                sb.AppendLine($"Tytuł: {song.Title}");
                if (!string.IsNullOrWhiteSpace(song.Author))
                    sb.AppendLine($"Autor: {song.Author}");
                if (!string.IsNullOrWhiteSpace(song.Key))
                    sb.AppendLine($"Tonacja: {song.Key}");
                if (song.Tags != null && song.Tags.Count > 0)
                    sb.AppendLine($"Tagi: {string.Join(", ", song.Tags)}");
                sb.AppendLine();
                sb.AppendLine(song.RawLyrics);

                File.WriteAllText(filePath, sb.ToString(), Encoding.UTF8);
            }
        }
    }
}
