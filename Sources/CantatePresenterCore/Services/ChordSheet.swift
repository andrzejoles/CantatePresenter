import Foundation

// MARK: - Chord Line

/// Wiersz dla muzyków: akordy nad tekstem (kolumny jak w arkuszu chwytów) albo sam tekst.
public struct ChordLine: Equatable, Codable, Sendable {
    public var chords: String?
    public var text: String

    public init(chords: String? = nil, text: String) {
        self.chords = chords
        self.text = text
    }
}

// MARK: - Chord Sheet

/// Dopasowanie arkusza chwytów (cała pieśń, akordy nad tekstem) do bieżącego slajdu, dla ekranu muzyków.
///
/// Arkusz i slajdy łamią wiersze inaczej, sekcje arkusza nie muszą pokrywać się ze slajdami, a chwyty bywają
/// tylko przy pierwszej zwrotce. Dlatego:
/// 1. wiersze arkusza, których słowa są w slajdzie, to kandydaci; wybieramy najdłuższy ciągły fragment kandydatów;
/// 2. fragment bez chwytów dostaje chwyty z pierwszej sekcji tego samego rodzaju (zwrotka / refren), wiersz po wierszu;
/// 3. gdy tekst slajdu nie pasuje do arkusza (inna wersja tekstu), slajd dostaje chwyty takiej sekcji wiersz po wierszu.
/// Chwyty w nawiasie na końcu wiersza, także sklejone („(Afis)” = A fis), są przenoszone nad tekst.
public enum ChordSheet {
    struct Section: Equatable {
        var header: String?
        var lines: [ChordLine]
        var isChorus: Bool
        var hasChords: Bool { lines.contains { $0.chords != nil } }
        var lyricLines: [ChordLine] { lines.filter { !$0.text.isEmpty } }
    }

    public struct Result: Equatable, Sendable {
        public var lines: [ChordLine]
        /// Chwyty pożyczone z innej sekcji (np. zwrotki 1): jej nagłówek albo pierwszy wiersz.
        public var borrowedFrom: String?
    }

