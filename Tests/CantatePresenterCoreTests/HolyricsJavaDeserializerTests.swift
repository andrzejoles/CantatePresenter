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

    @Test(
        "Prawdziwy eksport Holyrics z repozytorium",
        .enabled(if: FileManager.default.fileExists(atPath: Self.realExport.path))
    )
    func realExport() throws {
        let data = try Data(contentsOf: Self.realExport)
        let records = try parse(data)
        #expect(!records.isEmpty)

        var generator = SplitMix64(seed: 7)
        for _ in 0..<20 {
            _ = try? parse(data.prefix(Int.random(in: 0..<data.count, using: &generator)))
        }
    }

    static let realExport = URL(fileURLWithPath: #filePath)
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
