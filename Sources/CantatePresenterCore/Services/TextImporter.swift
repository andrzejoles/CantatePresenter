import Foundation
import AppKit

/// Plik, którego nie udało się (w całości) wczytać przy imporcie; pokazywany w przeglądzie importu (R2-04).
public struct ImportProblem: Equatable, Sendable {
    public let fileName: String
    public let message: String
    
    public init(fileName: String, message: String) {
        self.fileName = fileName
        self.message = message
    }
}

/// Wynik importu: pieśni i problemy z plikami.
public struct ImportOutcome: Sendable {
    public var songs: [Song] = []
    public var problems: [ImportProblem] = []
    
    public init(songs: [Song] = [], problems: [ImportProblem] = []) {
        self.songs = songs
        self.problems = problems
    }
    
    public mutating func append(_ other: ImportOutcome) {
        songs.append(contentsOf: other.songs)
        problems.append(contentsOf: other.problems)
    }
}

public struct TextImporter {
    
    /// Rozszerzenia plików rozpoznawane przy imporcie (także w oknie wyboru plików).
    public static let supportedExtensions: [String] = ["txt", "json", "muf", "mufl", "hly", "holyrics", "xml", "zip", "usr"]
        + SongSelectImporter.chordProExtensions.sorted()
    /// Archiwa; w archiwum nie są rozpakowywane kolejne (bez rekurencji).
    static let archiveExtensions: Set<String> = ["zip", "hly", "holyrics"]
    
    /// Imports songs from a single URL (supports Holyrics .muf/.mufl/.hly, .txt, .json, .xml, or directories)
    public static func importFromURL(_ url: URL) -> [Song] {
        importFile(url).songs
    }
    
