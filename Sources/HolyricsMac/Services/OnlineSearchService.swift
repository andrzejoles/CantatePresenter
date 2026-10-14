import Foundation

public final class OnlineSearchService {
    public static let shared = OnlineSearchService()
    
    // Curated offline religious song catalog for instant reliable search & fallback
    private let curatedPolishHymns: [OnlineSearchResult] = [
        OnlineSearchResult(
            title: "Dotknij Panie moich oczu",
            artist: "Pieśń uwielbienia",
            snippet: "Dotknij, Panie, moich oczu, abym przejrzał. Dotknij, Panie, mego serca...",
            lyrics: """
            [Zwrotka 1]
            Dotknij, Panie, moich oczu, abym przejrzał,
            Dotknij, Panie, mego serca, abym kochał,
            Dotknij, Panie, moich warg, abym wielbił Imię Twe,
            Dotknij, Panie, mego życia, Twoim chcę być.

            [Refren]
            Jezu, Jezu, dotknij mnie,
            Jezu, Jezu, ulecz mnie,
            Twoją mocą napełnij mnie!

            [Zwrotka 2]
            Weź me ręce, uczyń z nich narzędzie Twe,
            Weź me stopy, niechaj głoszą słowo Twe.
            Moje serce uczyń czystym na Twój chwalebny dzień,
            Bym na wieki z Tobą śpiewał w niebie pieśń!
            """,
            source: "Śpiewnik Kościelny"
        ),
        OnlineSearchResult(
            title: "Przyjdź Duchu Święty (Veni Sancte Spiritus)",
            artist: "Pieśń do Ducha Świętego",
            snippet: "Przyjdź, Duchu Święty, ja pragnę, o przyjdź, to jest Twój czas...",
            lyrics: """
            [Zwrotka 1]
            Przyjdź, Duchu Święty, ja pragnę,
            O, przyjdź, to jest Twój czas!
            Przyjdź, Duchu Święty, ja pragnę,
            O, przyjdź i rozpal nas!

            [Refren]
            Rozpal ogień w sercu mym,
            Niech Twój powiew dotknie mnie!
            Duchu Boży, przyjdź w swej mocy,
            Odnowić ziemię tę!

            [Zwrotka 2]
            Spuść na nas deszcz Swojej łaski,
            Oczyść nas ze wszystkich win.
            Daj nam poznać miłość Ojca,
            Którą w darze przyniósł Syn!
            """,
            source: "Śpiewnik Oazowy"
        ),
        OnlineSearchResult(
            title: "Zmartwychwstał Pan i żyje dziś",
            artist: "Pieśń wielkanocna / Uwielbienie",
            snippet: "Zmartwychwstał Pan i żyje dziś, blask Jego chwały świeci w nas...",
            lyrics: """
            [Zwrotka 1]
            Zmartwychwstał Pan i żyje dziś!
            Blask Jego chwały świeci w krąg!
            Zwyciężył śmierć, rozkruszył grzech,
            Wypuścił więźniów z czarnych rąk!

            [Refren]
            Alleluja, Jezus żyje!
            Alleluja, On jest Król!
            Śpiewaj ziemio, pieśń niech bije,
            Zniknął lęk i zniknął ból!

            [Zwrotka 2]
            Nie szukaj wśród umarłych Go,
            Bo grób jest pusty, wolny świat!
            Duch Życia wstał, pokonał zło,
            Zmartwychwstania nadszedł czas!
            """,
            source: "Pieśni Wielkanocne"
        ),
        OnlineSearchResult(
            title: "Twoja łaska jest lepsza niż życie",
            artist: "Pieśń uwielbienia",
            snippet: "Twoja łaska jest lepsza niż życie, Twoja łaska jest lepsza niż życie...",
            lyrics: """
            [Zwrotka 1]
            Twoja łaska jest lepsza niż życie,
            Twoja łaska jest lepsza niż życie.
            Moje usta będą Cię chwalić,
            Będę błogosławił Cię przez całe życie me.

            [Refren]
            Wznoszę ręce w Imię Twe,
            Wznoszę ręce w Imię Twe!
            Moje usta będą Cię chwalić,
            Będę błogosławił Cię przez całe życie me!
            """,
            source: "Wspólnota Uwielbienia"
        ),
        OnlineSearchResult(
            title: "Jesteś Królem",
            artist: "Współczesne Uwielbienie",
            snippet: "Jesteś Królem, jesteś Królem, Królem jest Bóg...",
            lyrics: """
            [Zwrotka 1]
            Jesteś Królem, jesteś Królem,
            Królem jest Bóg!
            Podnieśmy nasze ręce,
            Oddajmy Mu cześć!
            Przed tronem stańmy chwały,
            Wywyższajmy Go!

            [Refren]
            Bo Panem naszym jest,
            Bo Królem naszym jest!
            Święty, Święty, Pan Zastępów,
            Pełna jest ziemia chwały Twej!
            """,
            source: "Wspólnota Uwielbienia"
        ),
        OnlineSearchResult(
            title: "Panie mój przychodzę dziś",
            artist: "Geoff Bullock (tłum. polskie)",
            snippet: "Panie mój, przychodzę dziś, serce me obmyj z win...",
            lyrics: """
            [Zwrotka 1]
            Panie mój, przychodzę dziś,
            Serce me obmyj z win,
            Twoją łaską napełnij je!
            Wiem, że w Tobie siła jest,
            By zwyciężyć wszelki grzech,
            W Twej miłości zanurzyć się!

            [Refren]
            Trzymaj mnie, Twej miłości mocą,
            Prowadź mnie, tak blisko Siebie bądź!
            Jak orzeł wzbiję się,
            Ponad chmurami będę biegł,
            Gdy Twój Duch podniesie mnie!

            [Zwrotka 2]
            Otwórz oczy serca mego,
            Chcę oglądać Twoją twarz,
            Twoją wolę w mym życiu znać!
            Odnawiaj myśli moje wciąż,
            Niechaj staję się jak Ty,
            W obecności Twej każdego dnia!
            """,
            source: "Hillsong / Współczesne"
        ),
        OnlineSearchResult(
            title: "Nic nie musisz mówić nic",
            artist: "Pieśń zaufania",
            snippet: "Nic nie musisz mówić nic, odpocznij we Mnie...",
            lyrics: """
            [Zwrotka 1]
            Nic nie musisz mówić nic,
            Odpocznij we Mnie.
            Czuję każdy twój ból,
            Znam każde twe drżenie.

            [Refren]
            Zaufaj Mi, zaufaj Mi,
            Jam jest twój Bóg!
            Zaufaj Mi, zaufaj Mi,
            Nie lękaj się niczego już!

            [Zwrotka 2]
            Moje ramiona otwarte są,
            Moje serce kocha cię.
            Choćby opuścił cię cały świat,
            Ja nigdy nie opuszczę cię.
            """,
            source: "Pieśni Oazowe"
        ),
        OnlineSearchResult(
            title: "Czarna Madonno",
            artist: "Pieśń Maryjna",
            snippet: "Jest zakątek na tej ziemi, gdzie powracać każdy chce...",
            lyrics: """
            [Zwrotka 1]
            Jest zakątek na tej ziemi,
            Gdzie powracać każdy chce,
            Gdzie króluje Jej Oblicze,
            Na Nim cięte rysy dwie.
            Wzrok ma smutny, zatroskany,
            Jakby chciała prosić cię,
            Byś w matczyną Jej opiekę
            Oddał całe życie swe.

            [Refren]
            Madonno, Czarna Madonno,
            Jak dobrze Twym dzieckiem być!
            O, pozwól, Czarna Madonno,
            W ramionach Twoich się skryć!

            [Zwrotka 2]
            W Jej ramionach znajdziesz spokój
            I uchronisz się od zła,
            Bo dla wszystkich Swoich dzieci
            Ona serce czułe ma.
            I opieką cię otoczy,
            Gdy w wędrówce stracisz siły,
            Ona modli się za nami,
            Byśmy w niebie z Bogiem żyli.
            """,
            source: "Pieśni Maryjne"
        ),
        OnlineSearchResult(
            title: "Pan jest pasterzem moim",
            artist: "Psalm 23",
            snippet: "Pan jest pasterzem moim, niczego mi nie braknie...",
            lyrics: """
            [Zwrotka 1]
            Pan jest pasterzem moim,
            Niczego mi nie braknie,
            Na zielonych niwach pasie mnie,
            Nad wody spokojne mnie prowadzi.

            [Refren]
            Orzeźwia moją duszę,
            Ścieżkami prawdy wiedzie mnie,
            Dla Imienia Swego,
            Na wieki wieków, Amen!

            [Zwrotka 2]
            Chociażbym chodził ciemną doliną,
            Zła się nie ulęknę,
            Bo Ty jesteś ze mną,
            Laska Twoja i kij Twój mnie pocieszają!
            """,
            source: "Psalmy i Hymny"
        )
    ]
    
