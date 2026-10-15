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
        panel.prompt = "Eksportuj pieśń"
        panel.message = "Wybierz miejsce zapisu pliku tekstowego z pieśnią"
        
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
        panel.prompt = "Eksportuj bazę JSON"
        panel.message = "Zapisz kopię zapasową bazy pieśni do formatu JSON"
        
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
        panel.prompt = "Eksportuj do tego folderu"
        panel.message = "Wybierz folder, do którego zostaną zapisane pliki tekstowe pieśni"
        
        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return 0
        }
        
        var exportedCount = 0
        for song in songs {
            let safeName = sanitizeFilename(song.title)
            let fileURL = folderURL.appendingPathComponent("\(safeName).txt")
            let text = songToText(song)
            if (try? text.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                exportedCount += 1
            }
        }
        
        return exportedCount
    }
    
    private static func sanitizeFilename(_ string: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = string.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Piesn" : trimmed
    }
}