    private static let headerWords: Set<String> = ["ref", "r", "refren", "chorus", "zwrotka", "z", "verse", "bridge", "coda", "koda"]
    private static let chordAtStart = try! NSRegularExpression(
        pattern: #"^[A-Ha-h](?:is|es|s|#|b)?(?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*(?:/[A-Ha-h](?:is|es|s|#|b)?)?"#
    )
    private static let trailingGroup = try! NSRegularExpression(pattern: #"\s*\(([^()]+)\)\s*$"#)

    /// Słowa do porównania: bez znaków diakrytycznych, interpunkcji i oznaczeń sekcji („Ref.”).
    static func words(_ text: String) -> [String] {
        Song.searchFold(text).split(separator: " ").map(String.init).filter { !headerWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    static func isHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") { return true }
        return trimmed.hasSuffix(":") && trimmed.count <= 30 && !ChordTransposer.isChordLine(String(trimmed.dropLast()))
    }

    /// „Afis” → ["A", "fis"], „aF” → ["a", "F"]; nil, gdy to nie same akordy.
    static func splitConcatenatedChords(_ token: String) -> [String]? {
        var rest = token
        var chords: [String] = []
        while !rest.isEmpty {
            let range = NSRange(rest.startIndex..., in: rest)
            guard let match = chordAtStart.firstMatch(in: rest, range: range), match.range.length > 0,
                  let found = Range(match.range, in: rest) else { return nil }
            chords.append(String(rest[found]))
            rest = String(rest[found.upperBound...])
        }
        return chords.isEmpty ? nil : chords
    }

    /// Linia z samymi akordami w nawiasie, także sklejonymi: „(dgCF)” → „d g C F”.
    static func parenthesizedChordLine(_ line: String) -> String? {
        guard line.hasPrefix("("), line.hasSuffix(")"), line.count > 2 else { return nil }
        var chords: [String] = []
        for token in line.dropFirst().dropLast().split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            guard let split = splitConcatenatedChords(String(token)) else { return nil }
            chords.append(contentsOf: split)
        }
        return chords.isEmpty ? nil : chords.joined(separator: " ")
    }

    /// „leczy wszystkie choroby (E)” → akordy „E” nad tekstem bez nawiasu.
    static func trailingChords(_ line: String) -> ChordLine? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = trailingGroup.firstMatch(in: line, range: range),
              let group = Range(match.range(at: 1), in: line), let whole = Range(match.range, in: line) else { return nil }
        var chords: [String] = []
        for token in line[group].split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            guard let split = splitConcatenatedChords(String(token)) else { return nil }
            chords.append(contentsOf: split)
        }
        let text = String(line[..<whole.lowerBound]).trimmingCharacters(in: .whitespaces)
        return chords.isEmpty || text.isEmpty ? nil : ChordLine(chords: chords.joined(separator: " "), text: text)
    }

    static func sections(_ sheet: String) -> [Section] {
        var result: [Section] = []
        var current = Section(header: nil, lines: [], isChorus: false)
        var pendingChords: String?

        func finish() {
            if let chords = pendingChords {
                current.lines.append(ChordLine(chords: chords, text: ""))
                pendingChords = nil
            }
            if !current.lines.isEmpty {
                let header = (current.header ?? "").lowercased()
                let firstText = Song.searchFold(current.lines.first { !$0.text.isEmpty }?.text ?? "")
                current.isChorus = header.contains("ref") || header.contains("chorus") || firstText.hasPrefix("ref ") || firstText.hasPrefix("r ")
                result.append(current)
            }
            current = Section(header: nil, lines: [], isChorus: false)
        }

        for rawLine in sheet.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                finish()
            } else if let chords = parenthesizedChordLine(trimmed) {
                if let previous = pendingChords {
                    current.lines.append(ChordLine(chords: previous, text: ""))
                }
                pendingChords = chords
            } else if ChordTransposer.isChordLine(line) {
                if let previous = pendingChords {
                    current.lines.append(ChordLine(chords: previous, text: ""))
                }
                pendingChords = line.trimmingCharacters(in: .newlines)
            } else if isHeader(trimmed) {
                if !current.lines.isEmpty || pendingChords != nil { finish() }
                current.header = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]:"))
            } else if trimmed.contains("["), case let (chords?, lyrics) = SongSelectImporter.splitChords(trimmed) {
                current.lines.append(ChordLine(chords: chords, text: lyrics))
            } else if let inline = trailingChords(trimmed) {
                // Chwyty przy wierszu wygrywają; wcześniejsza linia samych akordów to wstęp.
                if let previous = pendingChords {
                    current.lines.append(ChordLine(chords: previous, text: ""))
                    pendingChords = nil
                }
                current.lines.append(inline)
            } else {
                current.lines.append(ChordLine(chords: pendingChords, text: trimmed))
                pendingChords = nil
            }
        }
        finish()
        return result
    }

    /// Wiersze slajdu z chwytami, transponowanymi o `semitones` względem pierwszego akordu całej pieśni.
    /// Bez arkusza albo bez chwytów: sam tekst slajdu.
    public static func lines(for slide: SongSlide, sheet: String?, semitones: Int = 0) -> Result {
        let slideLines = slide.text.components(separatedBy: "\n")
        let plain = Result(lines: slideLines.map { ChordLine(text: $0) }, borrowedFrom: nil)
        guard let sheet, !sheet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return plain }
        let all = sections(sheet)
        guard all.contains(where: \.hasChords) else { return plain }
        let slideWords = words(slide.text)
        let slideSet = Set(slideWords)
        let isChorus = slide.type == .chorus

        // Wiersze arkusza po kolei (z numerem sekcji i pozycją w niej) i kandydaci pasujący do slajdu.
        var flat: [(section: Int, position: Int, line: ChordLine)] = []
        for (sectionIndex, section) in all.enumerated() {
            for (position, line) in section.lyricLines.enumerated() {
                flat.append((sectionIndex, position, line))
            }
        }
        let candidate = flat.map { entry -> Bool in
            let lineWords = words(entry.line.text)
            guard !lineWords.isEmpty else { return false }
            return Double(lineWords.filter { slideSet.contains($0) }.count) / Double(lineWords.count) >= 0.6
        }
        var bestRun: Range<Int>?
        var start: Int?
        for index in 0...flat.count {
            if index < flat.count, candidate[index] {
                start = start ?? index
            } else if let runStart = start {
                if (index - runStart) > (bestRun?.count ?? 0) { bestRun = runStart..<index }
                start = nil
            }
        }

        var result: Result
        if let run = bestRun, coverage(of: slideWords, by: flat[run].map(\.line.text)) >= 0.5 {
            var lines = flat[run].map(\.line)
            var borrowedFrom: String?
            if !lines.contains(where: { $0.chords != nil }),
               let donor = all.first(where: { $0.hasChords && $0.isChorus == all[flat[run.lowerBound].section].isChorus }) {
                let donorLines = donor.lyricLines
                for (offset, entry) in flat[run].enumerated() where entry.position < donorLines.count {
                    lines[offset].chords = donorLines[entry.position].chords
                }
                borrowedFrom = donor.header ?? donorLines.first?.text
            }
            result = Result(lines: lines, borrowedFrom: borrowedFrom)
        } else if let donor = all.first(where: { $0.hasChords && $0.isChorus == isChorus }) ?? all.first(where: \.hasChords) {
            // Inna wersja tekstu niż w arkuszu: chwyty pierwszej sekcji tego rodzaju, wiersz po wierszu.
            let donorLines = donor.lyricLines
            let lines = slideLines.enumerated().map { index, text in
                ChordLine(chords: index < donorLines.count ? donorLines[index].chords : nil, text: text)
            }
            result = Result(lines: lines, borrowedFrom: donor.header ?? donorLines.first?.text)
        } else {
            return plain
        }

        if semitones % 12 != 0 {
            // Wszystkie linie chwytów razem z pierwszym akordem pieśni: ta sama tonacja i zapis (♯/♭) na każdym slajdzie.
            let reference = all.lazy.flatMap(\.lines).compactMap(\.chords).first ?? ""
            let indices = result.lines.indices.filter { result.lines[$0].chords != nil }
            let joined = ([reference] + indices.map { result.lines[$0].chords! }).joined(separator: "\n")
            let transposed = ChordTransposer.transpose(joined, semitones: semitones).components(separatedBy: "\n").dropFirst()
            for (index, chords) in zip(indices, transposed) {
                result.lines[index].chords = chords
            }
        }
        return result
    }

    /// Część słów slajdu obecnych we wskazanych wierszach (każde słowo liczone raz).
    static func coverage(of slideWords: [String], by lines: [String]) -> Double {
        guard !slideWords.isEmpty else { return 0 }
        var available = Dictionary(words(lines.joined(separator: " ")).map { ($0, 1) }, uniquingKeysWith: +)
        var found = 0
        for word in slideWords where (available[word] ?? 0) > 0 {
            available[word]! -= 1
            found += 1
        }
        return Double(found) / Double(slideWords.count)
    }
}
