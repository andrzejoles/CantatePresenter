import Foundation
import AppKit
import os

public struct SongExporter {
    /// Linia oddzielająca tekst od arkusza chwytów w eksporcie .txt (format danych, nie tłumaczony).
    public static let chordsSectionMarker = "--- Chwyty ---"
    
    /// Eksport do folderu przerwany błędem: część plików już zapisano (R2-09).
    public struct PartialExportError: LocalizedError {
        public let written: Int
        public let total: Int
        public let underlying: Error
        
        public var errorDescription: String? {
            Lnow("Zapisano {0} z {1} plików. Błąd: {2}", written, total, underlying.localizedDescription)
        }
    }
    
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "export")
    
    /// Converts a Song to cleanly formatted text file content.
    /// Nagłówek i sekcja chwytów wracają przy imporcie (`TextImporter.parseString`, R2-21).
    public static func songToText(_ song: Song) -> String {
        func oneLine(_ text: String) -> String {
            text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        var content = ""
        content += "Tytuł: \(oneLine(song.title))\n"
        if !song.author.isEmpty {
            content += "Autor: \(oneLine(song.author))\n"
        }
        if !song.key.isEmpty {
            content += "Tonacja: \(song.key)\n"
        }
        if !song.tags.isEmpty {
            content += "Tagi: \(song.tags.joined(separator: ", "))\n"
        }
        if let ccli = song.ccliNumber, !ccli.isEmpty {
            content += "CCLI: \(oneLine(ccli))\n"
        }
        if let copyright = song.copyright, !copyright.isEmpty {
            content += "Copyright: \(oneLine(copyright))\n"
        }
        if let source = song.source, !source.isEmpty {
            content += "Źródło: \(oneLine(source))\n"
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
        if song.hasChords, let chords = song.chords {
            content += "\n\n\(chordsSectionMarker)\n\(chords.trimmingCharacters(in: .whitespacesAndNewlines))"
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
                reportFailure(error, file: url)
                return false
            }
        }
        return false
    }
    
    /// Exports all or selected songs to a single JSON backup file
    @MainActor
    public static func exportSongsAsJSONFile(_ songs: [Song], defaultName: String = "Baza_piesni") -> Bool {
        guard let data = songsToJSONData(songs) else {
            reportFailure(CocoaError(.fileWriteUnknown), file: nil)
            return false
        }
        
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
                reportFailure(error, file: url)
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
            reportFailure(error, file: folderURL)
            return 0
        }
    }
    
    /// Błąd eksportu: wpis w dzienniku i komunikat (wcześniej eksport na pełny dysk „udawał się” po cichu).
    @MainActor
    private static func reportFailure(_ error: Error, file: URL?) {
        logger.error("Eksport nie powiódł się (\(file?.path ?? "-", privacy: .public)): \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = Lnow("Eksport nie powiódł się")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    /// Zapisuje każdą pieśń jako osobny plik .txt. Powtórzone tytuły dostają sufiks „ (2)”, „ (3)”
    /// (porównanie bez wielkości liter, jak w APFS), więc żadna pieśń nie nadpisuje innej (S4).
    /// Zwraca liczbę faktycznie zapisanych plików; błąd zapisu przerywa eksport (`PartialExportError`
    /// z liczbą plików zapisanych wcześniej).
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
            do {
                try songToText(song).write(to: folderURL.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            } catch {
                throw PartialExportError(written: written, total: songs.count, underlying: error)
            }
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
