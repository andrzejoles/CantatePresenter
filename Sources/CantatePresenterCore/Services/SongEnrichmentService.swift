import Foundation

public struct CanonicalSongData: Sendable {
    public let canonicalTitle: String
    public let canonicalAuthor: String
    public let tags: [String]
    public let keyPhrases: [String]
    
    public init(canonicalTitle: String, canonicalAuthor: String, tags: [String] = [], keyPhrases: [String] = []) {
        self.canonicalTitle = canonicalTitle
        self.canonicalAuthor = canonicalAuthor
        self.tags = tags
        self.keyPhrases = keyPhrases
    }
}

public final class SongEnrichmentService: Sendable {
    public static let shared = SongEnrichmentService()
    
    private let database: [String: CanonicalSongData]
    
    public init() {
        database = Self.makeDatabase()
    }
    
    /// Checks if an author string is essentially placeholder or empty
    public static func isUnknownAuthor(_ author: String) -> Bool {
        let clean = Song.foldString(author)
        return clean.isEmpty ||
               clean == "autor nieznany" ||
               clean == "nieznany" ||
               clean == "brak" ||
               clean == "tradycyjna" ||
               clean == "nn" ||
               clean == "various" ||
               clean == "-"
    }
    
    /// Normalizes title with diacritics and clean casing
    public func canonicalizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = Song.foldString(trimmed)
        if let canonical = database[folded] {
            return canonical.canonicalTitle
        }
        
        // Fix common diacritic omissions and formatting
        var fixed = trimmed
        let titleFixes: [(String, String)] = [
            ("badz krolowa", "Bądź Królową"),
            ("blogoslawieni milosierni", "Błogosławieni miłosierni"),
            ("boze moj boze szukam ciebie", "Boże mój, Boże, szukam Ciebie"),
            ("gore gwazda jezusowi", "Gore gwiazda Jezusowi"),
            ("magnificat", "Magnificat"),
            ("jubilate deo", "Jubilate Deo"),
            ("cantate domino", "Cantate Domino"),
            ("bonum est confidere", "Bonum est confidere"),
            ("bless the lord", "Bless the Lord"),
            ("christe salvator", "Christe Salvator"),
            ("chryste twoj duch", "Chryste, Twój Duch"),
            ("gloria gloria in excelsis deo", "Gloria, gloria in excelsis Deo"),
            ("gloria in excelsis deo", "Gloria in excelsis Deo"),
            ("surrexit christus", "Surrexit Christus"),
            ("in manus tuas pater", "In manus tuas, Pater"),
            ("misericordias domini", "Misericordias Domini"),
            ("nada te turbe", "Nada te turbe"),
            ("ubi caritas", "Ubi Caritas"),
            ("laudate dominum", "Laudate Dominum"),
            ("laudate omnes gentes", "Laudate omnes gentes"),
            ("sanctum nomen domini", "Sanctum Nomen Domini"),
            ("ostende nobis", "Ostende nobis"),
            ("veni creator spiritus", "Veni Creator Spiritus"),
            ("veni sancte spiritus", "Veni Sancte Spiritus"),
            ("adeste fideles", "Adeste Fideles"),
            ("panie twoj tron", "Panie, Twój tron"),
            ("chce wywyzszac imie twe", "Chcę wywyższać Imię Twe"),
            ("chodz oto jest czas", "Chodź, oto jest czas"),
            ("gdy wpatruje sie", "Gdy wpatruję się w Twą Świętą Twarz"),
            ("jezus najwyzsze imie", "Jezus, Najwyższe Imię"),
            ("z dawna polski tys krolowa", "Z dawna Polski Tyś Królową")
        ]
        
        for (pattern, replacement) in titleFixes {
            if folded == pattern || folded.hasPrefix(pattern + " ") {
                fixed = replacement
                break
            }
        }
        
        // If title is ALL CAPS, convert to Title Case
        if fixed == fixed.uppercased() && fixed.count > 3 {
            fixed = fixed.capitalized
        }
        
