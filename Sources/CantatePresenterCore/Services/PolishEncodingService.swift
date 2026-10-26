import Foundation

public final class PolishEncodingService: Sendable {
    public static let shared = PolishEncodingService()
    
    // Polish diacritic characters
    private static let polishDiacritics = Set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
    
    // Common Mojibake sequences resulting from UTF-8 interpreted as Windows-1252 / ISO-8859-1
    private static let mojibakeReplacements: [(String, String)] = [
        ("Ã³", "ó"), ("Ã“", "Ó"),
        ("Å‚", "ł"), ("Å\u{0081}", "Ł"), ("Å\u{009A}", "Ś"),
        ("Å›", "ś"), ("Åš", "Ś"),
        ("Å¼", "ż"), ("Å»", "Ż"),
        ("Åº", "ź"), ("Å¹", "Ź"),
        ("Ä™", "ę"), ("Ä\u{0098}", "Ę"), ("Ä˜", "Ę"),
        ("Ä…", "ą"), ("Ä„", "Ą"),
        ("Ä‡", "ć"), ("Ä†", "Ć"),
        ("Å„", "ń"), ("Åƒ", "Ń"),
        // Bajty Windows-1250 odczytane jako ISO-8859-1 dają znaki sterujące C1, których nie ma w prawdziwym
        // tekście. Drukowalne odpowiedniki (ñ, ¿, ê, æ, £, ¹, ³ …) to zwykłe litery innych języków
        // i nie są zamieniane (R2-02): „Señor” zostaje „Señor”.
        ("\u{009C}", "ś"), ("\u{008C}", "Ś"),
        ("\u{009F}", "ź"), ("\u{008F}", "Ź"),
        // Curly quotes and typographic dashes from Windows CP1250
        ("\u{0096}", "–"), ("\u{0097}", "—"),
        ("\u{0091}", "‘"), ("\u{0092}", "’"),
        ("\u{0093}", "“"), ("\u{0094}", "”"),
        ("â€ž", "„"), ("â€\u{009D}", "”"), ("â€“", "–"), ("â€”", "—")
    ]
    
    // Comprehensive dictionary of common Polish words in hymns/liturgy where ASCII letters should have diacritics
    private static let knownReligiousWordReplacements: [String: String] = [
        "badz": "Bądź",
        "bog": "Bóg",
        "boga": "Boga",
        "bogu": "Bogu",
        "bogiem": "Bogiem",
        "boze": "Boże",
        "blogoslaw": "Błogosław",
        "blogoslawcie": "Błogosławcie",
        "blogoslawiony": "Błogosławiony",
        "blogoslawieni": "Błogosławieni",
        "blogoslawiona": "Błogosławiona",
        "blogoslawione": "Błogosławione",
        "milosierni": "miłosierni",
        "milosierdzia": "miłosierdzia",
        "milosierdzie": "miłosierdzie",
        "milosc": "miłość",
        "milosci": "miłości",
        "krolowa": "Królowa",
        "krolowo": "Królowo",
        "krolowej": "Królowej",
        "krolowi": "Królowi",
        "krol": "Król",
        "krola": "Króla",
        "krolem": "Królem",
        "swiety": "Święty",
        "swieta": "Święta",
        "swiete": "Święte",
        "swieci": "Święci",
        "swietego": "Świętego",
        "swietym": "Świętym",
        "spiewaj": "Śpiewaj",
        "spiewajcie": "Śpiewajcie",
        "spiewajmy": "Śpiewajmy",
        "spiew": "Śpiew",
        "spiewam": "Śpiewam",
        "piesn": "Pieśń",
        "piesni": "Pieśni",
        "tys": "Tyś",
        "jestes": "Jesteś",
        "moj": "mój",
        "twoj": "Twój",
        "twoja": "Twoja",
        "twoje": "Twoje",
        "zlobie": "żłobie",
        "zlobka": "żłobka",
        "zlobku": "żłobku",
        "wsrod": "wśród",
        "coz": "Cóż",
        "chocby": "choćby",
        "duszo": "duszo",
        "dusza": "dusza",
        "duszy": "duszy",
        "zycie": "życie",
        "zycia": "życia",
        "zyje": "żyje",
        "zrodlo": "źródło",
        "zrodle": "źródle",
        "wez": "weź",
        "pojdz": "pójdź",
        "pojdmy": "pójdźmy",
        "przyjdz": "przyjdź",
        "przyjdzcie": "przyjdźcie",
        "wstan": "wstań",
        "wstancie": "wstańcie",
        "krzyz": "krzyż",
        "krzyza": "krzyża",
        "krzyzu": "krzyżu",
        "pokoj": "pokój",
        "pokoju": "pokoju",
        "zwyciezca": "zwycięzca",
        "smierc": "śmierć",
        "smierci": "śmierci",
        "gore": "Gore",
        "gwiazda": "gwiazda",
        "gwiazdo": "gwiazdo",
        "zmiluj": "zmiłuj",
        "ufnosc": "ufność",
        "ufnoscia": "ufnością",
        "otworz": "otwórz",
        "otworzcie": "otwórzcie",
        "wznosze": "wznoszę",
        "przejrzal": "przejrzał",
        "kochal": "kochał",
        "slonce": "słońce",
        "slonca": "słońca",
        "dzieciatko": "Dzieciątko",
        "dzieciatku": "Dzieciątku",
        "dzieciateczko": "Dzieciąteczko",
        "placz": "płacz",
        "aniol": "Anioł",
        "aniolowie": "Aniołowie",
        "lud": "lud",
        "ludem": "ludem",
        "ludzie": "ludzie",
        "ludziom": "ludziom"
    ]
    