    /// Jak `importFromURL`, ale z listą plików, których nie udało się wczytać (np. uszkodzony .mufl, R2-04).
    /// Każdy plik idzie tą samą drogą, także w folderze i w archiwum ZIP (R2-07).
    public static func importFile(_ url: URL, insideArchive: Bool = false) -> ImportOutcome {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            var outcome = ImportOutcome()
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == "__MACOSX" {
                        enumerator.skipDescendants()
                        continue
                    }
                    // W archiwum tylko zwykłe pliki: dowiązanie mogłoby wskazać plik spoza archiwum (R3-08).
                    if insideArchive {
                        let kind = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard kind?.isRegularFile == true, kind?.isSymbolicLink != true else { continue }
                    }
                    if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                        outcome.append(importFile(fileURL, insideArchive: insideArchive))
                    }
                }
            }
            return outcome
        }
        
        let ext = url.pathExtension.lowercased()
        
        // 1. Archiwa i pliki Holyrics (.zip, .hly, .holyrics, .muf, .mufl, .xml)
        if archiveExtensions.contains(ext) && insideArchive {
            return ImportOutcome(problems: [ImportProblem(fileName: url.lastPathComponent, message: Lnow("Archiwum w archiwum nie jest rozpakowywane."))])
        }
        if HolyricsImporter.isHolyricsFile(url: url) || archiveExtensions.contains(ext) {
            return HolyricsImporter.readSongs(from: url)
        }
        
        // 2. JSON (własny eksport, songs.json, Holyrics i inne programy)
        if ext == "json" {
            do {
                return jsonOutcome(data: try Data(contentsOf: url), fileName: url.lastPathComponent)
            } catch {
                return ImportOutcome(problems: [ImportProblem(fileName: url.lastPathComponent, message: error.localizedDescription)])
            }
        }

        guard let text = readTextWithBestEncoding(from: url), !looksBinary(text) else {
            return ImportOutcome(problems: [ImportProblem(fileName: url.lastPathComponent, message: Lnow("Nie można odczytać pliku."))])
        }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        // 3. Pliki z CCLI SongSelect (.usr, ChordPro, tekst ze stopką „CCLI Song #”)
        if ext == "usr" {
            guard let song = SongSelectImporter.parseUSR(text) else {
                return ImportOutcome(problems: [ImportProblem(fileName: url.lastPathComponent, message: Lnow("Nie można odczytać pliku."))])
            }
            return ImportOutcome(songs: [song])
        }
        if SongSelectImporter.chordProExtensions.contains(ext) {
            return ImportOutcome(songs: [SongSelectImporter.parseChordPro(text, fallbackTitle: fallbackTitle)])
        }
        if SongSelectImporter.isSongSelectText(text), let song = SongSelectImporter.parseText(text) {
            return ImportOutcome(songs: [song])
        }
        // 4. Tekst Holyrics (@nome:, ##(Verse 1))
        if HolyricsImporter.looksLikeHolyricsText(text) {
            return ImportOutcome(songs: HolyricsImporter.parseHolyricsContent(text, fallbackTitle: fallbackTitle))
        }
        
        // 5. Zwykły plik tekstowy, także eksport „do folderu” (Tytuł:, Autor:, Tonacja:)
        let song = parseString(rawContent: text, fallbackTitle: fallbackTitle)
        return ImportOutcome(songs: song.title.isEmpty && song.rawLyrics.isEmpty ? [] : [song])
    }
    
    /// Parses raw text into a Song structure. Nagłówek (Tytuł:, Autor:, Tonacja:, Tagi:, CCLI:, Copyright:,
    /// Źródło:) jest czytany tylko przed pierwszą pustą linią, a sekcja chwytów z eksportu tekstowego
    /// (`SongExporter.chordsSectionMarker`) wraca do pola `chords` (R2-21).
    public static func parseString(rawContent: String, fallbackTitle: String = "Nowa pieśń") -> Song {
        let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
                                   .replacingOccurrences(of: "\r", with: "\n")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var lines = normalized.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            return Song(title: fallbackTitle, rawLyrics: "")
        }
        
        var chords: String?
        if let markerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == SongExporter.chordsSectionMarker }) {
            let sheet = lines[(markerIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            chords = sheet.isEmpty ? nil : sheet
            lines = Array(lines[..<markerIndex])
        }
        
        var title = fallbackTitle
        var author = ""
        var key = ""
        var tags: [String] = []
        var ccliNumber: String?
        var copyright: String?
        var source: String?
        var lyricsStartIndex = 0
        
        func value(of line: String) -> String {
            String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        
        // Nagłówek: pierwsze linie do pierwszej pustej (np. Tytuł:, Autor:, Tonacja:).
        for (i, rawLine) in lines.prefix(12).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { break }
            let lower = line.lowercased()
            
            if lower.hasPrefix("tytuł:") || lower.hasPrefix("tytul:") || lower.hasPrefix("title:") {
                title = value(of: line)
            } else if lower.hasPrefix("autor:") || lower.hasPrefix("author:") {
                author = value(of: line)
            } else if lower.hasPrefix("tonacja:") || lower.hasPrefix("klucz:") || lower.hasPrefix("key:") {
                key = value(of: line)
            } else if lower.hasPrefix("tagi:") || lower.hasPrefix("kategoria:") || lower.hasPrefix("tags:") {
                tags = value(of: line).components(separatedBy: CharacterSet(charactersIn: ",;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if lower.hasPrefix("ccli:") {
                ccliNumber = value(of: line)
            } else if lower.hasPrefix("copyright:") || lower.hasPrefix("©:") {
                copyright = value(of: line)
            } else if lower.hasPrefix("źródło:") || lower.hasPrefix("zrodlo:") || lower.hasPrefix("source:") {
                source = value(of: line)
            } else if i == 0 && !line.hasPrefix("[") && !lower.hasPrefix("1.") && !lower.hasPrefix("ref") {
                // If the very first line isn't a verse marker, it can be the title
                title = line
            } else {
                break
            }
            lyricsStartIndex = i + 1
        }
        
        let remainingLines = Array(lines.dropFirst(lyricsStartIndex))
        let lyrics = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var song = Song(
            title: title.isEmpty ? fallbackTitle : title,
            author: author,
            key: key,
            tags: tags,
            rawLyrics: lyrics,
            chords: chords
        )
        song.ccliNumber = ccliNumber.flatMap { $0.isEmpty ? nil : $0 }
        song.copyright = copyright.flatMap { $0.isEmpty ? nil : $0 }
        song.source = source.flatMap { $0.isEmpty ? nil : $0 }
        return song
    }
    
    /// Reads text file trying UTF-8 and the common Polish single-byte encodings (S6)
    public static func readTextWithBestEncoding(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeText(data)
    }
    
    /// Kodowania jednobajtowe próbowane, gdy plik nie jest poprawnym UTF-8. Kolejność rozstrzyga remisy.
    /// Windows-1252 (zachodnioeuropejskie) jest po środkowoeuropejskich: wygrywa tylko przy wyraźnych
    /// oznakach tekstu hiszpańskiego itp., np. „ñ” przed samogłoską (R2-18). Windows-1251 (cyrylica, np. starsze
    /// pliki ukraińskie) jest ostatnie: wygrywa tylko tekst z samych słów cyrylicą (R6-12).
    private static let singleByteCandidates: [String.Encoding] = [
        CFStringEncodings.windowsLatin2, .isoLatin2, .macCentralEurRoman
    ].map { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding($0.rawValue))) }
        + [.windowsCP1252, .macOSRoman, .windowsCP1251]
    
    private static let polishLetters = Set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
    /// Znaki typowe dla złego kodowania polskiego tekstu, np. ISO-8859-2 czytane jako Windows-1250 („ą” → „±”, „ś” → „¶”)
    /// albo Windows-1250 czytane jako Windows-1252 („ł” → „³”, „ą” → „¹”, „ś” → „œ”).
    private static let suspiciousCharacters = Set("±¶¼¦¬ˇ˘˝˙¤§¨®°µ·¸ŠšŤťŽľĽĹĺŕŔřŘůŮ∂∑∏√∞≈≠≤≥◊ﬁﬂ¹³œŒŸ¥")
    private static let vowels = Set("aeiouyóAEIOUYÓáéíú")
    
    /// Dekoduje tekst: BOM UTF-16, UTF-8, a jeśli to niemożliwe, to kodowanie jednobajtowe z najlepszym wynikiem
    /// (najwięcej polskich liter, najmniej znaków podejrzanych i sterujących). Wcześniej Windows-1250
    /// prawie zawsze „się udawało”, więc ISO-8859-2 nie było nigdy próbowane.
    public static func decodeText(_ data: Data) -> String? {
        // Notatnik „Unicode” zapisuje UTF-16 z BOM (R2-18).
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            let littleEndian = data.starts(with: [0xFF, 0xFE])
            if let text = String(data: data.dropFirst(2), encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian) {
                return PolishEncodingService.shared.repairMojibake(text)
            }
        }
        if var utf8 = String(data: data, encoding: .utf8) {
            if utf8.hasPrefix("\u{FEFF}") {
                utf8.removeFirst()
            }
            return PolishEncodingService.shared.repairMojibake(utf8)
        }
        
        func isCyrillic(_ character: Character) -> Bool {
            character.unicodeScalars.first.map { (0x0400...0x04FF).contains($0.value) } ?? false
        }
        
        func score(_ text: String) -> Int {
            var result = 0
            var previous: Character?
            for character in text {
                if polishLetters.contains(character) || isCyrillic(character) {
                    result += 2
                } else if suspiciousCharacters.contains(character) {
                    result -= 3
                } else if let scalar = character.unicodeScalars.first,
                          scalar.properties.generalCategory == .control,
                          !"\n\r\t".unicodeScalars.contains(scalar) {
                    result -= 5
                }
                // Po polsku „ń” nie stoi przed samogłoską, a „ż” nie poprzedza wielkiej litery;
                // tak wygląda hiszpańskie „ñ”/„¿” odczytane jako Windows-1250 („Seńor”, „żQuién”).
                if let previous {
                    if "ńŃ".contains(previous) && vowels.contains(character) {
                        result -= 6
                    } else if "żŻ".contains(previous) && character.isUppercase {
                        result -= 6
                    } else if previous.isLetter && character.isLetter && isCyrillic(previous) != isCyrillic(character) {
                        // Litery łacińskie i cyrylica w jednym słowie: polski tekst odczytany jako Windows-1251
                        // („Zażółć” → „Zaїулж”) albo odwrotnie (R6-12).
                        result -= 6
                    }
                }
                previous = character
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
    
    /// Pieśni z JSON: własny format (tablica, pojedyncza pieśń, obiekt z listą `songs`/`items`/…) oraz JSON
    /// innych programów (Holyrics: `name`/`nome`, `lyrics`/`letra`/`text`, `slides`, `paragraphs`).
    /// Obiekt bez tytułu i tekstu (plan, ustawienia, manifest kopii) nie jest pieśnią (R2-03): wcześniej
    /// tolerancyjny dekoder `Song` przyjmował każdy obiekt jako pustą pieśń.
    public static func decodeSongsFromJSON(data: Data) -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        return songs(fromJSONValue: json)
    }

    /// Jak `decodeSongsFromJSON`, ale nieczytelny JSON i JSON bez pieśni są problemami importu (R6-05).
    static func jsonOutcome(data: Data, fileName: String) -> ImportOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: Lnow("Nie można odczytać pliku."))])
        }
        let songs = songs(fromJSONValue: json)
        guard !songs.isEmpty else {
            return ImportOutcome(problems: [ImportProblem(fileName: fileName, message: Lnow("Nie znaleziono pieśni"))])
        }
        return ImportOutcome(songs: songs)
    }

    /// Tekst, który jest poprawnym JSON-em (obiekt albo tablica), jako wynik importu JSON; `nil`, gdy to nie JSON (R6-06).
    static func jsonOutcomeIfJSON(_ text: String, fileName: String) -> ImportOutcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        let data = Data(trimmed.utf8)
        guard (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else { return nil }
        return jsonOutcome(data: data, fileName: fileName)
    }

    /// Znaki sterujące poza końcami linii i tabulatorami: w tekście pieśni ich nie ma, w danych binarnych
    /// (np. ucięte archiwum odczytane jako Windows-1250) jest ich dużo (R6-02).
    static func looksBinary(_ text: String) -> Bool {
        let allowed = "\n\r\t\u{0B}\u{0C}".unicodeScalars
        var total = 0
        var controls = 0
        for scalar in text.unicodeScalars {
            total += 1
            if scalar.properties.generalCategory == .control, !allowed.contains(scalar) {
                controls += 1
            }
        }
        return controls > max(2, total / 50)
    }

    private static let wrapperKeys = ["songs", "items", "piesni", "library", "musics"]

    static func songs(fromJSONValue value: Any) -> [Song] {
        if let array = value as? [Any] {
            return array.compactMap { ($0 as? [String: Any]).flatMap(song(fromJSONObject:)) }
        }
        guard let object = value as? [String: Any] else { return [] }
        for key in wrapperKeys {
            if let list = object[key] as? [Any] {
                let songs = songs(fromJSONValue: list)
                if !songs.isEmpty { return songs }
            }
        }
        return song(fromJSONObject: object).map { [$0] } ?? []
    }
    
    /// Dekoder dat jak w `songs.json` (liczba sekund od 2001 r.) i ISO 8601 z eksportu.
    private static let flexibleDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            if let text = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter().date(from: text) { return date }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: text) { return date }
                }
            }
            return Date()
        }
        return decoder
    }()
    
    private static func song(fromJSONObject object: [String: Any]) -> Song? {
        func string(_ keys: String...) -> String? {
            for key in keys {
                if let value = object[key] as? String { return value }
            }
            return nil
        }
        // Własny format (eksport JSON, songs.json): pełny dekoder `Song` z chwytami, CCLI, © i źródłem.
        if object["rawLyrics"] is String || object["slides"] is [[String: Any]] {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  var song = try? flexibleDecoder.decode(Song.self, from: data) else { return nil }
            let hasTitle = !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasLyrics = !song.rawLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !song.slides.isEmpty
            guard hasTitle || hasLyrics else { return nil }
            if !hasTitle { song.title = Lnow("Bez tytułu") }
            return song
        }
        
        var lyrics = string("lyrics", "letra", "text", "tekst") ?? ""
        if lyrics.isEmpty, let slides = object["slides"] as? [String] {
            lyrics = slides.joined(separator: "\n\n")
        } else if lyrics.isEmpty, let paragraphs = object["paragraphs"] as? [[String: Any]] {
            lyrics = paragraphs.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        }
        lyrics = HolyricsImporter.translateHolyricsVerseMarkers(lyrics).trimmingCharacters(in: .whitespacesAndNewlines)
        // Bez tekstu to nie pieśń, tylko np. plan albo własny język (mają `name`).
        guard !lyrics.isEmpty else { return nil }
        
        let title = string("title", "tytul", "tytuł", "name", "nome", "titulo")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = (object["tags"] as? [String]) ?? (object["tagi"] as? [String]) ?? []
        var song = Song(
            title: title.isEmpty ? Lnow("Bez tytułu") : title,
            author: string("author", "autor", "artist", "artista") ?? "",
            key: string("key", "tonacja", "tone", "tom") ?? "",
            tags: tags,
            rawLyrics: lyrics,
            chords: string("chords")
        )
        song.copyright = string("copyright")
        song.source = string("source")
        if let ccli = string("ccliNumber", "ccli") {
            song.ccliNumber = ccli
        } else if let number = (object["ccliNumber"] ?? object["ccli"]) as? Int {
            song.ccliNumber = String(number)
        }
        return song
    }
}
