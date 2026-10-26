import Foundation

public struct GuitarChordResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var artist: String
    public var key: String
    public var chordsSheet: String
    public var source: String
    public var url: String?
    
    public init(
        title: String,
        artist: String = "Tradycyjna / Religijna",
        key: String = "",
        chordsSheet: String,
        source: String = "Baza Chwytów Gitarowych",
        url: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.key = key
        self.chordsSheet = chordsSheet
        self.source = source
        self.url = url
    }
}

public final class GuitarChordsService: Sendable {
    public static let shared = GuitarChordsService()
    
    // Curated offline chords database for most popular Polish worship hymns
    private let curatedChords: [String: GuitarChordResult]
    
    public init() {
        curatedChords = Self.makeCuratedChords()
    }
    
    /// Returns curated chords for a song title if available in the built-in database
    public func getCuratedChords(for title: String) -> GuitarChordResult? {
        let folded = Song.foldString(title)
        if let direct = curatedChords[folded] {
            return direct
        }
        for (k, chord) in curatedChords {
            if k.contains(folded) || folded.contains(k) {
                return chord
            }
        }
        return nil
    }
    
    /// Chwyty z wbudowanej bazy: dokładny tytuł, potem tytuły zawierające zapytanie (albo w nim zawarte).
    /// Bez wyszukiwania w internecie: decyzja właściciela S9 (tylko źródła z jasną licencją), R4-12.
    public func searchChords(for songTitle: String) -> [GuitarChordResult] {
        var results: [GuitarChordResult] = []
        let cleanTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = Song.foldString(cleanTitle)
        
        // 1. Direct match in curated collection
        if let direct = curatedChords[folded] {
            results.append(direct)
        }
        
        // 2. Fuzzy match in curated collection
        for (key, chord) in curatedChords {
            if key != folded && (key.contains(folded) || folded.contains(key)) {
                if !results.contains(where: { $0.title == chord.title }) {
                    results.append(chord)
                }
            }
        }
        
        return results
    }
    
    // Kompilowane raz (N3). Inline chords in parens like (CG) or (a e), and in brackets like [C] or [G].
    private static let inlineParensChordRegex = try! NSRegularExpression(pattern: #"\(([A-Ha-h0-9#b\s/]{1,8})\)"#)
    private static let inlineBracketsChordRegex = try! NSRegularExpression(pattern: #"\[([A-Ha-h0-9#b/]{1,6})\]"#)
    
    /// Usuwa z linii dopasowania, które są chwytami: każdy wyraz to akord albo znak neutralny, co najmniej
    /// jeden akord. `[1]`, `(3)` czy `(ach)` zostają w tekście (R2-20). `nil`, gdy w linii nie ma chwytów.
    private static func removingChordMatches(of regex: NSRegularExpression, in line: String) -> String? {
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).filter { match in
            let content = ns.substring(with: match.range(at: 1))
            let tokens = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return tokens.contains { ChordTransposer.parse($0) != nil }
                && tokens.allSatisfy { ChordTransposer.parse($0) != nil || $0 == "/" }
        }
        guard !matches.isEmpty else { return nil }
        let result = NSMutableString(string: line)
        for match in matches.reversed() {
            result.replaceCharacters(in: match.range, with: "")
        }
        return result as String
    }
    
    /// Extracts chords from raw lyrics text, returning both cleaned lyrics (for projection) and extracted chords sheet (for musicians)
    public func extractChordsAndCleanLyrics(_ raw: String) -> (cleanLyrics: String, extractedChords: String?) {
        let lines = raw.components(separatedBy: .newlines)
        var cleanLines: [String] = []
        var chordSheetLines: [String] = []
        var foundAnyChords = false
        
        let inlineParensChordRegex: NSRegularExpression? = Self.inlineParensChordRegex
        let inlineBracketsChordRegex: NSRegularExpression? = Self.inlineBracketsChordRegex
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if entire line is just chords (also Fis, Es, x2, | separators)
            if !trimmed.isEmpty && ChordTransposer.isChordLine(line) {
                foundAnyChords = true
                chordSheetLines.append(line)
                continue // don't add chord-only line to audience projection
            }
            
            var cleanedLine = line
            
            // Check for inline chords in brackets [C]
            if let bRegex = inlineBracketsChordRegex, let stripped = Self.removingChordMatches(of: bRegex, in: cleanedLine) {
                foundAnyChords = true
                chordSheetLines.append(cleanedLine)
                // Remove bracketed chords for audience projection
                cleanedLine = stripped
            }
            // Check for inline chords in parens at end of line like "Pan kiedyś stanął nad brzegiem (D A)"
            else if let pRegex = inlineParensChordRegex, let stripped = Self.removingChordMatches(of: pRegex, in: cleanedLine) {
                foundAnyChords = true
                chordSheetLines.append(cleanedLine)
                cleanedLine = stripped
            } else {
                chordSheetLines.append(cleanedLine)
            }
            
            cleanLines.append(cleanedLine)
        }
        
        let finalCleanLyrics = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalChords = foundAnyChords ? chordSheetLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (finalCleanLyrics, finalChords)
    }
    