    /// Detects and repairs Mojibake encoding artifacts in text
    public func repairMojibake(_ text: String) -> String {
        var repaired = text
        for (mojibake, correct) in PolishEncodingService.mojibakeReplacements {
            if repaired.contains(mojibake) {
                repaired = repaired.replacingOccurrences(of: mojibake, with: correct)
            }
        }
        return repaired
    }
    
    /// Checks if a text string contains genuine Polish diacritics
    public func hasPolishDiacritics(_ text: String) -> Bool {
        return text.contains { PolishEncodingService.polishDiacritics.contains($0) }
    }
    
    /// Contextually restores Polish diacritics in title by cross-referencing words with its lyrics and dictionary
    public func restoreTitleDiacritics(title: String, lyrics: String) -> (title: String, wasRestored: Bool) {
        let fixedTitle = repairMojibake(title.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // If title already has Polish characters, return as is (with mojibake fixed)
        if hasPolishDiacritics(fixedTitle) {
            return (fixedTitle, fixedTitle != title)
        }
        
        let lyricsRepaired = repairMojibake(lyrics)
        let lyricsHasDiacritics = hasPolishDiacritics(lyricsRepaired)
        
        // Słowa z tekstu z polskimi literami. Słowo, które w tekście ma kilka postaci („droga” i „drogą”),
        // nie jest zmieniane, bo nie wiadomo, o którą chodzi (R2-05).
        let lyricsWords = lyricsRepaired.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        var lyricsForms: [String: Set<String>] = [:]
        for lw in lyricsWords {
            lyricsForms[Song.foldString(lw), default: []].insert(lw.lowercased())
        }
        var lyricsWordMap: [String: String] = [:]
        if lyricsHasDiacritics {
            for (folded, forms) in lyricsForms where forms.count == 1 {
                if let form = forms.first, hasPolishDiacritics(form) {
                    lyricsWordMap[folded] = form
                }
            }
        }
        
        // Tokenize title preserving punctuation
        var changed = false
        var titleWords = fixedTitle.components(separatedBy: " ")
        for i in 0..<titleWords.count {
            let rawWord = titleWords[i]
            // Extract core letters and trailing punctuation (e.g. "Ciebie," -> core "Ciebie", punct ",")
            let letters = rawWord.filter { $0.isLetter }
            let trailingPunct = rawWord.filter { !$0.isLetter }
            guard !letters.isEmpty else { continue }
            
            let folded = Song.foldString(letters)
            // Tekst ma też dokładnie tę postać bez polskich liter: zostawiamy tytuł.
            if lyricsForms[folded]?.contains(letters.lowercased()) == true { continue }

            var replacementWord: String? = nil
            // 1. Try lyrics match
            if let matchedFromLyrics = lyricsWordMap[folded] {
                replacementWord = matchedFromLyrics
            }
            // 2. Try known religious vocabulary
            else if let matchedFromDict = PolishEncodingService.knownReligiousWordReplacements[folded] {
                replacementWord = matchedFromDict
            }
            
            if let repl = replacementWord {
                // Preserve original casing style (TitleCase, UPPERCASE, or lowercase)
                var styledRepl = repl
                if letters == letters.uppercased() {
                    styledRepl = repl.uppercased()
                } else if letters.first?.isUppercase == true {
                    styledRepl = repl.prefix(1).uppercased() + repl.dropFirst().lowercased()
                } else {
                    styledRepl = repl.lowercased()
                }
                
                let finalWord = styledRepl + trailingPunct
                if finalWord != rawWord {
                    titleWords[i] = finalWord
                    changed = true
                }
            }
        }
        
        let result = titleWords.joined(separator: " ")
        return (result, changed || result != title)
    }
    
    /// Normalizes lyrics ensuring Mojibake is repaired and Polish quotes/dashes are cleanly formatted
    public func cleanLyrics(_ lyrics: String) -> String {
        var cleaned = repairMojibake(lyrics)
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
        return cleaned
    }
}
