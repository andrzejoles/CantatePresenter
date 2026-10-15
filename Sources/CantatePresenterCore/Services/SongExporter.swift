import Foundation
import AppKit

public struct SongExporter {
    
    /// Converts a Song to cleanly formatted text file content
    public static func songToText(_ song: Song) -> String {
        var content = ""
        content += "Tytuł: \(song.title)\n"
        if !song.author.isEmpty {
            content += "Autor: \(song.author)\n"
        }
        if !song.key.isEmpty {
            content += "Tonacja: \(song.key)\n"
        }
        if !song.tags.isEmpty {
            content += "Tagi: \(song.tags.joined(separator: ", "))\n"
        }
        content += "\n"
        
        // Stanzas
        if !song.slides.isEmpty {
            for (index, slide) in song.slides.enumerated() {
                content += "[\(slide.label)]\n"
                content += slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if index < song.slides.count - 1 {
                    content += "\n\n"
                }
            }
        } else {
            content += song.rawLyrics
        }
        
        return content
    }
    
    /// Exports multiple songs to formatted JSON Data
    public static func songsToJSONData(_ songs: [Song]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(songs)
    }
    
    /// Exports a single song to a user-chosen .txt file via NSSavePanel
    @MainActor
    public static func exportSongAsTextFile(_ song: Song) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        
        // Clean filename from title
        let safeName = sanitizeFilename(song.title)
        panel.nameFieldStringValue = "\(safeName).txt"
        panel.prompt = Lnow("Eksportuj pieśń")
        panel.message = Lnow("Wybierz miejsce zapisu pliku tekstowego z pieśnią")
        
        if panel.runModal() == .OK, let url = panel.url {
            let text = songToText(song)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    /// Exports all or selected songs to a single JSON backup file
    @MainActor
    public static func exportSongsAsJSONFile(_ songs: [Song], defaultName: String = "Baza_piesni") -> Bool {
        guard let data = songsToJSONData(songs) else { return false }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = "\(defaultName)_\(dateStr).json"
        panel.prompt = Lnow("Eksportuj bazę JSON")
        panel.message = Lnow("Zapisz kopię zapasową bazy pieśni do formatu JSON")
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    /// Exports multiple songs as separate .txt files into a selected directory
    @MainActor
    public static func exportSongsToFolder(_ songs: [Song]) -> Int {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Lnow("Eksportuj do tego folderu")
        panel.message = Lnow("Wybierz folder, do którego zostaną zapisane pliki tekstowe pieśni")
        
        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return 0
        }
        
        do {
            return try exportSongs(songs, to: folderURL)
        } catch {
            return 0
        }
    }
    
    /// Zapisuje każdą pieśń jako osobny plik .txt. Powtórzone tytuły dostają sufiks „ (2)”, „ (3)”
    /// (porównanie bez wielkości liter, jak w APFS), więc żadna pieśń nie nadpisuje innej (S4).
    /// Zwraca liczbę faktycznie zapisanych plików; błąd zapisu przerywa eksport.
    public static func exportSongs(_ songs: [Song], to folderURL: URL) throws -> Int {
        var usedNames: Set<String> = []
        var written = 0
        for song in songs {
            let baseName = sanitizeFilename(song.title)
            var fileName = "\(baseName).txt"
            var counter = 2
            while usedNames.contains(fileName.lowercased()) {
                fileName = "\(baseName) (\(counter)).txt"
                counter += 1
            }
            usedNames.insert(fileName.lowercased())
            try songToText(song).write(to: folderURL.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            written += 1
        }
        return written
    }
    
    private static func sanitizeFilename(_ string: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = string.components(separatedBy: invalidCharacters).joined(separator: "_")
        // Bez znaków nowej linii i kropki na początku (plik ukryty); nazwa w limicie 255 bajtów APFS.
        let trimmed = String(cleaned
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            .prefix(120))
        return trimmed.isEmpty ? "Piesn" : trimmed
    }
}
