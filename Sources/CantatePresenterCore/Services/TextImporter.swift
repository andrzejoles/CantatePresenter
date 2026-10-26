import Foundation
import AppKit

public struct TextImporter {
    
    /// Rozszerzenia plików rozpoznawane przy imporcie (także w oknie wyboru plików).
    public static let supportedExtensions: [String] = ["txt", "json", "muf", "mufl", "hly", "holyrics", "xml", "zip", "usr"]
        + SongSelectImporter.chordProExtensions.sorted()
    
    /// Imports songs from a single URL (supports Holyrics .muf/.mufl/.hly, .txt, .json, .xml, or directories)
    public static func importFromURL(_ url: URL) -> [Song] {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Scan folder for supported song files
            var songsFromFolder: [Song] = []
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    let supportedExts = supportedExtensions
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
                let decoded = decodeSongsFromJSON(data: data)
                if !decoded.isEmpty {
                    return decoded
                }
                
                // Fallback to Holyrics JSON format
                let holyricsSongs = HolyricsImporter.importFromURL(url)
                if !holyricsSongs.isEmpty {
                    return holyricsSongs
                }
            }
        }
        
        // 3. Pliki z CCLI SongSelect (.usr, ChordPro, tekst ze stopką „CCLI Song #”)
        if ext == "usr" || SongSelectImporter.chordProExtensions.contains(ext) {
            guard let text = readTextWithBestEncoding(from: url) else { return [] }
            if ext == "usr" {
                return SongSelectImporter.parseUSR(text).map { [$0] } ?? []
            }
            return [SongSelectImporter.parseChordPro(text, fallbackTitle: url.deletingPathExtension().lastPathComponent)]
        }
        if ext == "txt", let text = readTextWithBestEncoding(from: url), SongSelectImporter.isSongSelectText(text),
           let song = SongSelectImporter.parseText(text) {
            return [song]
        }
        
        // 4. Default text file parsing
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
    
    /// Reads text file trying UTF-8 and the common Polish single-byte encodings (S6)
    public static func readTextWithBestEncoding(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeText(data)
    }
    
    /// Kodowania jednobajtowe próbowane, gdy plik nie jest poprawnym UTF-8. Kolejność rozstrzyga remisy.
    private static let singleByteCandidates: [String.Encoding] = [
        CFStringEncodings.windowsLatin2, .isoLatin2, .macCentralEurRoman
    ].map { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding($0.rawValue))) }
        + [.macOSRoman]
    
    private static let polishLetters = Set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
    /// Znaki typowe dla złego kodowania polskiego tekstu, np. ISO-8859-2 czytane jako Windows-1250 („ą” → „±”, „ś” → „¶”).
    private static let suspiciousCharacters = Set("±¶¼¦¬ˇ˘˝˙¤§¨®°µ·¸ŠšŤťŽľĽĹĺŕŔřŘůŮ∂∑∏√∞≈≠≤≥◊ﬁﬂ")
    
    /// Dekoduje tekst: UTF-8, a jeśli to niemożliwe, to kodowanie jednobajtowe z najlepszym wynikiem
    /// (najwięcej polskich liter, najmniej znaków podejrzanych i sterujących). Wcześniej Windows-1250
    /// prawie zawsze „się udawało”, więc ISO-8859-2 nie było nigdy próbowane.
    public static func decodeText(_ data: Data) -> String? {
        if var utf8 = String(data: data, encoding: .utf8) {
            if utf8.hasPrefix("\u{FEFF}") {
                utf8.removeFirst()
            }
            return PolishEncodingService.shared.repairMojibake(utf8)
        }
        
        func score(_ text: String) -> Int {
            var result = 0
            for character in text {
                if polishLetters.contains(character) {
                    result += 2
                } else if suspiciousCharacters.contains(character) {
                    result -= 3
                } else if let scalar = character.unicodeScalars.first,
                          scalar.properties.generalCategory == .control,
                          !"\n\r\t".unicodeScalars.contains(scalar) {
                    result -= 5
                }
            }
            return result
        }
        
        let best = singleByteCandidates
            .compactMap { String(data: data, encoding: $0) }
            .enumerated()
            .max { lhs, rhs in
                let (left, right) = (score(lhs.element), score(rhs.element))
                // Przy remisie wygrywa wcześniejszy kandydat.
                return left == right ? lhs.offset > rhs.offset : left < right
            }?.element
        guard let decoded = best ?? String(data: data, encoding: .ascii) else { return nil }
        return PolishEncodingService.shared.repairMojibake(decoded)
    }
    
    /// Decodes songs from JSON Data supporting multiple date strategies, single song, arrays, and wrapper objects
    public static func decodeSongsFromJSON(data: Data) -> [Song] {
        // Strategy 1: ISO-8601 [Song]
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let songs = try? isoDecoder.decode([Song].self, from: data), !songs.isEmpty {
            return songs
        }
        
        // Strategy 2: Default DeferredToDate [Song] (native DataStore format)
        let defDecoder = JSONDecoder()
        if let songs = try? defDecoder.decode([Song].self, from: data), !songs.isEmpty {
            return songs
        }
        
        // Strategy 3: Flexible Date Decoder [Song]
        let flexDecoder = JSONDecoder()
        flexDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            if let str = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                if let d = formatter.date(from: str) { return d }
                let df = DateFormatter()
                df.locale = Locale(identifier: "pl_PL")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let d = df.date(from: str) { return d }
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let d = df.date(from: str) { return d }
                df.dateFormat = "yyyy-MM-dd"
                if let d = df.date(from: str) { return d }
            }
            return Date()
        }
        if let songs = try? flexDecoder.decode([Song].self, from: data), !songs.isEmpty {
            return songs
        }
        
        // Strategy 4: Single Song object
        if let single = try? isoDecoder.decode(Song.self, from: data) {
            return [single]
        }
        if let single = try? defDecoder.decode(Song.self, from: data) {
            return [single]
        }
        if let single = try? flexDecoder.decode(Song.self, from: data) {
            return [single]
        }
        
        // Strategy 5: Wrapper object { "songs": [...], "items": [...] }
        struct SongsWrapper: Decodable {
            let songs: [Song]?
            let items: [Song]?
            let piesni: [Song]?
            let library: [Song]?
        }
        if let wrapper = try? flexDecoder.decode(SongsWrapper.self, from: data) {
            if let list = wrapper.songs, !list.isEmpty { return list }
            if let list = wrapper.items, !list.isEmpty { return list }
            if let list = wrapper.piesni, !list.isEmpty { return list }
            if let list = wrapper.library, !list.isEmpty { return list }
        }
        
        // Strategy 6: Generic JSON array of dictionaries with loose keys
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let array = jsonObject as? [[String: Any]] {
            var extracted: [Song] = []
            for item in array {
                let title = (item["title"] as? String) ?? (item["tytul"] as? String) ?? (item["tytuł"] as? String) ?? (item["name"] as? String) ?? "Bez tytułu"
                let author = (item["author"] as? String) ?? (item["autor"] as? String) ?? ""
                let key = (item["key"] as? String) ?? (item["tonacja"] as? String) ?? ""
                let tags = (item["tags"] as? [String]) ?? (item["tagi"] as? [String]) ?? []
                let chords = item["chords"] as? String
                let lyrics = (item["rawLyrics"] as? String) ?? (item["lyrics"] as? String) ?? (item["text"] as? String) ?? (item["tekst"] as? String) ?? ""
                if !title.isEmpty || !lyrics.isEmpty {
                    extracted.append(Song(title: title, author: author, key: key, tags: tags, rawLyrics: lyrics, chords: chords))
                }
            }
            if !extracted.isEmpty {
                return extracted
            }
        }
        
        return []
    }
}
