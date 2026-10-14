import Foundation
import AppKit

public struct TextImporter {
    
    /// Imports songs from multiple file URLs (.txt or .json) with auto encoding detection
    public static func importFiles(from urls: [URL]) -> [Song] {
        var importedSongs: [Song] = []
        for url in urls {
            importedSongs.append(contentsOf: importFromURL(url))
        }
        return importedSongs
    }
    
    /// Imports songs from a single URL (supports Holyrics .muf/.mufl/.hly, .txt, .json, .xml, or directories)
    public static func importFromURL(_ url: URL) -> [Song] {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Scan folder for supported song files
            var songsFromFolder: [Song] = []
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    let supportedExts = ["txt", "json", "muf", "mufl", "hly", "holyrics", "xml", "zip"]
                    if supportedExts.contains(ext) {
                        songsFromFolder.append(contentsOf: importFromURL(fileURL))
                    }
                }
            }
            return songsFromFolder
        }
        
        let ext = url.pathExtension.lowercased()
        
        // 1. Check for Holyrics files (.muf, .mufl, .hly, .holyrics, .xml, or .zip)
        if HolyricsImporter.isHolyricsFile(url: url) || ext == "zip" {
            let holyricsSongs = HolyricsImporter.importFromURL(url)
            if !holyricsSongs.isEmpty {
                return holyricsSongs
            }
        }
        
        // 2. Check for JSON
        if ext == "json" {
            if let data = try? Data(contentsOf: url) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let songArray = try? decoder.decode([Song].self, from: data) {
                    return songArray
                } else if let singleSong = try? decoder.decode(Song.self, from: data) {
                    return [singleSong]
                } else {
                    // Try Holyrics JSON format
                    let holyricsSongs = HolyricsImporter.importFromURL(url)
                    if !holyricsSongs.isEmpty {
                        return holyricsSongs
                    }
                }
            }
        }
        
        // 3. Default text file parsing
        if let song = parseFile(at: url) {
            return [song]
        }
        
        return []
    }
    
    /// Parses a single text file
    public static func parseFile(at url: URL) -> Song? {
        guard let text = readTextWithBestEncoding(from: url) else { return nil }
        
        let filenameTitle = url.deletingPathExtension().lastPathComponent
        return parseString(rawContent: text, fallbackTitle: filenameTitle)
    }
    
    /// Parses raw text into a Song structure
    public static func parseString(rawContent: String, fallbackTitle: String = "Nowa pieśń") -> Song {
        let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
                                   .replacingOccurrences(of: "\r", with: "\n")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let lines = normalized.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            return Song(title: fallbackTitle, rawLyrics: "")
        }
        
        var title = fallbackTitle
        var author = ""
        var key = ""
        var tags: [String] = []
        var lyricsStartIndex = 0
        
        // Scan first lines for metadata (e.g. Title:, Autor:, Tonacja:)
        for (i, rawLine) in lines.prefix(8).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            
            if lower.hasPrefix("tytuł:") || lower.hasPrefix("tytul:") || lower.hasPrefix("title:") {
                title = String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                lyricsStartIndex = max(lyricsStartIndex, i + 1)
            } else if lower.hasPrefix("autor:") || lower.hasPrefix("author:") {
                author = String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                lyricsStartIndex = max(lyricsStartIndex, i + 1)
            } else if lower.hasPrefix("tonacja:") || lower.hasPrefix("klucz:") || lower.hasPrefix("key:") {
                key = String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                lyricsStartIndex = max(lyricsStartIndex, i + 1)
            } else if lower.hasPrefix("tagi:") || lower.hasPrefix("kategoria:") || lower.hasPrefix("tags:") {
                let tagsStr = String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                tags = tagsStr.components(separatedBy: CharacterSet(charactersIn: ",;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                lyricsStartIndex = max(lyricsStartIndex, i + 1)
            } else if i == 0 && !line.hasPrefix("[") && !line.lowercased().hasPrefix("1.") && !line.lowercased().hasPrefix("ref") {
                // If the very first line isn't a verse marker, it can be the title
                title = line
                lyricsStartIndex = 1
            }
        }
        
        let remainingLines = Array(lines.dropFirst(lyricsStartIndex))
        let lyrics = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Song(
            title: title.isEmpty ? fallbackTitle : title,
            author: author,
            key: key,
            tags: tags,
            rawLyrics: lyrics
        )
    }
    
    /// Reads text file trying UTF-8, Windows-1250 (common for Polish songs), and ISO-8859-2
    public static func readTextWithBestEncoding(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        var decodedString: String? = nil
        
        // 1. Try UTF-8
        if let str = String(data: data, encoding: .utf8) {
            decodedString = str
        }
        // 2. Try Windows-1250 (Central European / Polish Windows standard)
        else {
            let windows1250 = CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)
            let nsWindows1250 = CFStringConvertEncodingToNSStringEncoding(windows1250)
            if let str = String(data: data, encoding: String.Encoding(rawValue: nsWindows1250)) {
                decodedString = str
            }
            // 3. Try ISO Latin 2 (ISO-8859-2)
            else {
                let isoLatin2 = CFStringEncoding(CFStringEncodings.isoLatin2.rawValue)
                let nsIsoLatin2 = CFStringConvertEncodingToNSStringEncoding(isoLatin2)
                if let str = String(data: data, encoding: String.Encoding(rawValue: nsIsoLatin2)) {
                    decodedString = str
                }
                // 4. Fallback to ASCII / MacOSRoman
                else if let str = String(data: data, encoding: .macOSRoman) {
                    decodedString = str
                } else {
                    decodedString = String(data: data, encoding: .ascii)
                }
            }
        }
        
        guard let finalString = decodedString else { return nil }
        return PolishEncodingService.shared.repairMojibake(finalString)
    }
    
    /// Prompts native file dialog to pick .txt or .json files or a folder
    @MainActor
    public static func pickFilesForImport() -> [Song] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["txt", "json", "muf", "mufl", "hly", "holyrics", "xml", "zip"]
        panel.prompt = "Importuj pieśni"
        panel.message = "Wybierz pliki Holyrics (.muf, .mufl, .hly), pliki tekstowe (.txt), XML, JSON lub archiwum ZIP"
        
        if panel.runModal() == .OK {
            return importFiles(from: panel.urls)
        }
        return []
    }
}