    /// Searches online lyrics services and returns matching results
    public func search(query: String, language: String = "pl") async -> [OnlineSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        var results: [OnlineSearchResult] = []
        
        // 1. Search in curated catalog first (instant, guaranteed quality)
        let foldedQuery = Song.foldString(clean)
        for song in curatedPolishHymns {
            let titleFolded = Song.foldString(song.title)
            let lyricsFolded = Song.foldString(song.lyrics)
            if titleFolded.contains(foldedQuery) || lyricsFolded.contains(foldedQuery) {
                results.append(song)
            }
        }
        
        // 2. Query LRCLIB API (open public lyrics API)
        let lrclibResults = await queryLRCLIB(query: clean)
        results.append(contentsOf: lrclibResults)
        
        // 3. Query Web / DuckDuckGo if needed
        if results.count < 5 {
            let webResults = await queryWebSearch(query: clean, language: language)
            results.append(contentsOf: webResults)
        }
        
        // Remove duplicates by title
        var unique: [OnlineSearchResult] = []
        var seenTitles = Set<String>()
        for r in results {
            let key = Song.foldString(r.title)
            if !seenTitles.contains(key) {
                seenTitles.insert(key)
                unique.append(r)
            }
        }
        
        return unique
    }
    
    private func queryLRCLIB(query: String) async -> [OnlineSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("HolyricsMac/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            
            var results: [OnlineSearchResult] = []
            for item in jsonArray.prefix(8) {
                guard let track = item["trackName"] as? String,
                      let artist = item["artistName"] as? String else { continue }
                
                let plainLyrics = item["plainLyrics"] as? String ?? ""
                guard !plainLyrics.isEmpty else { continue }
                
                let snippet = plainLyrics.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .joined(separator: " / ")
                
                results.append(OnlineSearchResult(
                    title: track,
                    artist: artist,
                    snippet: snippet,
                    lyrics: plainLyrics,
                    source: "LRCLIB Database"
                ))
            }
            return results
        } catch {
            return []
        }
    }
    
