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
    
    /// Reads raw songs from any Holyrics file without deduplication (for batch processing)
    public static func readRawSongs(from url: URL) -> [Song] {
        readSongs(from: url).songs
    }
    
    /// Pieśni z pliku Holyrics albo archiwum razem z problemami (uszkodzony plik, błąd rozpakowania).
    public static func readSongs(from url: URL) -> ImportOutcome {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        
        // 1. ZIP package. .hly/.holyrics bywają też zwykłym plikiem tekstowym; jako tekst idą tylko bez
        // sygnatury ZIP, bo uszkodzone archiwum dawało jedną „pieśń” z bajtów ZIP bez ostrzeżenia (R6-02).
        if TextImporter.archiveExtensions.contains(ext), ext == "zip" || ZipArchive.hasSignature(url) {
            return importFromArchive(at: url)
        }
        
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: error.localizedDescription)])
        }
        
        // 2. Java ObjectStream (.mufl / .muf). Uszkodzony strumień nie jest już czytany jako tekst
        // (cała biblioteka jako jedna „pieśń” z bajtów binarnych, R2-04): zostają pieśni sprzed błędu.
        if HolyricsJavaDeserializer.isJavaSerializedStream(fileData) {
            let (records, error) = HolyricsJavaDeserializer(data: fileData).deserializeMusicRecordsPartially()
            let songs = records
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { convertRawRecordToSong($0) }
            guard let error else { return ImportOutcome(songs: songs) }
            let message = songs.isEmpty
                ? Lnow("Plik Holyrics jest uszkodzony lub niepełny: {0}", error.localizedDescription)
                : Lnow("Plik Holyrics jest uszkodzony lub niepełny: {0}. Wczytano {1} pieśni sprzed miejsca błędu.", error.localizedDescription, songs.count)
            return ImportOutcome(songs: songs, problems: [ImportProblem(fileName: fileName, message: message)])
        }
        
        // 3. Text parsing (JSON, XML, or tagged TXT). Dane binarne nie są słowami pieśni (R6-02).
        guard let content = TextImporter.decodeText(fileData), !TextImporter.looksBinary(content) else {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: Lnow("Nie można odczytać pliku."))])
        }
        // JSON idzie tą samą drogą co plik .json (własny format bez strat, plan to nie pieśń, R6-06).
        if let json = TextImporter.jsonOutcomeIfJSON(content, fileName: fileName) {
            return json
        }
        let songs = parseHolyricsContent(content, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        return songs.isEmpty ? ImportOutcome(problems: [.noSongs(in: fileName)]) : ImportOutcome(songs: songs)
    }
    
    /// Imports songs from any Holyrics file (.muf, .mufl, .hly, .holyrics, .xml, .json, .txt)
    public static func importFromURL(_ url: URL) -> [Song] {
        readSongs(from: url).songs
    }
    
    /// Tekst w formacie Holyrics: znaczniki `@nome:`/`@title:` na początku albo znaczniki zwrotek `##(Verse 1)`.
    public static func looksLikeHolyricsText(_ text: String) -> Bool {
        if text.contains("##(") { return true }
        let tags = ["@title:", "@nome:", "@titulo:", "@author:", "@autor:", "@artist:", "@artista:", "@key:", "@tom:"]
        return text.split(whereSeparator: \.isNewline).prefix(5).contains { line in
            let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
            return tags.contains { lower.hasPrefix($0) }
        }
    }
    
    /// Parses string content formatted as Holyrics Music File (.muf/.mufl), JSON, XML, or tagged TXT
    public static func parseHolyricsContent(_ rawContent: String, fallbackTitle: String = "Pieśń Holyrics") -> [Song] {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // A. JSON (Holyrics API export, własny eksport): ta sama tolerancyjna droga co pliki .json (R6-06).
        // Poprawny JSON bez pieśni (np. plan) nie staje się pieśnią z tekstem JSON.
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
           let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: []) {
            return TextImporter.songs(fromJSONValue: json)
        }
        
        // B. Try XML (OpenSong / OpenLyrics / Holyrics XML format). XML bez pieśni (plist, metadane innych
        // programów) nie staje się pieśnią z surowym XML (R10-05, jak JSON w R6-06); tekst ze znacznikami
        // Holyrics zaczynający się od „<” idzie dalej.
        if trimmed.hasPrefix("<") {
            let xmlSongs = parseHolyricsXML(trimmed, fallbackTitle: fallbackTitle)
            if !xmlSongs.isEmpty || !looksLikeHolyricsText(trimmed) {
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
            
            // Znaczniki tylko przed tekstem: linia „autor: …” w środku pieśni to tekst (R2-07).
            if isInLyrics {
                lyricsLines.append(rawLine)
                continue
            }
            
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
    /// Każdy plik z archiwum idzie przez `TextImporter.importFile`, jak plik wskazany bezpośrednio:
    /// eksport do folderu, JSON i pliki SongSelect w ZIP-ie wracają bez strat (R2-07).
    private static func importFromArchive(at url: URL) -> ImportOutcome {
        let fileManager = FileManager.default
        let fileName = url.lastPathComponent
        if let size = ZipArchive.declaredUncompressedSize(of: url), size > ZipArchive.maxUncompressedSize {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: Lnow("Archiwum po rozpakowaniu zajęłoby {0}; to nie jest kopia CantatePresenter.", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))])
        }
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("holyrics_import_\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // `waitUntilExit` na procesie, który się nie uruchomił, zatrzymuje aplikację (N5).
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try process.run()
        } catch {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: error.localizedDescription)])
        }
        process.waitUntilExit()
        
        var outcome = TextImporter.importFile(tempDir, insideArchive: true)
        outcome.problems = outcome.problems.map { $0.renamed("\(fileName)/\($0.fileName)") }
        // Kod 1 = ostrzeżenia unzip (część plików rozpakowana); wyższy = błąd (R2-14).
        if process.terminationStatus != 0 {
            outcome.problems.insert(ImportProblem(fileName: fileName, message: Lnow("Archiwum rozpakowane z błędami (kod unzip: {0}); część pieśni mogła zostać pominięta.", process.terminationStatus)), at: 0)
        } else if outcome.songs.isEmpty && outcome.problems.isEmpty {
            outcome.problems.append(.noSongs(in: fileName))
        }
        return outcome
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
    /// Tekst OpenLyrics (`<verse><lines>a<br/>b</lines></verse>`): liczy się tylko treść `<lines>`,
    /// `<br/>` to nowa linia, `<verse>` to nowy slajd (R2-18).
    private var structuredLyrics = false
    private var linesDepth = 0
    
    /// Deklaracja `encoding="ISO-8859-2"` jest usuwana: tekst jest już zdekodowany i trafia do parsera jako UTF-8 (R2-18).
    private static let encodingDeclaration = try! NSRegularExpression(pattern: #"^(\s*<\?xml[^>]*?)\s+encoding\s*=\s*["'][^"']*["']"#)
    
    static func records(in xml: String) -> [[String: String]] {
        let reader = HolyricsXMLReader()
        let utf8XML = encodingDeclaration.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "$1")
        let parser = XMLParser(data: Data(utf8XML.utf8))
        parser.delegate = reader
        parser.parse()
        if reader.records.isEmpty, !reader.documentFields.isEmpty {
            return [reader.documentFields]
        }
        return reader.records
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = elementName.lowercased()
        if field == "lyrics" {
            switch name {
            case "verse":
                startStructuredLyrics()
                if !text.isEmpty && !text.hasSuffix("\n\n") { text += text.hasSuffix("\n") ? "\n" : "\n\n" }
            case "lines", "line":
                startStructuredLyrics()
                if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
                linesDepth += 1
            case "br":
                if structuredLyrics { text += "\n" }
            default:
                break
            }
            return
        }
        if Self.songElements.contains(name) {
            current = [:]
        } else if let alias = Self.fieldAliases[name] {
            field = alias
            text = ""
            structuredLyrics = false
            linesDepth = 0
        }
    }
    
    private func startStructuredLyrics() {
        guard !structuredLyrics else { return }
        structuredLyrics = true
        // Dotychczasowy tekst to tylko wcięcia między elementami.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = "" }
    }
    
    private func appendText(_ string: String) {
        guard field != nil else { return }
        if structuredLyrics {
            guard linesDepth > 0 else { return }
            // Wcięcia i końce linii w źródle XML to tylko formatowanie; linie wyznacza `<br/>`.
            text += string.components(separatedBy: .whitespacesAndNewlines).joined(separator: " ")
        } else {
            text += string
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        if field == "lyrics", name == "lines" || name == "line" {
            linesDepth = max(0, linesDepth - 1)
            return
        }
        if let alias = Self.fieldAliases[name], alias == field {
            var value = text
            if structuredLyrics {
                value = value.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                    .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != nil {
                if current?[alias]?.isEmpty ?? true { current?[alias] = value }
            } else if documentFields[alias]?.isEmpty ?? true {
                documentFields[alias] = value
            }
            field = nil
            structuredLyrics = false
        } else if Self.songElements.contains(name), let record = current {
            records.append(record)
            current = nil
        }
    }
}
