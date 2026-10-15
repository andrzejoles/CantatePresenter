import Foundation

/// Native Swift deserializer for Java Object Serialization Stream (stream magic: AC ED 00 05).
/// Specifically optimized to deserialize `com.limagiran.holyrics.model.Music` arrays from `.mufl` / `.muf` Holyrics files.
public final class HolyricsJavaDeserializer {
    
    // Java Serialization Constants
    private static let STREAM_MAGIC: UInt16 = 0xaced
    private static let STREAM_VERSION: UInt16 = 0x0005
    
    private static let TC_NULL: UInt8 = 0x70
    private static let TC_REFERENCE: UInt8 = 0x71
    private static let TC_CLASSDESC: UInt8 = 0x72
    private static let TC_OBJECT: UInt8 = 0x73
    private static let TC_STRING: UInt8 = 0x74
    private static let TC_ARRAY: UInt8 = 0x75
    private static let TC_CLASS: UInt8 = 0x76
    private static let TC_BLOCKDATA: UInt8 = 0x77
    private static let TC_ENDBLOCKDATA: UInt8 = 0x78
    private static let TC_RESET: UInt8 = 0x79
    private static let TC_BLOCKDATALONG: UInt8 = 0x7A
    private static let TC_LONGSTRING: UInt8 = 0x7C
    private static let TC_PROXYCLASSDESC: UInt8 = 0x7D
    private static let TC_ENUM: UInt8 = 0x7E
    
    private static let BASE_WIRE_HANDLE: UInt32 = 0x7e0000
    /// Limit zagnieżdżenia `readContent` (W6). Prawdziwe eksporty mają kilka poziomów.
    /// Ramka `readContent` w buildzie debug jest duża: na wątku z 512 KB stosu (testy, `Task`)
    /// 64 poziomy już przepełniały stos, 48 jeszcze nie. 32 zostawia zapas.
    private static let MAX_DEPTH = 32
    
    public struct RawMusicRecord {
        public var title: String = ""
        public var author: String = ""
        public var artist: String = ""
        public var lyrics: String = ""
        public var key: String = ""
        public var note: String = ""
        public var formatting: String = ""
        public var language: String = ""
    }
    
    /// Bajty indeksowane od zera (wycinek `Data` może mieć niezerowy `startIndex`).
    private let bytes: [UInt8]
    private var pos: Int = 0
    private var depth: Int = 0
    private var handles: [Any?] = []
    
    public init(data: Data) {
        self.bytes = Array(data)
    }
    
    public static func isJavaSerializedStream(_ data: Data) -> Bool {
        data.starts(with: [0xac, 0xed, 0x00, 0x05])
    }
    
    public func deserializeMusicRecords() throws -> [RawMusicRecord] {
        guard bytes.count >= 4 else {
            throw DeserializationError.invalidHeader("Plik jest za krótki")
        }
        
        let magic = try readUInt16()
        let version = try readUInt16()
        guard magic == HolyricsJavaDeserializer.STREAM_MAGIC, version == HolyricsJavaDeserializer.STREAM_VERSION else {
            throw DeserializationError.invalidHeader("Nieprawidłowy nagłówek Java ObjectStream (oczekiwano AC ED 00 05)")
        }
        
        var musicRecords: [RawMusicRecord] = []
        
        while pos < bytes.count {
            guard let obj = try readContent() else {
                continue
            }
            
            if let list = obj as? [RawMusicRecord] {
                musicRecords.append(contentsOf: list)
            } else if let rec = obj as? RawMusicRecord {
                musicRecords.append(rec)
            } else if let dict = obj as? [String: Any] {
                if let elems = dict["_elements"] as? [RawMusicRecord] {
                    musicRecords.append(contentsOf: elems)
                } else if let rec = extractMusicFromDict(dict) {
                    musicRecords.append(rec)
                }
            }
        }
        
        return musicRecords
    }
    