    /// Transposes chords in a chord sheet by given number of semitones (W7: see `ChordTransposer`)
    public func transpose(chordsSheet: String, semitones: Int) -> String {
        ChordTransposer.transpose(chordsSheet, semitones: semitones)
    }
    
    // MARK: - Populate Curated Chords for Top Polish Hymns
    private static func makeCuratedChords() -> [String: GuitarChordResult] {
        var curatedChords: [String: GuitarChordResult] = [:]
        func add(_ title: String, key: String, chords: String, artist: String = "Tradycyjna / Religijna") {
            let entry = GuitarChordResult(title: title, artist: artist, key: key, chordsSheet: chords, source: "Biblioteka Chwytów Holyrics")
            curatedChords[Song.foldString(title)] = entry
        }
        
        add("Barka", key: "D-dur", chords: """
        Zwrotka 1:
        D            F#m        G           A
        Pan kiedyś stanął nad brzegiem,
        D            F#m     G       A
        Szukał ludzi gotowych pójść za Nim,
        D          F#m     G            A
        By łowić serca słów Bożych Prawdą.
        
        Refren:
        G      A       D     h
        O Panie, to Ty na mnie spojrzałeś,
        e        A         D     D7
        Twoje usta dziś wyrzekły me imię.
        G         A       D        h
        Swoją barkę pozostawiam na brzegu,
        e           A          D
        Razem z Tobą nowy zacznę dziś łów.
        
        Zwrotka 2:
        D            F#m        G           A
        Jestem ubogim człowiekiem,
        D            F#m     G       A
        Moim skarbem są ręce gotowe
        D          F#m     G            A
        Do pracy z Tobą i czyste serce.
        """, artist: "Cesareo Gabarain, ks. Stanisław Szmidt SDB")
        
        add("Bóg się rodzi", key: "G-dur", chords: """
        Zwrotka 1:
        G             D    C   D  G
        Bóg się rodzi, moc truchleje,
        G              D  C D G
        Pan niebiosów obnażony!
        G             D   C  D  G
        Ogień krzepnie, blask ciemnieje,
        G           D  C  D G
        Ma granice Nieskończony.
        
        Refren:
        G      C   D      G
        A Słowo Ciałem się stało
        C     G     D      G
        I mieszkało między nami.
        """, artist: "Franciszek Karpiński (1792)")
        
        add("Cicha noc", key: "C-dur", chords: """
        C
        Cicha noc, święta noc,
        G        C
        Pokój niesie ludziom wszem,
        F                 C
        A u żłóbka Matka Święta
        F                C
        Czuwa sama, uśmiechnięta
        G               C
        Nad Dzieciątka snem,
        C       G        C
        Nad Dzieciątka snem.
        """, artist: "Joseph Mohr, Franz Xaver Gruber")
        
        add("Bądź Królową moich dni", key: "e-moll", chords: """
        e      a      h      e  a  h
        Bądź Królową moich czystych myśli,
        C      D      e      H7
        Ucz mnie kochać tak jak kocha Bóg.
        e      a      h      e  a  h
        Bądź Królową moich wszystkich kroków,
        C      D      e
        Prowadź mnie Maryjo do Swych dróg.
        """, artist: "Wspólnota Emmanuel")
        
        add("Dotknij, Panie, moich oczu", key: "d-moll", chords: """
        d            g
        Dotknij, Panie, moich oczu,
        A7           d
        Abym przejrzał.
        d            g
        Dotknij, Panie, mego serca,
        A7         d
        Abym kochał.
        
        Refren:
        g      C      F      B
        Jezu, Jezu, dotknij mnie,
        g      A7     d
        Twoją mocą napełnij mnie!
        """, artist: "Piotr Pałka / ks. Jan Twardowski")
        
        add("Błogosławieni miłosierni", key: "h-moll", chords: """
        Zwrotka:
        h            G            D        A
        Wznoszę swe oczy ku górom, skąd przyjdzie mi pomoc;
        h        G           D    A
        Pomoc od Pana, wszak On stworzył niebo i ziemię!
        
        Refren:
        h                    G
        Błogosławieni miłosierni,
        D                        A
        Albowiem oni miłosierdzia dostąpią!
        """, artist: "Jakub Blycharz (Hymn ŚDM Kraków 2016)")
        
        add("Chodź, oto jest czas", key: "D-dur", chords: """
        D                          G       D
        Chodź, oto jest czas, by wielbić Pana,
        A                          e7      G
        Chodź, oto jest czas, by oddać serce!
        D                          G       D
        Chodź, taki jaki jesteś, by wielbić,
        A                          e7      G     D
        Chodź, taki jaki jesteś przed Jego tron, chodź!
        """, artist: "Brian Doerksen")
        
        add("Abba, Ojcze", key: "C-dur", chords: """
        Zwrotka:
        C        F        C
        Ty wyzwoliłeś nas Panie
        a        d        G
        Z kajdan i samych siebie,
        C          F        C
        A Chrystus stając się bratem
        a         d       G
        Nauczył nas wołać do Ciebie:
        
        Refren:
        C     e     F     G
        Abba, Ojcze! Abba, Ojcze!
        C     a     F  G  C
        Abba, Ojcze!
        """, artist: "o. Jan Góra OP, Jacek Sykulski")
        
        add("Błogosław, duszo moja, Pana", key: "e-moll", chords: """
        e                 C
        Błogosław, duszo moja, Pana,
        G                 D
        Wszystko, co we mnie, Jego Święte Imię!
        e                 C
        On odpuszcza wszystkie twoje grzechy,
        G                 D
        On leczy wszystkie twoje choroby!
        """, artist: "Trzecia Godzina Dnia (TGD)")
        
        add("W cieniu Twoich rąk", key: "a-moll", chords: """
        a             F
        W cieniu Twoich rąk
        C             G
        Ukryj, Panie, mnie,
        a             F
        Gdy wokoło szaleje sztorm,
        d             E7
        Tyś pokojem jest!
        """, artist: "Trzecia Godzina Dnia (TGD)")
        
        add("Tak mnie skrusz", key: "d-moll", chords: """
        d          C            B
        Tak mnie skrusz, tak mnie złam,
        g          A7           d
        Tak mnie wypal, Panie, w ogniu Twym,
        d          C            B
        Byś został tylko Ty, byś został tylko Ty,
        g          A7           d
        Jezu, mój Panie i Królu!
        """, artist: "Deus Meus")
        
        add("Jezus jest tu", key: "D-dur", chords: """
        D         G           D
        Jezus jest tu, Jezus jest tu,
        A         G           D
        O, wznieśmy ręce, chwalmy Go,
        D         G           D
        Bo Jezus jest tu!
        """, artist: "Deus Meus")
        return curatedChords
    }
}
