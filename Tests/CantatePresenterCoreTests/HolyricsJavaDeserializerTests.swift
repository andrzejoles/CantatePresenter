import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Java ObjectStream builder

/// Buduje minimalny strumień Java ObjectStream jak eksport Holyrics:
/// `ArrayList` z obiektami `com.limagiran.holyrics.model.Music` (pola `title`, `lyrics`).
private struct JavaStream {
    var bytes: [UInt8] = [0xAC, 0xED, 0x00, 0x05]

    mutating func u8(_ value: UInt8) { bytes.append(value) }
    mutating func u16(_ value: UInt16) { bytes += [UInt8(value >> 8), UInt8(value & 0xFF)] }
    mutating func u32(_ value: UInt32) { bytes += (0..<4).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    mutating func u64(_ value: UInt64) { bytes += (0..<8).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    mutating func utf(_ string: String) {
        let data = Array(string.utf8)
        u16(UInt16(data.count))
        bytes += data
    }
    mutating func string(_ value: String) { u8(0x74); utf(value) }
    mutating func reference(_ handle: UInt32) { u8(0x71); u32(0x7E0000 + handle) }

    static func musicList(_ songs: [(title: String, lyrics: String)]) -> Data {
        var s = JavaStream()
        // h0: ArrayList classdesc
        s.u8(0x73); s.u8(0x72); s.utf("java.util.ArrayList"); s.u64(0x7881D21D99C7619D); s.u8(0x03)
        s.u16(1); s.u8(UInt8(ascii: "I")); s.utf("size")
        s.u8(0x78); s.u8(0x70)
        // h1: ArrayList object
        s.u32(UInt32(songs.count))
        s.u8(0x77); s.u8(4); s.u32(UInt32(songs.count))
        var musicClassHandle: UInt32?
        var nextHandle: UInt32 = 2
        for song in songs {
            s.u8(0x73)
            if let handle = musicClassHandle {
                s.reference(handle)
            } else {
                musicClassHandle = nextHandle
                s.u8(0x72); s.utf("com.limagiran.holyrics.model.Music"); s.u64(1); s.u8(0x02)
                s.u16(2)
                s.u8(UInt8(ascii: "L")); s.utf("title"); s.string("Ljava/lang/String;")
                s.u8(UInt8(ascii: "L")); s.utf("lyrics"); s.reference(nextHandle + 1)
                s.u8(0x78); s.u8(0x70)
                nextHandle += 2
            }
            nextHandle += 1 // obiekt Music
            s.string(song.title); s.string(song.lyrics)
            nextHandle += 2
        }
        s.u8(0x78)
        return Data(s.bytes)
    }

    static func raw(_ body: [UInt8]) -> Data {
        Data([0xAC, 0xED, 0x00, 0x05] + body)
    }
}

// MARK: - W6: deserializer .mufl

@Suite("HolyricsJavaDeserializer (W6)")
struct HolyricsJavaDeserializerTests {
    private let songs = [
        (title: "Barka", lyrics: "Pan kiedyś stanął nad brzegiem"),
        (title: "Abba Ojcze", lyrics: "Ty jesteś Bogiem"),
        (title: "Jezus Siłą Mą", lyrics: "Jezus siłą mą")
    ]

    private func parse(_ data: Data) throws -> [HolyricsJavaDeserializer.RawMusicRecord] {
        try HolyricsJavaDeserializer(data: data).deserializeMusicRecords()
    }

    @Test("Poprawny eksport: wszystkie pieśni, także z referencją do klasy")
    func parsesValidExport() throws {
        let records = try parse(JavaStream.musicList(songs))

        #expect(records.map(\.title) == songs.map(\.title))
        #expect(records.map(\.lyrics) == songs.map(\.lyrics))
    }

    @Test("Wycinek Data z niezerowym indeksem startowym")
    func parsesDataSlice() throws {
        let full = Data([0xFF, 0xFF]) + JavaStream.musicList(songs)
        let slice = full[2...]

        #expect(try parse(slice).count == songs.count)
    }

    @Test("Obcięcie w każdym miejscu: błąd albo wynik, nigdy awaria")
    func everyTruncationIsSafe() {
        let data = JavaStream.musicList(songs)
        for length in 0..<data.count {
            _ = try? parse(data.prefix(length))
        }
    }

    @Test("Losowe uszkodzenia bajtów: błąd albo wynik, nigdy awaria ani zawieszenie")
    func randomCorruptionIsSafe() {
        let data = JavaStream.musicList(songs)
        var generator = SplitMix64(seed: 2026)
        let start = ContinuousClock.now
        for _ in 0..<3_000 {
            var bytes = Array(data)
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                let index = Int.random(in: 4..<bytes.count, using: &generator)
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
            _ = try? parse(Data(bytes))
        }
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test("Obcięty .mufl: pieśni sprzed uszkodzenia i komunikat, nigdy binarna „pieśń” (R2-04)")
    func truncatedFileImportsCompleteSongsWithProblem() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let data = JavaStream.musicList(songs)
        let file = dir.file("biblioteka.mufl")
        try data.prefix(data.count - 3).write(to: file)

        let outcome = TextImporter.importFile(file)

        #expect(outcome.songs.map(\.title) == ["Barka", "Abba Ojcze"])
        #expect(!outcome.songs.contains { $0.rawLyrics.contains("\u{0}") || $0.title == "biblioteka" })
        #expect(outcome.problems.count == 1)
        #expect(outcome.problems.first?.fileName == "biblioteka.mufl")
    }

    @Test("Uszkodzony nagłówek .mufl: brak pieśni, jest komunikat (R2-04)")
    func corruptFileReportsProblem() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let file = dir.file("zly.mufl")
        try JavaStream.raw([0x7E, 0x00, 0x01, 0x02, 0x03]).write(to: file)

        let outcome = TextImporter.importFile(file)

        #expect(outcome.songs.isEmpty)
        #expect(outcome.problems.count == 1)
    }

    @Test("Referencja poniżej bazowego uchwytu: błąd zamiast przepełnienia")
    func referenceBelowBaseHandle() {
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw([0x71, 0x00, 0x00, 0x00, 0x01]))
        }
    }

    @Test("Tablica z długością 4 mld: szybki błąd zamiast zawieszenia")
    func hugeArrayLength() {
        // TC_ARRAY, TC_NULL jako opis klasy, długość 0xFFFFFFFF, brak elementów
        let start = ContinuousClock.now
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw([0x75, 0x70, 0xFF, 0xFF, 0xFF, 0xFF]))
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test("Długi napis z długością bliską Int.max: błąd zamiast przepełnienia")
    func hugeLongStringLength() {
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw([0x7C, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x41]))
        }
    }

    @Test("Bardzo głębokie zagnieżdżenie: błąd zamiast przepełnienia stosu")
    func deepNesting() {
        // Każde TC_ARRAY czyta opis klasy rekurencyjnie.
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw(Array(repeating: 0x75, count: 100_000)))
        }
    }

    @Test("Głęboko zagnieżdżone obiekty: błąd zamiast przepełnienia stosu")
    func deepObjectNesting() {
        // TC_OBJECT czyta opis klasy rekurencyjnie; tu zamiast opisu jest kolejny TC_OBJECT.
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw(Array(repeating: 0x73, count: 100_000)))
        }
    }

    @Test("Długi łańcuch nadklas: błąd zamiast przepełnienia stosu")
    func deepSuperclassChain() {
        var body: [UInt8] = []
        for _ in 0..<10_000 {
            // TC_CLASSDESC, nazwa "A", suid, flagi, 0 pól, TC_ENDBLOCKDATA, potem nadklasa (kolejny opis)
            body += [0x72, 0x00, 0x01, 0x41] + Array(repeating: 0, count: 8) + [0x02, 0x00, 0x00, 0x78]
        }
        #expect(throws: (any Error).self) {
            try parse(JavaStream.raw(body))
        }
    }

    // MARK: R7-03: wzmocnienie przez referencje

    /// Opis klasy `Music` z jednym polem `lyrics` (uchwyty: h0 opis, h1 typ pola).
    private func musicClassDescriptor(into s: inout JavaStream) {
        s.u8(0x72); s.utf("com.limagiran.holyrics.model.Music"); s.u64(0); s.u8(0x02); s.u16(1)
        s.u8(UInt8(ascii: "L")); s.utf("lyrics"); s.string("Ljava/lang/String;")
        s.u8(0x78); s.u8(0x70)
    }

    @Test("Lista miliona referencji do jednej pieśni: jedna pieśń, szybko (R7-03)")
    func repeatedReferencesToOneSongCountOnce() throws {
        var s = JavaStream()
        s.u8(0x73); musicClassDescriptor(into: &s)                 // h2: obiekt Music
        s.string(String(repeating: "Alleluja ", count: 6_000))     // h3: 54 KB tekstu
        s.u8(0x73); s.u8(0x72); s.utf("java.util.ArrayList"); s.u64(0); s.u8(0x03); s.u16(1)
        s.u8(UInt8(ascii: "I")); s.utf("size"); s.u8(0x78); s.u8(0x70)
        let count: UInt32 = 200_000
        s.u32(count); s.u8(0x77); s.u8(4); s.u32(count)
        for _ in 0..<count { s.reference(2) }
        s.u8(0x78)
        // Ponowne referencje do całej listy na najwyższym poziomie też nie mnożą pieśni.
        for _ in 0..<1_000 { s.reference(5) }

        let start = ContinuousClock.now
        let records = try parse(Data(s.bytes))
        #expect(records.count == 1)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Ponowne referencje do listy pieśni nie dublują pieśni (R7-03)")
    func repeatedListReferencesDoNotDuplicate() throws {
        var bytes = Array(JavaStream.musicList(songs))
        // h1 to obiekt ArrayList w `musicList`.
        for _ in 0..<50 { bytes += [0x71, 0x00, 0x7E, 0x00, 0x01] }

        #expect(try parse(Data(bytes)).map(\.title) == songs.map(\.title))
    }

    @Test("Tysiące pieśni z referencją do tego samego długiego tekstu: błąd zamiast gigabajtów (R7-03)")
    func sharedLyricsAmplificationIsRejected() {
        var s = JavaStream()
        s.u8(0x73); musicClassDescriptor(into: &s)                 // h2: pierwszy obiekt Music
        s.string(String(repeating: "Alleluja ", count: 6_000))     // h3
        for _ in 0..<3_000 {
            s.u8(0x73); s.reference(0); s.reference(3)              // 11 bajtów = 54 KB tekstu
        }
        let deserializer = HolyricsJavaDeserializer(data: Data(s.bytes))
        let start = ContinuousClock.now
        let result = deserializer.deserializeMusicRecordsPartially()
        #expect(result.error != nil)
        let total = result.records.reduce(0) { $0 + $1.lyrics.utf8.count }
        #expect(total <= 8 * s.bytes.count + HolyricsJavaDeserializer.textAllowance)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// R10-08: pieśni są zbierane z listy (i obiektów) najwyższego poziomu; referencja do pieśni odczytanej
    /// wcześniej nic nie dodaje (R7-03). Pieśń zapisana najpierw w polu innego obiektu, a potem tylko wskazana
    /// referencją z listy, nie trafia więc do wyniku. Prawdziwy eksport Holyrics tak nie wygląda: to `ArrayList`
    /// obiektów `Music`, każdy zapisany w liście w całości, a klasa `Music` nie ma pól typu `Music` (same napisy,
    /// liczby, `List order`, `String[]`). Ten sam wynik (901 pieśni) dają stary i nowy deserializer na prawdziwym pliku.
    @Test("Referencja z listy do pieśni zapisanej wcześniej w polu innego obiektu nic nie dodaje (R10-08)")
    func referenceToSongReadInsideAnotherObject() throws {
        var s = JavaStream()
        // h0: opis klasy Wrapper, h1: typ pola, h2: obiekt Wrapper
        s.u8(0x73); s.u8(0x72); s.utf("Wrapper"); s.u64(0); s.u8(0x02); s.u16(1)
        s.u8(UInt8(ascii: "L")); s.utf("favorite"); s.string("Ljava/lang/Object;")
        s.u8(0x78); s.u8(0x70)
        // Pole `favorite`: h3 opis Music, h4 typ pola, h5 obiekt Music, h6 tekst
        s.u8(0x73); musicClassDescriptor(into: &s)
        s.string("Pan kiedyś stanął nad brzegiem")
        // h7: opis ArrayList, h8: lista z referencją do h5
        s.u8(0x73); s.u8(0x72); s.utf("java.util.ArrayList"); s.u64(0); s.u8(0x03); s.u16(1)
        s.u8(UInt8(ascii: "I")); s.utf("size"); s.u8(0x78); s.u8(0x70)
        s.u32(1); s.u8(0x77); s.u8(4); s.u32(1)
        s.reference(5)
        s.u8(0x78)

        let result = HolyricsJavaDeserializer(data: Data(s.bytes)).deserializeMusicRecordsPartially()

        #expect(result.error == nil)
        #expect(result.records.isEmpty)
    }

    @Test("Opis klasy z nieznanym typem pola: szybki błąd (R7-03)")
    func unknownFieldTypeIsRejected() {
        var s = JavaStream()
        s.u8(0x73); s.u8(0x72); s.utf("X"); s.u64(0); s.u8(0x02); s.u16(65_535)
        for _ in 0..<65_535 { s.u8(UInt8(ascii: "Q")); s.utf("") }
        s.u8(0x78); s.u8(0x70)
        for _ in 0..<2_000 { s.u8(0x73); s.reference(0) }

        let start = ContinuousClock.now
        #expect(throws: (any Error).self) {
            try parse(Data(s.bytes))
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test(
        "Prawdziwy eksport Holyrics z repozytorium",
        .enabled(if: FileManager.default.fileExists(atPath: Self.realExportURL.path))
    )
    func realExport() throws {
        let data = try Data(contentsOf: Self.realExportURL)
        let records = try parse(data)
        #expect(!records.isEmpty)

        var generator = SplitMix64(seed: 7)
        for _ in 0..<20 {
            _ = try? parse(data.prefix(Int.random(in: 0..<data.count, using: &generator)))
        }
    }

    static let realExportURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("2026-10-14_16-19-00.mufl")
}

// MARK: - Deterministic RNG

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
