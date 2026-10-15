import Foundation

// MARK: - Chord Transposer

/// Transpozycja arkusza akordów (W7).
///
/// - Zmieniane są tylko linie akordowe (każdy wyraz to akord albo znak pomocniczy, np. `|`, `x2`)
///   oraz akordy w `[ ]` i `( )` w liniach tekstu. Słowo „A” na początku wersu zostaje.
/// - Notacja polska/niemiecka: `H` = H, `B` = B♭; krzyżyki i bemole jako `#`/`b` albo `is`/`es`.
/// - Zapis krzyżykowy lub bemolowy według tonacji docelowej (pierwszy akord arkusza).
public enum ChordTransposer {

    // MARK: - Chord Model

    struct Chord {
        var root: Int
        var isLowercase: Bool
        var suffix: String
        var bass: Int?
        var bassIsLowercase: Bool
        /// Źródło używało zapisu `is`/`es` (np. `Fis`, `Es`).
        var usesGermanAccidentals: Bool

        var isMinor: Bool {
            isLowercase || (suffix.hasPrefix("m") && !suffix.hasPrefix("maj")) || suffix.hasPrefix("min")
        }
    }

    private static let naturalPitches: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 10, "H": 11]

    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "B", "H"]
    private static let germanSharpNames = ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "Ais", "H"]
    private static let germanFlatNames = ["C", "Des", "D", "Es", "E", "F", "Ges", "G", "As", "A", "B", "H"]

    /// Tonacje zapisywane z bemolami: F, B, Es, As, Des dur oraz d, g, c, f, b moll.
    private static let flatMajorKeys: Set<Int> = [5, 10, 3, 8, 1]
    private static let flatMinorKeys: Set<Int> = [2, 7, 0, 5, 10]

    private static let chordRegex = try! NSRegularExpression(
        pattern: #"^([A-Ha-h])(is|es|s|#|b)?((?:maj|min|dim|aug|sus|add|m|M|\+|°|ø|\d)*)(?:/([A-Ha-h])(is|es|s|#|b)?)?$"#
    )
    private static let repeatMarkerRegex = try! NSRegularExpression(pattern: #"^x?\d+x?$"#)

    // MARK: - Parsing

    static func parse(_ token: String) -> Chord? {
        let ns = token as NSString
        guard let match = chordRegex.firstMatch(in: token, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        guard let rootLetter = group(1), let root = pitch(letter: rootLetter, accidental: group(2)) else {
            return nil
        }
        var bass: Int?
        var bassIsLowercase = false
        if let bassLetter = group(4) {
            guard let value = pitch(letter: bassLetter, accidental: group(5)) else { return nil }
            bass = value
            bassIsLowercase = bassLetter == bassLetter.lowercased()
        }
        let german = [group(2), group(5)].contains { ["is", "es", "s"].contains($0 ?? "") }
        return Chord(
            root: root,
            isLowercase: rootLetter == rootLetter.lowercased(),
            suffix: group(3) ?? "",
            bass: bass,
            bassIsLowercase: bassIsLowercase,
            usesGermanAccidentals: german
        )
    }

    private static func pitch(letter: String, accidental: String?) -> Int? {
        guard let character = letter.uppercased().first, let natural = naturalPitches[character] else { return nil }
        let offset: Int
        switch accidental {
        case "#", "is": offset = 1
        // `Bb` w zapisie angielskim to po prostu B♭, tak jak polskie `B`.
        case "b" where character == "B": offset = 0
        case "b", "es", "s": offset = -1
        default: offset = 0
        }
        return (natural + offset + 12) % 12
    }

    /// Wysokość dźwięku podstawy akordu (0 = C), np. do testów.
    public static func pitch(of chord: String) -> Int? {
        parse(chord.trimmingCharacters(in: .whitespaces))?.root
    }

    /// Wyraz, który może stać w linii akordowej, ale nie jest akordem (`|`, `-`, `x2`, `(x2)`).
    private static func isNeutralToken(_ token: String) -> Bool {
        let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        if stripped.isEmpty || stripped.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
            return true
        }
        return repeatMarkerRegex.firstMatch(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length)) != nil
    }

    private static func chordToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
    }

    public static func isChordLine(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var chordCount = 0
        for token in tokens {
            if parse(chordToken(token)) != nil {
                chordCount += 1
            } else if !isNeutralToken(token) {
                return false
            }
        }
        return chordCount > 0
    }

    // MARK: - Transposition

    public static func transpose(_ sheet: String, semitones: Int) -> String {
        let shift = (semitones % 12 + 12) % 12
        guard shift != 0 else { return sheet }

        let lines = sheet.components(separatedBy: "\n")
        let chords = lines.flatMap(chordsIn)
        guard let first = chords.first else { return sheet }

        let targetKey = (first.root + shift) % 12
        let useFlats = first.isMinor ? flatMinorKeys.contains(targetKey) : flatMajorKeys.contains(targetKey)
        let german = chords.contains { $0.usesGermanAccidentals }
        let names: [String]
        switch (german, useFlats) {
        case (true, true): names = germanFlatNames
        case (true, false): names = germanSharpNames
        case (false, true): names = flatNames
        case (false, false): names = sharpNames
        }

        func render(_ chord: Chord) -> String {
            var result = names[(chord.root + shift) % 12]
            if chord.isLowercase {
                result = result.lowercased()
            }
            result += chord.suffix
            if let bass = chord.bass {
                let bassName = names[(bass + shift) % 12]
                result += "/" + (chord.bassIsLowercase ? bassName.lowercased() : bassName)
            }
            return result
        }

        return lines.map { line in
            isChordLine(line) ? transposeChordLine(line, render: render) : transposeInlineChords(line, render: render)
        }.joined(separator: "\n")
    }

    /// Akordy, które transpozycja zmieni, w kolejności występowania.
    private static func chordsIn(_ line: String) -> [Chord] {
        if isChordLine(line) {
            return line.split(whereSeparator: { $0.isWhitespace }).compactMap { parse(chordToken(String($0))) }
        }
        return inlineGroups(in: line).flatMap { group in
            group.content.split(whereSeparator: { $0.isWhitespace }).compactMap { parse(String($0)) }
        }
    }

    /// Zmienia akordy w linii akordowej, starając się zachować ich kolumny nad tekstem.
    private static func transposeChordLine(_ line: String, render: (Chord) -> String) -> String {
        var result = ""
        var column = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index].isWhitespace {
                index = line.index(after: index)
                column += 1
                continue
            }
            let tokenEnd = line[index...].firstIndex(where: { $0.isWhitespace }) ?? line.endIndex
            let token = String(line[index..<tokenEnd])
            let core = chordToken(token)
            var replacement = token
            if let chord = parse(core), let range = token.range(of: core) {
                replacement = token.replacingCharacters(in: range, with: render(chord))
            }
            // Wyraz zaczyna się w swojej kolumnie, chyba że poprzedni się wydłużył; wtedy jedna spacja odstępu.
            let padding = result.isEmpty ? column : max(column - result.count, 1)
            result += String(repeating: " ", count: padding) + replacement
            column += token.count
            index = tokenEnd
        }
        return result
    }

    private struct InlineGroup {
        let range: Range<String.Index>
        let content: String
        let open: Character
        let close: Character
    }

    /// Grupy `[...]` i `(...)`, których cała zawartość to akordy, np. `[C]`, `(D A)`; `[Refren]` się nie liczy.
    private static func inlineGroups(in line: String) -> [InlineGroup] {
        var groups: [InlineGroup] = []
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let close: Character? = character == "[" ? "]" : (character == "(" ? ")" : nil)
            if let close, let end = line[line.index(after: index)...].firstIndex(of: close) {
                let content = String(line[line.index(after: index)..<end])
                let tokens = content.split(whereSeparator: { $0.isWhitespace })
                if !tokens.isEmpty, tokens.allSatisfy({ parse(String($0)) != nil }) {
                    groups.append(InlineGroup(range: index..<line.index(after: end), content: content, open: character, close: close))
                }
                index = line.index(after: end)
            } else {
                index = line.index(after: index)
            }
        }
        return groups
    }

    private static func transposeInlineChords(_ line: String, render: (Chord) -> String) -> String {
        var result = ""
        var cursor = line.startIndex
        for group in inlineGroups(in: line) {
            let transposed = group.content
                .split(separator: " ", omittingEmptySubsequences: false)
                .map { token in parse(String(token)).map(render) ?? String(token) }
                .joined(separator: " ")
            result += line[cursor..<group.range.lowerBound] + "\(group.open)\(transposed)\(group.close)"
            cursor = group.range.upperBound
        }
        return result + line[cursor...]
    }
}
