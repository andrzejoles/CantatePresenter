using System.Text.Json;
using System.Text.Json.Nodes;
using CantatePresenter.Core.Models;

namespace CantatePresenter.Core.Data;

/// <summary>Eksport pieśni do .txt i JSON, 1:1 z SongExporter w macOS (te same nagłówki, nazwy plików i podział na slajdy).</summary>
public static class SongExport
{
    private static readonly char[] InvalidCharacters = ['\\', '/', ':', '*', '?', '"', '<', '>', '|'];

    /// <summary>Tekst pieśni: nagłówki „Tytuł:”, „Autor:”… (format danych, nie tłumaczony) i slajdy z etykietami.</summary>
    public static string ToText(Song song)
    {
        var content = $"Tytuł: {song.Title}\n";
        if (song.Author.Length > 0) content += $"Autor: {song.Author}\n";
        if (song.Key.Length > 0) content += $"Tonacja: {song.Key}\n";
        if (song.Tags.Count > 0) content += $"Tagi: {string.Join(", ", song.Tags)}\n";
        content += "\n";
        if (song.Slides.Count > 0)
        {
            content += string.Join("\n\n", song.Slides.Select(slide => $"[{slide.Label}]\n{slide.Text.Trim()}"));
        }
        else
        {
            content += song.RawLyrics;
        }
        return content;
    }

    /// <summary>Nazwa pliku z tytułu: bez znaków zabronionych i nowych linii, bez kropek na brzegach, do 120 znaków.</summary>
    public static string SafeFileName(string title)
    {
        var cleaned = string.Join("_", title.Split(InvalidCharacters));
        cleaned = string.Join(" ", cleaned.Split(['\r', '\n', '\u2028', '\u2029']));
        static bool Edge(char c) => char.IsWhiteSpace(c) || c == '.';
        var start = 0;
        var end = cleaned.Length;
        while (start < end && Edge(cleaned[start])) start++;
        while (end > start && Edge(cleaned[end - 1])) end--;
        cleaned = cleaned[start..end];
        if (cleaned.Length > 120) cleaned = cleaned[..120];
        return cleaned.Length > 0 ? cleaned : "Piesn";
    }

    /// <summary>Pliki .txt do folderu: powtórzone tytuły dostają „ (2)”, „ (3)” (bez rozróżniania wielkości liter, S4).</summary>
    public static List<(string FileName, string Text)> Folder(IEnumerable<Song> songs)
    {
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var files = new List<(string, string)>();
        foreach (var song in songs)
        {
            var baseName = SafeFileName(song.Title);
            var fileName = $"{baseName}.txt";
            for (var counter = 2; used.Contains(fileName); counter++) fileName = $"{baseName} ({counter}).txt";
            used.Add(fileName);
            files.Add((fileName, ToText(song)));
        }
        return files;
    }

    /// <summary>Tablica pieśni w formacie songs.json (czytelny zapis).</summary>
    public static string ToJson(IEnumerable<Song> songs) =>
        new JsonArray(songs.Select(s => (JsonNode)s.ToJson()).ToArray())
            .ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
}