    private func queryWebSearch(query: String, language: String) async -> [OnlineSearchResult] {
        let suffix = (language == "pl") ? " tekst pieśni religijnej" : " christian song lyrics"
        let fullQuery = query + suffix
        guard let encoded = fullQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 7.0
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            
            // Extract snippets and titles
            let snippetPattern = "<a class=\"result__snippet\"[^>]*>(.*?)</a>"
            let titlePattern = "<a class=\"result__url\"[^>]*>(.*?)</a>"
            
            let sRegex = try NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators])
            let tRegex = try NSRegularExpression(pattern: titlePattern, options: [.dotMatchesLineSeparators])
            
            let nsHtml = html as NSString
            let sMatches = sRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
            let tMatches = tRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
            
            var list: [OnlineSearchResult] = []
            let count = min(sMatches.count, tMatches.count, 4)
            for i in 0..<count {
                let sRaw = nsHtml.substring(with: sMatches[i].range(at: 1))
                let tRaw = nsHtml.substring(with: tMatches[i].range(at: 1))
                
                let cleanSnippet = sRaw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#x27;", with: "'")
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let cleanTitle = tRaw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanSnippet.isEmpty {
                    list.append(OnlineSearchResult(
                        title: query.capitalized,
                        artist: cleanTitle,
                        snippet: cleanSnippet,
                        lyrics: cleanSnippet,
                        source: "Sieć internetowa"
                    ))
                }
            }
            return list
        } catch {
            return []
        }
    }
}