    private enum DeserializationError: LocalizedError {
        case invalidHeader(String)
        case unexpectedToken(UInt8, Int)
        case prematureEndOfData(Int)
        case invalidReference(UInt32)
        case invalidLength(Int64, Int)
        case tooDeep(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidHeader(let msg): return "Błąd nagłówka: \(msg)"
            case .unexpectedToken(let tok, let offset): return String(format: "Nieoczekiwany znacznik 0x%02X na pozycji %d", tok, offset)
            case .prematureEndOfData(let offset): return "Przedwczesny koniec danych na pozycji \(offset)"
            case .invalidReference(let ref): return "Nieprawidłowy uchwyt referencji \(ref)"
            case .invalidLength(let length, let offset): return "Nieprawidłowa długość \(length) na pozycji \(offset)"
            case .tooDeep(let offset): return "Zbyt głębokie zagnieżdżenie danych na pozycji \(offset)"
            }
        }
    }
    
    // MARK: - Handle Management
    @discardableResult
    private func assignHandle(_ obj: Any?) -> Int {
        let idx = handles.count
        handles.append(obj)
        return idx
    }
    
    private func setHandle(_ idx: Int, _ obj: Any?) {
        if idx < handles.count {
            handles[idx] = obj
        }
    }
    
    // MARK: - Primitive Readers
    // Każdy odczyt sprawdza granice i rzuca błąd zamiast zwracać 0 po końcu danych (W6).
    private var remaining: Int { bytes.count - pos }
    
    private func require(_ count: Int) throws {
        guard count >= 0, count <= remaining else {
            throw DeserializationError.prematureEndOfData(pos)
        }
    }
    
    private func readUInt8() throws -> UInt8 {
        try require(1)
        let val = bytes[pos]
        pos += 1
        return val
    }
    
    private func readUInt16() throws -> UInt16 {
        try require(2)
        let val = UInt16(bytes[pos]) << 8 | UInt16(bytes[pos + 1])
        pos += 2
        return val
    }
    
    private func readUInt32() throws -> UInt32 {
        try require(4)
        let val = UInt32(bytes[pos]) << 24 | UInt32(bytes[pos + 1]) << 16 | UInt32(bytes[pos + 2]) << 8 | UInt32(bytes[pos + 3])
        pos += 4
        return val
    }
    
    private func readInt64() throws -> Int64 {
        try require(8)
        var val: Int64 = 0
        for i in 0..<8 {
            val = (val << 8) | Int64(bytes[pos + i])
        }
        pos += 8
        return val
    }
    
    private func skip(_ count: Int) throws {
        try require(count)
        pos += count
    }
    
    private func readString(length: Int) throws -> String {
        try require(length)
        let sub = bytes[pos..<(pos + length)]
        pos += length
        return String(bytes: sub, encoding: .utf8) ?? String(decoding: sub, as: UTF8.self)
    }
    
    private func readUTF() throws -> String {
        try readString(length: Int(try readUInt16()))
    }
    
    private func readLongUTF() throws -> String {
        let length = try readInt64()
        // Porównanie na Int64, zanim długość trafi do arytmetyki na pozycjach (przepełnienie `pos + length`).
        guard length >= 0, length <= Int64(remaining) else {
            throw DeserializationError.invalidLength(length, pos)
        }
        return try readString(length: Int(length))
    }
    
    /// Pomija dane bloku (`TC_BLOCKDATA` / `TC_BLOCKDATALONG`) aż do `TC_ENDBLOCKDATA`, czytając po drodze obiekty.
    /// Koniec danych przed `TC_ENDBLOCKDATA` to błąd, nie cichy wynik częściowy.
    private func readBlockContents(collect: Bool) throws -> [Any] {
        var elems: [Any] = []
        while true {
            try require(1)
            switch bytes[pos] {
            case HolyricsJavaDeserializer.TC_ENDBLOCKDATA:
                pos += 1
                return elems
            case HolyricsJavaDeserializer.TC_BLOCKDATA:
                pos += 1
                try skip(Int(try readUInt8()))
            case HolyricsJavaDeserializer.TC_BLOCKDATALONG:
                pos += 1
                try skip(Int(try readUInt32()))
            default:
                if collect {
                    if let el = try readContent() {
                        elems.append(el)
                    }
                } else {
                    _ = try readContent()
                }
            }
        }
    }
    
    // MARK: - Core Content Parser
    private struct ClassDescriptor {
        let name: String
        let suid: Int64
        let flags: UInt8
        let fields: [(name: String, typeCode: Character, className: String?)]
        let superClass: Any?
    }
    
    private func readContent() throws -> Any? {
        guard depth < HolyricsJavaDeserializer.MAX_DEPTH else {
            throw DeserializationError.tooDeep(pos)
        }
        depth += 1
        defer { depth -= 1 }
        
        let tc = try readUInt8()
        
        switch tc {
        case HolyricsJavaDeserializer.TC_NULL:
            return nil
            
        case HolyricsJavaDeserializer.TC_REFERENCE:
            let ref = try readUInt32()
            guard ref >= HolyricsJavaDeserializer.BASE_WIRE_HANDLE else {
                throw DeserializationError.invalidReference(ref)
            }
            let handleIndex = Int(ref - HolyricsJavaDeserializer.BASE_WIRE_HANDLE)
            guard handleIndex < handles.count else {
                throw DeserializationError.invalidReference(ref)
            }
            return handles[handleIndex]
            
        case HolyricsJavaDeserializer.TC_STRING:
            let h = assignHandle(nil)
            let s = try readUTF()
            setHandle(h, s)
            return s
            
        case HolyricsJavaDeserializer.TC_LONGSTRING:
            let h = assignHandle(nil)
            let s = try readLongUTF()
            setHandle(h, s)
            return s
            
        case HolyricsJavaDeserializer.TC_CLASSDESC:
            let h = assignHandle(nil)
            let name = try readUTF()
            let suid = try readInt64()
            let flags = try readUInt8()
            let numFields = Int(try readUInt16())
            // Każde pole zajmuje co najmniej 3 bajty (typ + długość nazwy).
            guard numFields * 3 <= remaining else {
                throw DeserializationError.invalidLength(Int64(numFields), pos)
            }
            
            var fields: [(name: String, typeCode: Character, className: String?)] = []
            fields.reserveCapacity(numFields)
            
            for _ in 0..<numFields {
                let ftype = Character(UnicodeScalar(try readUInt8()))
                let fname = try readUTF()
                var fclass: String? = nil
                if ftype == "[" || ftype == "L" {
                    if let c = try readContent() as? String {
                        fclass = c
                    }
                }
                fields.append((fname, ftype, fclass))
            }
            
            // Skip class annotations until TC_ENDBLOCKDATA
            while true {
                try require(1)
                if bytes[pos] == HolyricsJavaDeserializer.TC_ENDBLOCKDATA {
                    pos += 1
                    break
                } else if bytes[pos] == HolyricsJavaDeserializer.TC_BLOCKDATA {
                    pos += 1
                    try skip(Int(try readUInt8()))
                } else {
                    pos += 1
                }
            }
            
            let superClass = try readContent()
            let cd = ClassDescriptor(name: name, suid: suid, flags: flags, fields: fields, superClass: superClass)
            setHandle(h, cd)
            return cd
            
        case HolyricsJavaDeserializer.TC_OBJECT:
            guard let cdObj = try readContent() as? ClassDescriptor else {
                throw DeserializationError.unexpectedToken(tc, pos)
            }
            let h = assignHandle(nil)
            
            var obj: [String: Any] = ["_class": cdObj.name]
            setHandle(h, obj)
            
            // Gather class hierarchy
            var hierarchy: [ClassDescriptor] = []
            var curr: ClassDescriptor? = cdObj
            while let c = curr, hierarchy.count < HolyricsJavaDeserializer.MAX_DEPTH {
                hierarchy.append(c)
                curr = c.superClass as? ClassDescriptor
            }
            hierarchy.reverse()
            
            var musicRecord: RawMusicRecord? = nil
            if cdObj.name.contains("Music") {
                musicRecord = RawMusicRecord()
            }
            
            for c in hierarchy {
                // 1. Primitive fields
                for f in c.fields {
                    switch f.typeCode {
                    case "Z": // boolean
                        let val = try readUInt8() != 0
                        obj[f.name] = val
                    case "B": // byte
                        let val = try readUInt8()
                        obj[f.name] = val
                    case "C": // char
                        let val = try readUInt16()
                        obj[f.name] = val
                    case "S": // short
                        let val = Int16(bitPattern: try readUInt16())
                        obj[f.name] = val
                    case "I": // int
                        let val = Int32(bitPattern: try readUInt32())
                        obj[f.name] = val
                    case "J": // long
                        let val = try readInt64()
                        obj[f.name] = val
                    case "F": // float
                        let bits = try readUInt32()
                        obj[f.name] = Float(bitPattern: bits)
                    case "D": // double
                        let bits = UInt64(bitPattern: try readInt64())
                        obj[f.name] = Double(bitPattern: bits)
                    default:
                        break
                    }
                }
                
                // 2. Object fields
                for f in c.fields {
                    if f.typeCode == "[" || f.typeCode == "L" {
                        let fieldVal = try readContent()
                        if let str = fieldVal as? String {
                            obj[f.name] = str
                            if musicRecord != nil {
                                switch f.name {
                                case "title": musicRecord?.title = str
                                case "author": musicRecord?.author = str
                                case "artist": musicRecord?.artist = str
                                case "lyrics": musicRecord?.lyrics = str
                                case "formatting": musicRecord?.formatting = str
                                case "note": musicRecord?.note = str
                                case "language": musicRecord?.language = str
                                default: break
                                }
                            }
                        } else if let fieldVal = fieldVal {
                            obj[f.name] = fieldVal
                        }
                    }
                }
                
                // 3. Custom writeObject (SC_WRITE_METHOD flag 0x01)
                if (c.flags & 0x01) != 0 {
                    if c.name == "java.util.ArrayList" {
                        let elems = try readBlockContents(collect: true)
                        obj["_elements"] = elems
                        setHandle(h, obj)
                        return elems
                    } else {
                        // Skip extra block data until TC_ENDBLOCKDATA
                        _ = try readBlockContents(collect: false)
                    }
                }
            }
            
            if let rec = musicRecord {
                setHandle(h, rec)
                return rec
            }
            
            setHandle(h, obj)
            return obj
            
        case HolyricsJavaDeserializer.TC_ARRAY:
            _ = try readContent() // classDesc
            let h = assignHandle(nil)
            let arrLen = Int(try readUInt32())
            // Każdy element zajmuje co najmniej 1 bajt; większa długość oznacza uszkodzony plik.
            guard arrLen <= remaining else {
                throw DeserializationError.invalidLength(Int64(arrLen), pos)
            }
            var arr: [Any?] = []
            arr.reserveCapacity(arrLen)
            setHandle(h, arr)
            
            for _ in 0..<arrLen {
                let el = try readContent()
                arr.append(el)
            }
            setHandle(h, arr)
            return arr
            
        case HolyricsJavaDeserializer.TC_BLOCKDATA:
            try skip(Int(try readUInt8()))
            return nil
            
        case HolyricsJavaDeserializer.TC_BLOCKDATALONG:
            try skip(Int(try readUInt32()))
            return nil
            
        case HolyricsJavaDeserializer.TC_ENDBLOCKDATA:
            return nil
            
        case HolyricsJavaDeserializer.TC_RESET:
            handles.removeAll()
            return nil
            
        default:
            throw DeserializationError.unexpectedToken(tc, pos - 1)
        }
    }
    
    private func extractMusicFromDict(_ dict: [String: Any]) -> RawMusicRecord? {
        guard let title = dict["title"] as? String else { return nil }
        var rec = RawMusicRecord()
        rec.title = title
        rec.author = dict["author"] as? String ?? ""
        rec.artist = dict["artist"] as? String ?? ""
        rec.lyrics = dict["lyrics"] as? String ?? ""
        rec.formatting = dict["formatting"] as? String ?? ""
        rec.note = dict["note"] as? String ?? ""
        rec.language = dict["language"] as? String ?? ""
        return rec
    }
}
