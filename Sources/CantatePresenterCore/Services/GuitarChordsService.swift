import Foundation

public struct GuitarChordResult: Identifiable, Equatable {
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

public final class GuitarChordsService {
    public static let shared = GuitarChordsService()
    
    // Scale for transposition
    private static let chromaticScaleSharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
    private static let chromaticScaleFlats  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "B", "H"]
    
    // Curated offline chords database for most popular Polish worship hymns
    private var curatedChords: [String: GuitarChordResult] = [:]
    
    public init() {
        populateCuratedChords()
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
    
    /// Searches chords for a song: checks curated database first, then queries online sources
    public func searchChords(for songTitle: String, artist: String? = nil, queryHint: String? = nil) async -> [GuitarChordResult] {
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
        
        // 3. Query online guitar chord repositories
        let webResults = await searchOnlineChords(title: cleanTitle, artist: artist ?? "")
        for wr in webResults {
            if !results.contains(where: { $0.title.lowercased() == wr.title.lowercased() }) {
                results.append(wr)
            }
        }
        
        return results
    }
    
    /// Extracts chords from raw lyrics text, returning both cleaned lyrics (for projection) and extracted chords sheet (for musicians)
    public func extractChordsAndCleanLyrics(_ raw: String) -> (cleanLyrics: String, extractedChords: String?) {
        let lines = raw.components(separatedBy: .newlines)
        var cleanLines: [String] = []
        var chordSheetLines: [String] = []
        var foundAnyChords = false
        
        // Regex for standalone chord line (e.g. "C   G   a   F" or "e H7 C D")
        let chordLineRegex = try? NSRegularExpression(pattern: #"^\s*([A-Ha-h][#b]?(?:m|maj|min|dim|sus|add)?[0-9]?(?:/[A-Ha-h][#b]?)?(\s+|$))+$"#, options: [])
        // Regex for inline chords in parens like (CG) or (a e)
        let inlineParensChordRegex = try? NSRegularExpression(pattern: #"\(([A-Ha-h0-9#b\s/]{1,8})\)"#, options: [])
        // Regex for inline chords in brackets like [C] or [G]
        let inlineBracketsChordRegex = try? NSRegularExpression(pattern: #"\[([A-Ha-h0-9#b/]{1,6})\]"#, options: [])
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            
            // Check if entire line is just chords
            if let regex = chordLineRegex, regex.firstMatch(in: line, options: [], range: range) != nil && !trimmed.isEmpty {
                foundAnyChords = true
                chordSheetLines.append(line)
                continue // don't add chord-only line to audience projection
            }
            
            var cleanedLine = line
            
            // Check for inline chords in brackets [C]
            if let bRegex = inlineBracketsChordRegex, bRegex.firstMatch(in: cleanedLine, options: [], range: NSRange(location: 0, length: (cleanedLine as NSString).length)) != nil {
                foundAnyChords = true
                chordSheetLines.append(cleanedLine)
                // Remove bracketed chords for audience projection
                cleanedLine = bRegex.stringByReplacingMatches(in: cleanedLine, options: [], range: NSRange(location: 0, length: (cleanedLine as NSString).length), withTemplate: "")
            }
            // Check for inline chords in parens at end of line like "Pan kiedyś stanął nad brzegiem (D A)"
            else if let pRegex = inlineParensChordRegex, pRegex.firstMatch(in: cleanedLine, options: [], range: NSRange(location: 0, length: (cleanedLine as NSString).length)) != nil {
                foundAnyChords = true
                chordSheetLines.append(cleanedLine)
                cleanedLine = pRegex.stringByReplacingMatches(in: cleanedLine, options: [], range: NSRange(location: 0, length: (cleanedLine as NSString).length), withTemplate: "")
            } else {
                chordSheetLines.append(cleanedLine)
            }
            
            cleanLines.append(cleanedLine)
        }
        
        let finalCleanLyrics = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalChords = foundAnyChords ? chordSheetLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (finalCleanLyrics, finalChords)
    }
    
    /// Transposes chords in a chord sheet by given number of semitones (-11 to +11)
    public func transpose(chordsSheet: String, semitones: Int) -> String {
        guard semitones != 0 else { return chordsSheet }
        
        // Normalize semitones to 0...11
        let shift = (semitones % 12 + 12) % 12
        
        let chordRegex = try? NSRegularExpression(pattern: #"\b([A-H][#b]?)(m|maj|min|dim|sus|add)?([0-9]?)(?:/([A-H][#b]?))?\b"#, options: [])
        guard let regex = chordRegex else { return chordsSheet }
        
        func transposeRoot(_ root: String) -> String {
            let isLower = (root == root.lowercased())
            let upper = root.uppercased()
            
            let scale = GuitarChordsService.chromaticScaleSharps
            guard let idx = scale.firstIndex(of: upper) else { return root }
            let newIdx = (idx + shift) % 12
            let transposed = scale[newIdx]
            return isLower ? transposed.lowercased() : transposed
        }
        
        let lines = chordsSheet.components(separatedBy: .newlines)
        var transposedLines: [String] = []
        
        for line in lines {
            let ns = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty {
                transposedLines.append(line)
                continue
            }
            
            var lineResult = line
            // Process matches in reverse order so character offsets don't invalidate
            for m in matches.reversed() {
                let fullChord = ns.substring(with: m.range)
                let rootRange = m.range(at: 1)
                guard rootRange.location != NSNotFound else { continue }
                
                let rootStr = ns.substring(with: rootRange)
                let newRoot = transposeRoot(rootStr)
                
                var newChord = newRoot
                let modRange = m.range(at: 2)
                if modRange.location != NSNotFound {
                    newChord += ns.substring(with: modRange)
                }
                let numRange = m.range(at: 3)
                if numRange.location != NSNotFound {
                    newChord += ns.substring(with: numRange)
                }
                let bassRange = m.range(at: 4)
                if bassRange.location != NSNotFound {
                    let bassStr = ns.substring(with: bassRange)
                    newChord += "/" + transposeRoot(bassStr)
                }
                
                if let r = Range(m.range, in: lineResult) {
                    lineResult.replaceSubrange(r, with: newChord)
                }
            }
            transposedLines.append(lineResult)
        }
        
        return transposedLines.joined(separator: "\n")
    }
    
    // MARK: - Online Chords Scraper
    private func searchOnlineChords(title: String, artist: String) async -> [GuitarChordResult] {
        let query = "\(title) \(artist) chwyty gitarowe akordy"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 7.0
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            
            let snippetPattern = "<a class=\"result__snippet\"[^>]*>(.*?)</a>"
            let titlePattern = "<a class=\"result__url\"[^>]*>(.*?)</a>"
            
            guard let sRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators]),
                  let tRegex = try? NSRegularExpression(pattern: titlePattern, options: [.dotMatchesLineSeparators]) else { return [] }
            
            let ns = html as NSString
            let sMatches = sRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            let tMatches = tRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            
            var list: [GuitarChordResult] = []
            let count = min(sMatches.count, tMatches.count, 4)
            
            for i in 0..<count {
                let rawSnippet = ns.substring(with: sMatches[i].range(at: 1))
                let rawSource = ns.substring(with: tMatches[i].range(at: 1))
                
                let cleanSnippet = rawSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#x27;", with: "'")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let cleanSource = rawSource.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if snippet contains chord symbols
                if cleanSnippet.contains("C") || cleanSnippet.contains("G") || cleanSnippet.contains("D") || cleanSnippet.contains("a") || cleanSnippet.contains("e") {
                    list.append(GuitarChordResult(
                        title: title,
                        artist: artist.isEmpty ? "Pieśń religijna" : artist,
                        key: "Oryginalna",
                        chordsSheet: cleanSnippet,
                        source: cleanSource.isEmpty ? "Internetowy śpiewnik chwytów" : cleanSource
                    ))
                }
            }
            return list
        } catch {
            return []
        }
    }
    
    // MARK: - Populate Curated Chords for Top Polish Hymns
    private func populateCuratedChords() {
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
    }
}
