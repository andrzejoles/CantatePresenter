import Foundation
import AppKit

public struct HolyricsImporter {
    
    /// Checks if a file URL is a known Holyrics file format
    public static func isHolyricsFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "muf" || ext == "mufl" || ext == "hly" || ext == "holyrics" || ext == "xml"
    }
    
    /// Wzorce znaczników Holyrics kompilowane raz, a nie dla każdej importowanej pieśni (N3).
    /// ##(Verse 1) -> [Zwrotka 1], ##(Chorus 1) -> [Refren] itd.
    private static let verseMarkerReplacements: [(NSRegularExpression, String)] = [
        (#"##\(Verse\s*(\d+)\)"#, "[Zwrotka $1]"),
        (#"##\(Verse\)"#, "[Zwrotka]"),
        (#"##\(Chorus\s*(\d*)\)"#, "[Refren]"),
        (#"##\(Bridge\s*(\d*)\)"#, "[Bridge]"),
        (#"##\(Coda\s*(\d*)\)"#, "[Coda]"),
        (#"##\(Intro\s*(\d*)\)"#, "[Wstęp]"),
        (#"##\((Outro|Ending)\s*(\d*)\)"#, "[Zakończenie]"),
        (#"##\(Pre-Chorus\s*(\d*)\)"#, "[Przed-refren]"),
        (#"##\((Tag|Interlude)\s*(\d*)\)"#, "[Przejście]"),
        (#"##\(([^)]+)\)"#, "[$1]")
    ].map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }
    
    /// Translates Holyrics verse section markers into presentation slide tags
    public static func translateHolyricsVerseMarkers(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
        
        // Convert ##(Verse 1) -> [Zwrotka 1], ##(Chorus 1) -> [Refren], etc.
        
        for (regex, template) in verseMarkerReplacements {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
        }
        
        return result
    }
    
    /// Converts a raw Java-deserialized Holyrics Music object to a Song model
    public static func convertRawRecordToSong(_ rec: HolyricsJavaDeserializer.RawMusicRecord) -> Song {
        var title = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = "Pieśń Holyrics"
        }
        
        var author = rec.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.isEmpty {
            author = rec.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let cleanedLyrics = translateHolyricsVerseMarkers(rec.lyrics)
        
        var tags = ["Import Holyrics"]
        if !rec.note.isEmpty {
            tags.append(rec.note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return Song(
            title: title,
            author: author,
            key: rec.key,
            tags: tags,
            rawLyrics: cleanedLyrics
        )
    }
    
    /// Imports songs from any Holyrics file (.muf, .mufl, .hly, .holyrics, .xml, .json, .txt) with basic deduplication
    /// Reads raw songs from any Holyrics file without deduplication (for batch processing)
    public static func readRawSongs(from url: URL) -> [Song] {
        let ext = url.pathExtension.lowercased()
        
        // 1. ZIP package
        if ext == "zip" || ext == "hly" || ext == "holyrics" {
            if let zipSongs = importFromArchive(at: url), !zipSongs.isEmpty {
                return zipSongs
            }
        }
        
        // 2. Java ObjectStream (.mufl / .muf)
        if let fileData = try? Data(contentsOf: url), HolyricsJavaDeserializer.isJavaSerializedStream(fileData) {
            let deserializer = HolyricsJavaDeserializer(data: fileData)
            if let rawRecords = try? deserializer.deserializeMusicRecords(), !rawRecords.isEmpty {
                return rawRecords.map { convertRawRecordToSong($0) }
            }
        }
        
        // 3. Text parsing (JSON, XML, or tagged TXT)
        guard let content = TextImporter.readTextWithBestEncoding(from: url) else {
            return []
        }
        
        let filename = url.deletingPathExtension().lastPathComponent
        return parseHolyricsContent(content, fallbackTitle: filename)
    }
    
    /// Imports songs from any Holyrics file (.muf, .mufl, .hly, .holyrics, .xml, .json, .txt) with basic deduplication
    public static func importFromURL(_ url: URL) -> [Song] {
        return readRawSongs(from: url)
    }
    
    /// Parses string content formatted as Holyrics Music File (.muf/.mufl), JSON, XML, or tagged TXT
    public static func parseHolyricsContent(_ rawContent: String, fallbackTitle: String = "Pieśń Holyrics") -> [Song] {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // A. Try JSON (Holyrics API export / JSON format)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            if let data = trimmed.data(using: .utf8) {
                if let songs = parseHolyricsJSON(data) {
                    return songs
                }
            }
        }
        
        // B. Try XML (OpenSong / OpenLyrics / Holyrics XML format)
        if trimmed.hasPrefix("<") {
            let xmlSongs = parseHolyricsXML(trimmed, fallbackTitle: fallbackTitle)
            if !xmlSongs.isEmpty {
                return xmlSongs
            }
        }
        
        // C. Check for Multi-Song delimiters in .muf / .mufl files (e.g., ---, ===, [SONG], ##)
        let multiSongBlocks = splitMultiSongMUF(trimmed)
        if multiSongBlocks.count > 1 {
            var songs: [Song] = []
            for block in multiSongBlocks {
                let parsed = parseSingleHolyricsSong(block, fallbackTitle: fallbackTitle)
                if !parsed.title.isEmpty && !parsed.rawLyrics.isEmpty {
                    songs.append(parsed)
                }
            }
            if !songs.isEmpty {
                return songs
            }
        }
        
        // D. Parse as single song with Holyrics Portuguese/English tags
        let single = parseSingleHolyricsSong(trimmed, fallbackTitle: fallbackTitle)
        return [single]
    }
    
    // MARK: - Single Song Parser (handles Holyrics metadata tags and verse markers)
    public static func parseSingleHolyricsSong(_ text: String, fallbackTitle: String) -> Song {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        
        let lines = normalized.components(separatedBy: .newlines)
        
        var title = ""
        var author = ""
        var key = ""
        var tags: [String] = ["Import Holyrics"]
        var lyricsLines: [String] = []
        var isInLyrics = false
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if isInLyrics {
                    lyricsLines.append("")
                }
                continue
            }
            
            let lower = line.lowercased()
            
            // Holyrics metadata tags: @title, @nome, @autor, @artist, @tom, @key, @order, etc.
            if lower.hasPrefix("@title:") || lower.hasPrefix("@nome:") || lower.hasPrefix("@titulo:") || lower.hasPrefix("title:") || lower.hasPrefix("título:") || lower.hasPrefix("nome:") {
                title = extractValue(from: line)
            } else if lower.hasPrefix("@author:") || lower.hasPrefix("@autor:") || lower.hasPrefix("@artist:") || lower.hasPrefix("@artista:") || lower.hasPrefix("author:") || lower.hasPrefix("autor:") || lower.hasPrefix("artist:") {
                author = extractValue(from: line)
            } else if lower.hasPrefix("@key:") || lower.hasPrefix("@tom:") || lower.hasPrefix("key:") || lower.hasPrefix("tom:") {
                key = extractValue(from: line)
            } else if lower.hasPrefix("@tags:") || lower.hasPrefix("@tag:") || lower.hasPrefix("tags:") {
                let tagList = extractValue(from: line).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                tags.append(contentsOf: tagList)
            } else if lower.hasPrefix("@ccli:") || lower.hasPrefix("@copyright:") || lower.hasPrefix("@order:") || lower.hasPrefix("@ordem:") {
                // Ignore internal Holyrics metadata properties
                continue
            } else {
                // Beginning of lyrics
                isInLyrics = true
                lyricsLines.append(rawLine)
            }
        }
        
        let finalTitle = title.isEmpty ? fallbackTitle : title
        let finalLyrics = lyricsLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedLyrics = translateHolyricsVerseMarkers(finalLyrics)
        
        return Song(
            title: finalTitle,
            author: author,
            key: key,
            tags: tags,
            rawLyrics: translatedLyrics
        )
    }
    
    private static func extractValue(from line: String) -> String {
        guard let colonIdx = line.firstIndex(of: ":") else { return "" }
        let nextIdx = line.index(after: colonIdx)
        return String(line[nextIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Multi-Song MUF splitter
    private static func splitMultiSongMUF(_ text: String) -> [String] {
        let delimiterPatterns = [
            "\n===\n",
            "\n===\r\n",
            "\n---song---\n",
            "\n[SONG]\n",
            "\n[MUSIC]\n",
            "\n{SONG}\n"
        ]
        
        for pattern in delimiterPatterns {
            if text.contains(pattern) {
                return text.components(separatedBy: pattern)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        
        return [text]
    }
    
    // MARK: - JSON Parser (Holyrics JSON export)
    private static func parseHolyricsJSON(_ data: Data) -> [Song]? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        
        var songDicts: [[String: Any]] = []
        if let array = jsonObject as? [[String: Any]] {
            songDicts = array
        } else if let dict = jsonObject as? [String: Any] {
            if let list = dict["songs"] as? [[String: Any]] {
                songDicts = list
            } else if let list = dict["musics"] as? [[String: Any]] {
                songDicts = list
            } else if let list = dict["items"] as? [[String: Any]] {
                songDicts = list
            } else {
                songDicts = [dict]
            }
        }
        
        guard !songDicts.isEmpty else { return nil }
        
        var results: [Song] = []
        for dict in songDicts {
            let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? (dict["nome"] as? String) ?? (dict["titulo"] as? String) ?? ""
            let author = (dict["author"] as? String) ?? (dict["artist"] as? String) ?? (dict["artista"] as? String) ?? (dict["autor"] as? String) ?? ""
            let key = (dict["key"] as? String) ?? (dict["tone"] as? String) ?? (dict["tom"] as? String) ?? ""
            
            var lyrics = (dict["lyrics"] as? String) ?? (dict["letra"] as? String) ?? (dict["text"] as? String) ?? ""
            if lyrics.isEmpty, let slidesArray = dict["slides"] as? [String] {
                lyrics = slidesArray.joined(separator: "\n\n")
            } else if lyrics.isEmpty, let paragraphs = dict["paragraphs"] as? [[String: Any]] {
                let texts = paragraphs.compactMap { $0["text"] as? String }
                lyrics = texts.joined(separator: "\n\n")
            }
            
            if !title.isEmpty || !lyrics.isEmpty {
                let cleaned = translateHolyricsVerseMarkers(lyrics)
                results.append(Song(
                    title: title.isEmpty ? "Bez tytułu" : title,
                    author: author,
                    key: key,
                    tags: ["Import Holyrics JSON"],
                    rawLyrics: cleaned
                ))
            }
        }
        
        return results.isEmpty ? nil : results
    }
    
    // MARK: - XML Parser (OpenSong / OpenLyrics / Holyrics XML format)
    /// Prawdziwy parser XML zamiast wyrażeń regularnych: encje (`&amp;`) i CDATA są dekodowane (N5).
    private static func parseHolyricsXML(_ xmlString: String, fallbackTitle: String) -> [Song] {
        HolyricsXMLReader.records(in: xmlString).compactMap { fields in
            let title = fields["title"] ?? ""
            let lyrics = fields["lyrics"] ?? ""
            guard !title.isEmpty || !lyrics.isEmpty else { return nil }
            return Song(
                title: title.isEmpty ? fallbackTitle : title,
                author: fields["author"] ?? "",
                key: fields["key"] ?? "",
                tags: ["Import Holyrics XML"],
                rawLyrics: translateHolyricsVerseMarkers(lyrics)
            )
        }
    }
    
    // MARK: - Archive (.zip / .hly) extraction
    private static func importFromArchive(at url: URL) -> [Song]? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("holyrics_import_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempDir.path]
        // `waitUntilExit` na procesie, który się nie uruchomił, zatrzymuje aplikację (N5).
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        
        var importedSongs: [Song] = []
        if let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "muf" || ext == "mufl" || ext == "txt" || ext == "json" || ext == "xml" {
                    importedSongs.append(contentsOf: importFromURL(fileURL))
                }
            }
        }
        
        return importedSongs.isEmpty ? nil : importedSongs
    }
}

// MARK: - Holyrics XML Reader

/// Czyta pieśni z XML Holyrics / OpenSong: elementy `song`/`music` z polami (także po portugalsku).
/// Bez elementu pieśni pola z całego dokumentu tworzą jedną pieśń.
final class HolyricsXMLReader: NSObject, XMLParserDelegate {
    private static let songElements: Set<String> = ["song", "music", "musica"]
    private static let fieldAliases: [String: String] = [
        "title": "title", "nome": "title", "titulo": "title",
        "author": "author", "artist": "author", "autor": "author", "artista": "author",
        "key": "key", "tom": "key", "tone": "key",
        "lyrics": "lyrics", "letra": "lyrics"
    ]
    
    private var records: [[String: String]] = []
    private var current: [String: String]?
    private var documentFields: [String: String] = [:]
    private var field: String?
    private var text = ""
    
    static func records(in xml: String) -> [[String: String]] {
        let reader = HolyricsXMLReader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        parser.parse()
        if reader.records.isEmpty, !reader.documentFields.isEmpty {
            return [reader.documentFields]
        }
        return reader.records
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = elementName.lowercased()
        if Self.songElements.contains(name) {
            current = [:]
        } else if let alias = Self.fieldAliases[name] {
            field = alias
            text = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if field != nil { text += String(decoding: CDATABlock, as: UTF8.self) }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        if let alias = Self.fieldAliases[name], alias == field {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != nil {
                if current?[alias]?.isEmpty ?? true { current?[alias] = value }
            } else if documentFields[alias]?.isEmpty ?? true {
                documentFields[alias] = value
            }
            field = nil
        } else if Self.songElements.contains(name), let record = current {
            records.append(record)
            current = nil
        }
    }
}