        return fixed
    }
    
    /// Enriches a song with canonical author, Polish diacritics, and guitar chords
    public func enrich(song: Song) -> (enrichedSong: Song, wasEnriched: Bool, details: String) {
        var updated = song
        var changes: [String] = []
        
        // 0. Repair Mojibake & Normalize Polish characters in Title and Lyrics
        let cleanLyrics = PolishEncodingService.shared.cleanLyrics(song.rawLyrics)
        let cleanTitle = PolishEncodingService.shared.repairMojibake(song.title)
        
        if cleanLyrics != song.rawLyrics {
            updated.rawLyrics = cleanLyrics
            changes.append("Poprawiono kodowanie znaków")
        }
        
        // 0b. Chords extraction from lyrics (if chords were embedded in text)
        if updated.chords == nil || updated.chords?.isEmpty == true {
            let (extractedLyrics, foundChords) = GuitarChordsService.shared.extractChordsAndCleanLyrics(updated.rawLyrics)
            if let chords = foundChords {
                updated.chords = chords
                updated.rawLyrics = extractedLyrics
                changes.append("Wyodrębniono chwyty gitarowe")
            }
        }
        
        // Contextual title diacritics restoration from lyrics
        let (diacriticsTitle, titleWasRestored) = PolishEncodingService.shared.restoreTitleDiacritics(title: cleanTitle, lyrics: updated.rawLyrics)
        if titleWasRestored && diacriticsTitle != updated.title {
            changes.append("Przywrócono polskie litery: \"\(diacriticsTitle)\"")
            updated.title = diacriticsTitle
        }
        
        let foldedTitle = Song.foldString(updated.title)
        let needsAuthor = SongEnrichmentService.isUnknownAuthor(song.author)
        
        // 1. Direct title lookup in database
        if let entry = database[foldedTitle] {
            if updated.title != entry.canonicalTitle {
                changes.append("Tytuł: \"\(updated.title)\" ➔ \"\(entry.canonicalTitle)\"")
                updated.title = entry.canonicalTitle
            }
            if needsAuthor && !entry.canonicalAuthor.isEmpty {
                changes.append("Autor: \"\(entry.canonicalAuthor)\"")
                updated.author = entry.canonicalAuthor
            }
            for tag in entry.tags {
                if !updated.tags.contains(tag) {
                    updated.tags.append(tag)
                }
            }
        } else {
            // 2. Lyrics keyphrase lookup
            let foldedLyrics = Song.foldString(updated.rawLyrics)
            var matchedByLyrics = false
            
            for (_, entry) in database {
                for phrase in entry.keyPhrases {
                    let foldedPhrase = Song.foldString(phrase)
                    if !foldedPhrase.isEmpty && foldedLyrics.contains(foldedPhrase) {
                        if needsAuthor && !entry.canonicalAuthor.isEmpty {
                            changes.append("Autor (na podst. tekstu): \"\(entry.canonicalAuthor)\"")
                            updated.author = entry.canonicalAuthor
                        }
                        for tag in entry.tags {
                            if !updated.tags.contains(tag) {
                                updated.tags.append(tag)
                            }
                        }
                        matchedByLyrics = true
                        break
                    }
                }
                if matchedByLyrics { break }
            }
            
            // 3. Fallback title fixes (diacritics, casing)
            let fixedTitle = canonicalizeTitle(updated.title)
            if fixedTitle != updated.title {
                changes.append("Poprawiono pisownię tytułu: \"\(fixedTitle)\"")
                updated.title = fixedTitle
            }
        }
        
        // 4. Attach chords from curated chords repository if not already set
        if updated.chords == nil || updated.chords?.isEmpty == true {
            let foldedFinalTitle = Song.foldString(updated.title)
            if let curated = GuitarChordsService.shared.getCuratedChords(for: foldedFinalTitle) {
                updated.chords = curated.chordsSheet
                if updated.key.isEmpty && !curated.key.isEmpty {
                    updated.key = curated.key
                }
                changes.append("Dołączono chwyty gitarowe (\(curated.key))")
            }
        }
        
        let wasEnriched = !changes.isEmpty
        let details = changes.joined(separator: ", ")
        return (updated, wasEnriched, details)
    }
    
    // MARK: - Populate Comprehensive Hymnal & Worship Database
    private static func makeDatabase() -> [String: CanonicalSongData] {
        var database: [String: CanonicalSongData] = [:]
        func add(_ title: String, _ author: String, tags: [String] = [], phrases: [String] = []) {
            let key = Song.foldString(title)
            database[key] = CanonicalSongData(canonicalTitle: title, canonicalAuthor: author, tags: tags, keyPhrases: phrases)
        }
        
        // Polish Carols & Pastorals (Kolędy i Pastorałki)
        add("Bóg się rodzi", "Franciszek Karpiński (1792)", tags: ["Kolęda", "Tradycyjna"], phrases: ["Bóg się rodzi moc truchleje", "Podnieś rękę Boże Dziecię"])
        add("Bracia, patrzcie jeno", "Franciszek Karpiński", tags: ["Kolęda"], phrases: ["Bracia patrzcie jeno jak niebo goreje"])
        add("Ach ubogi żłobie", "Piotr Artomiusz (XVII w.)", tags: ["Kolęda"], phrases: ["Ach ubogi żłobie cóż ja widzę w tobie"])
        add("Cicha noc", "sł. Joseph Mohr, muz. Franz Xaver Gruber, sł. pol. Piotr Maszyński", tags: ["Kolęda"], phrases: ["Cicha noc święta noc", "pokój niesie ludziom wszem"])
        add("Gdy się Chrystus rodzi", "tradycyjna kolęda polska (XVII w.) / ks. M. Mioduszewski", tags: ["Kolęda"], phrases: ["Gdy się Chrystus rodzi i na świat przychodzi", "Gloria in excelsis Deo"])
        add("Gdy śliczna Panna", "tradycyjna kolęda polska (XVIII w.)", tags: ["Kolęda"], phrases: ["Gdy śliczna Panna Syna kołysała", "Lili lili laj"])
        add("Dzisiaj w Betlejem", "tradycyjna kolęda polska (XIX w.)", tags: ["Kolęda"], phrases: ["Dzisiaj w Betlejem wesoła nowina", "Chrystus się rodzi nas oswobodzi"])
        add("Lulajże, Jezuniu", "tradycyjna kolęda polska (XVII w.)", tags: ["Kolęda"], phrases: ["Lulajże Jezuniu moja perełko", "Lulajże Jezuniu lulajże lulaj"])
        add("Wśród nocnej ciszy", "ks. Michał Marcin Mioduszewski (1843)", tags: ["Kolęda"], phrases: ["Wśród nocnej ciszy głos się rozchodzi", "Wstańcie pasterze Bóg się wam rodzi"])
        add("Pójdźmy wszyscy do stajenki", "tradycyjna kolęda polska (XVIII w.)", tags: ["Kolęda"], phrases: ["Pójdźmy wszyscy do stajenki", "Powitajmy Maleńkiego"])
        add("Przybieżeli do Betlejem", "tradycyjna kolęda polska (XVII w.) / Jan Żabczyc", tags: ["Kolęda"], phrases: ["Przybieżeli do Betlejem pasterze", "Chwała na wysokości"])
        add("Anioł pasterzom mówił", "tradycyjna kolęda polska (XVI w.)", tags: ["Kolęda"], phrases: ["Anioł pasterzom mówił Chrystus się wam narodził"])
        add("Mędrcy świata, monarchowie", "ks. Stefan Bareła (sł.), Zygmunt Piasecki (muz.)", tags: ["Kolęda"], phrases: ["Mędrcy świata monarchowie gdzie spiesznie dążycie"])
        add("Gore gwiazda Jezusowi", "tradycyjna pastorałka polska (XVIII w.)", tags: ["Pastorałka"], phrases: ["Gore gwiazda Jezusowi w obłoku"])
        add("Jezus malusieńki", "tradycyjna kolęda polska (XVII w.)", tags: ["Kolęda"], phrases: ["Jezus malusieńki leży wśród stajenki"])
        add("W żłobie leży", "Piotr Skarga SJ (przypisywana)", tags: ["Kolęda"], phrases: ["W żłobie leży któż pobieży kolędować Małemu"])
        add("Nie było miejsca dla Ciebie", "o. Mateusz Jeż SJ (sł.), o. Józef Łaś SJ (muz.)", tags: ["Kolęda"], phrases: ["Nie było miejsca dla Ciebie w Betlejem"])
        add("Tryumfy Króla niebieskiego", "tradycyjna kolęda polska (XVIII w.)", tags: ["Kolęda"], phrases: ["Tryumfy Króla niebieskiego zstąpiły z nieba wysokiego"])
        add("Mizerna cicha", "Teofil Lenartowicz (sł.), Jan Gall (muz.)", tags: ["Kolęda"], phrases: ["Mizerna cicha stajenka licha"])
        add("Z narodzenia Pana", "tradycyjna kolęda polska", tags: ["Kolęda"], phrases: ["Z narodzenia Pana dzień dziś wesoły"])
        add("Nowy Rok bieży", "tradycyjna kolęda polska", tags: ["Kolęda"], phrases: ["Nowy Rok bieży w jasełkach leży"])
        add("Pasterze mili", "tradycyjna pastorałka polska", tags: ["Pastorałka"], phrases: ["Pasterze mili coście widzieli"])

        // Classical & Liturgical Hymns
        add("Barka", "Cesareo Gabarain, tłum. ks. Stanisław Szmidt SDB", tags: ["Oazowa", "ŚDM"], phrases: ["Pan kiedyś stanął nad brzegiem", "O Panie to Ty na mnie spojrzałeś", "Moim skarbem są ręce gotowe"])
        add("Abba, Ojcze", "o. Jan Góra OP (sł.), Jacek Sykulski (muz.) - ŚDM 1991", tags: ["ŚDM", "Uwielbienie"], phrases: ["Ty wyzwoliłeś nas Panie z kajdan", "Abba Ojcze"])
        add("Błogosławieni miłosierni", "Jakub Blycharz (Hymn ŚDM Kraków 2016)", tags: ["ŚDM"], phrases: ["Błogosławieni miłosierni albowiem oni miłosierdzia dostąpią", "Wznoszę swe oczy ku górom"])
        add("Ciebie, Boga, wysławiamy (Te Deum)", "św. Ambroży / ks. Józef Siedlecki", tags: ["Liturgiczna", "Tradycyjna"], phrases: ["Ciebie Boga wysławiamy Tobie Panu wieczna cześć", "Święty Święty Święty Pan Bóg Zastępów"])
        add("Kiedy ranne wstają zorze", "Franciszek Karpiński (1792)", tags: ["Tradycyjna", "Poranna"], phrases: ["Kiedy ranne wstają zorze Tobie ziemia Tobie morze"])
        add("Wszystkie nasze dzienne sprawy", "Franciszek Karpiński (1792)", tags: ["Tradycyjna", "Wieczorna"], phrases: ["Wszystkie nasze dzienne sprawy przyjm na ofiarę"])
        add("Czarna Madonna", "Jan Patho (sł.), o. W. Kapeć (muz.)", tags: ["Maryjna"], phrases: ["Jest zakątek na tej ziemi gdzie powracać każdy chce", "Madonno Czarna Madonno"])
        add("Z dawna Polski Tyś Królową", "ks. Jan Siedlecki (1878)", tags: ["Maryjna", "Tradycyjna"], phrases: ["Z dawna Polski Tyś Królową Maryjo"])
        add("Apel Jasnogórski", "ks. Stanisław Ormiński SDB", tags: ["Maryjna"], phrases: ["Maryjo Królowo Polski jestem przy Tobie pamiętam"])
        add("Bądź Królową moich dni", "Wspólnota Emmanuel", tags: ["Maryjna", "Uwielbienie"], phrases: ["Bądź Królową moich dni", "Prowadź mnie Maryjo"])
        add("Chrystus Pan karmi nas", "ks. Józef Siedlecki", tags: ["Eucharystyczna"], phrases: ["Chrystus Pan karmi nas swoim świętym Ciałem", "Chwalcie o Panie"])
        add("Chlebie najcichszy", "ks. Kazimierz Szymonik", tags: ["Eucharystyczna"], phrases: ["Przemień mnie w siebie", "Chlebie najcichszy otul mnie swym milczeniem"])
        add("Jeden chleb, co krzepi serca", "ks. Józef Siedlecki / Didache", tags: ["Eucharystyczna"], phrases: ["Jeden chleb co krzepi serca marne", "Jak ten chleb co złączył złote ziarna"])
        add("O Panie, Ty nam dajesz", "ks. Józef Siedlecki", tags: ["Eucharystyczna"], phrases: ["O Panie Ty nam dajesz Ciało swe i Krew"])
        add("Panie, dobry jak chleb", "bł. ks. Jerzy Popiełuszko / ks. J. Siedlecki", tags: ["Eucharystyczna"], phrases: ["Panie dobry jak chleb użycz Twego ducha"])
        add("Zbliżam się w pokorze (Adoro te devote)", "św. Tomasz z Akwinu", tags: ["Eucharystyczna"], phrases: ["Zbliżam się w pokorze i niskości swej", "Bo bóstwo Twe całe ukryte"])
        add("Kłaniam się Tobie", "ks. Józef Siedlecki", tags: ["Eucharystyczna"], phrases: ["Kłaniam się Tobie Przedwieczny Boże"])
        add("Ludu, mój ludu", "ks. Józef Siedlecki / Improperia", tags: ["Wielki Post"], phrases: ["Ludu mój ludu cóżem ci uczynił"])
        add("W krzyżu cierpienie", "ks. Karol Antoniewicz", tags: ["Wielki Post"], phrases: ["W krzyżu cierpienie w krzyżu zbawienie"])
        add("Któryś za nas cierpiał rany", "tradycyjna pieśń pasyjna", tags: ["Wielki Post"], phrases: ["Któryś za nas cierpiał rany Jezu Chryste"])
        add("Rozmyślajmy dziś, wierni chrześcijanie", "tradycyjna pieśń pasyjna (XVI w.)", tags: ["Wielki Post"], phrases: ["Rozmyślajmy dziś wierni chrześcijanie"])
        add("Zwycięzca śmierci", "tradycyjna pieśń wielkanocna (XVII w.)", tags: ["Wielkanoc"], phrases: ["Zwycięzca śmierci piekła i szatana", "Wychodzi z grobu"])
        add("Otrzyjcie łzy, płaczący", "tradycyjna pieśń wielkanocna (XVII w.)", tags: ["Wielkanoc"], phrases: ["Otrzyjcie łzy płaczący żałość z serca wyzujcie"])
        add("Wesoły nam dzień dziś nastał", "tradycyjna pieśń wielkanocna (XIV w.)", tags: ["Wielkanoc"], phrases: ["Wesoły nam dzień dziś nastał którego z nas każdy żądał"])
        add("Chrystus zmartwychwstan jest", "najstarsza polska pieśń wielkanocna (XIV w.)", tags: ["Wielkanoc"], phrases: ["Chrystus zmartwychwstan jest nam na przykład dan jest"])

        // Liturgical Music Workshop (Paweł Bębenek & Piotr Pałka)
        add("Błogosławcie Pana", "Paweł Bębenek", tags: ["Uwielbienie", "Liturgiczna"], phrases: ["Błogosławcie Pana wszystkie Jego dzieła", "Błogosławcie Pana aniołowie Pańscy"])
        add("Gdzie miłość wzajemna i dobroć (Ubi Caritas)", "Paweł Bębenek", tags: ["Liturgiczna"], phrases: ["Gdzie miłość wzajemna i dobroć tam znajdziesz Boga żywego"])
        add("Dzięki Ci Panie za Ciało Twe i Krew", "Paweł Bębenek", tags: ["Eucharystyczna"], phrases: ["Dzięki Ci Panie za Ciało Twe i Krew za dar Twej obecności"])
        add("Dotknij, Panie, moich oczu", "Piotr Pałka (muz.), ks. Jan Twardowski (sł.)", tags: ["Uwielbienie"], phrases: ["Dotknij Panie moich oczu abym przejrzał", "Dotknij Panie moich warg"])
        add("Nie bójcie się żyć dla miłości", "Piotr Pałka", tags: ["Uwielbienie"], phrases: ["Nie bójcie się żyć dla miłości dla miłości warto żyć"])
        add("Oto mój sługa", "Piotr Pałka", tags: ["Wielki Post"], phrases: ["Oto mój sługa którego podtrzymuję"])

        // Taizé Community (Jacques Berthier)
        add("Bonum est confidere", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Bonum est confidere in Domino"])
        add("Bless the Lord, my soul", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Bless the Lord my soul and bless His holy name"])
        add("Cantate Domino", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Cantate Domino canticum novum"])
        add("Christe Salvator", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Christe Salvator Filius Patris dona nobis pacem"])
        add("Chryste, Twój Duch", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Chryste Twój Duch pośród nas zapala ogień"])
        add("Gloria, gloria in excelsis Deo", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Gloria gloria in excelsis Deo"])
        add("Ubi caritas et amor", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Ubi caritas et amor Deus ibi est"])
        add("Nada te turbe", "św. Teresa z Avila / Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Nada te turbe nada te espante quien a Dios tiene nada le falta"])
        add("Laudate Dominum", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Laudate Dominum omnes gentes"])
        add("Laudate omnes gentes", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Laudate omnes gentes laudate Dominum"])
        add("Misericordias Domini", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Misericordias Domini in aeternum cantabo"])
        add("In manus tuas, Pater", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["In manus tuas Pater commendo spiritum meum"])
        add("Bóg jest miłością", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Bóg jest miłością miejcie odwagę żyć dla miłości"])
        add("Jezu, Tyś jest światłością", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Jezu Tyś jest światłością mej duszy"])
        add("O usłysz mój głos", "Jacques Berthier / Taizé", tags: ["Taizé"], phrases: ["Panie usłysz modlitwę moją przyjmij wołanie me"])

        // Contemporary Christian / Worship (TGD, Deus Meus, Hillsong, etc.)
        add("Błogosław, duszo moja, Pana", "Trzecia Godzina Dnia (TGD) / Piotr Nazaruk", tags: ["Uwielbienie", "TGD"], phrases: ["Błogosław duszo moja Pana On odpuszcza wszystkie twoje grzechy", "On leczy wszystkie twoje choroby"])
        add("W cieniu Twoich rąk", "Trzecia Godzina Dnia (TGD) / Piotr Nazaruk", tags: ["Uwielbienie", "TGD"], phrases: ["W cieniu Twoich rąk ukryj Panie mnie"])
        add("Oto stoję u drzwi i kołaczę", "Trzecia Godzina Dnia (TGD) / Piotr Nazaruk", tags: ["Uwielbienie", "TGD"], phrases: ["Oto stoję u drzwi i kołaczę jeśli kto posłyszy mój głos"])
        add("Wiara czyni cuda", "Trzecia Godzina Dnia (TGD) / Piotr Nazaruk", tags: ["Uwielbienie", "TGD"], phrases: ["Wiara czyni cuda wiara przenosi góry"])
        add("Tak mnie skrusz", "Deus Meus", tags: ["Uwielbienie", "Deus Meus"], phrases: ["Tak mnie skrusz tak mnie złam tak mnie wypal Panie", "byś został tylko Ty"])
        add("Jezus jest tu", "Deus Meus", tags: ["Uwielbienie", "Deus Meus"], phrases: ["Jezus jest tu Jezus jest tu Jego krew oczyszcza nas"])
        add("Święte Imię Jezus", "Deus Meus", tags: ["Uwielbienie", "Deus Meus"], phrases: ["Święte Imię Jezus Święte Imię Jezus jest na ustach moich"])
        add("O, wychwalajcie Go", "Deus Meus", tags: ["Uwielbienie", "Deus Meus"], phrases: ["O wychwalajcie Go wszystkie narody"])
        add("Chodź, oto jest czas", "Brian Doerksen (Come, Now is the Time to Worship)", tags: ["Uwielbienie"], phrases: ["Chodź oto jest czas by wielbić Pana", "Chodź oto jest czas by oddać serce"])
        add("Chcę wywyższać Imię Twe", "Rick Founds (Lord, I Lift Your Name On High)", tags: ["Uwielbienie"], phrases: ["Chcę wywyższać Imię Twe chcę zaśpiewać Tobie chwałę", "Z nieba zstąpiłeś na ziemię"])
        add("Chcę przestąpić Jego próg", "Leona Von Brethorst (I Will Enter His Gates)", tags: ["Uwielbienie"], phrases: ["Chcę przestąpić Jego próg z dziękczynieniem w sercu mym", "Oto dzień który dał nam Pan"])
        add("Gdy wpatruję się w Twą Świętą Twarz", "Wayne & Cathy Perrin (When I Look into Your Holiness)", tags: ["Uwielbienie"], phrases: ["Gdy wpatruję się w Twą Świętą Twarz", "Wielbię Cię wielbię Cię to życia mego cel"])
        add("Agnus Dei", "Michael W. Smith", tags: ["Uwielbienie"], phrases: ["Alleluja Alleluja Królów Król Panów Pan", "Święty Święty Pan Bóg Wszechmogący"])
        add("Panie, Twój tron", "Graham Kendrick (Shine, Jesus, Shine)", tags: ["Uwielbienie"], phrases: ["Panie Twój tron wznosi się nad nami", "Świeć Jezu świeć"])
        add("Będę Cię uwielbiał", "Graham Kendrick", tags: ["Uwielbienie"], phrases: ["Będę Cię uwielbiał ze wszystkich moich sił"])
        add("Otwórz me oczy, chcę widzieć Jezusa", "Robert Cull (Open Our Eyes, Lord)", tags: ["Uwielbienie"], phrases: ["Otwórz me oczy chcę widzieć Jezusa dotknąć Go pragnę"])
        add("Chwalę Ciebie, Panie", "Bob Fitts", tags: ["Uwielbienie"], phrases: ["Chwalę Ciebie Panie chwalę Ciebie Panie całym sercem mym"])
        add("Jezus, Najwyższe Imię", "Naida Hearn (Jesus, Name Above All Names)", tags: ["Uwielbienie"], phrases: ["Jezus Najwyższe Imię nasz Zbawiciel Książę Pokoju"])
        add("Jezus zwyciężył", "ks. Kazimierz Wolny", tags: ["Uwielbienie"], phrases: ["Jezus zwyciężył to On dał nam życie", "Przelał krew swoją"])
        add("Jezus siłą mą", "Paul Baloche", tags: ["Uwielbienie"], phrases: ["Jezus siłą mą Jezus chlubą mą"])
        add("Duchu Miłości wylewaj się", "Mocni w Duchu / o. Remigiusz Recław SJ", tags: ["Mocni w Duchu", "Duch Święty"], phrases: ["Duchu Miłości wylewaj się na nas"])
        add("Jezus daje nam zbawienie", "Mocni w Duchu", tags: ["Mocni w Duchu"], phrases: ["Jezus daje nam zbawienie Jezus daje nam pokój"])
        add("Niechaj zstąpi Duch Twój", "Mocni w Duchu", tags: ["Mocni w Duchu", "Duch Święty"], phrases: ["Niechaj zstąpi Duch Twój i odnowi oblicze ziemi"])
        add("Będę śpiewał Tobie", "Psalm 104 / Wspólnota Miłości Ukrzyżowanej", tags: ["Uwielbienie"], phrases: ["Będę śpiewał Tobie mocy moja", "Bo Ty o Boże jesteś mą twierdzą"])
        add("Choćby figi nie zakwitły", "Habakuk 3,17-18 / Wspólnota Miłości Ukrzyżowanej", tags: ["Uwielbienie"], phrases: ["Choćby figi nie zakwitły a plon oliwek zawiódł"])
        add("Ci, którzy Jahwe ufają", "Psalm 125 / Wspólnota Miłości Ukrzyżowanej", tags: ["Uwielbienie"], phrases: ["Ci którzy Jahwe ufają są jak góra Syjon"])
        add("Bo góry mogą ustąpić", "Izajasz 54,10 / Odnowa w Duchu Świętym", tags: ["Uwielbienie"], phrases: ["Bo góry mogą ustąpić i pagórki się zachwiać", "ale miłość moja nie odstąpi od ciebie"])
        add("Boże mój, Boże, szukam Ciebie", "Psalm 63 / Wspólnota Miłości Ukrzyżowanej", tags: ["Uwielbienie"], phrases: ["Boże mój Boże szukam Ciebie i pragnie Ciebie moja dusza"])
        add("Zaufaj Mi", "s. Michaela Rak / Wspólnota Bożego Miłosierdzia", tags: ["Uwielbienie"], phrases: ["Ja z czułością cię utkałem i od wieków ukochałem", "Zaufaj Mi"])
        return database
    }
}
