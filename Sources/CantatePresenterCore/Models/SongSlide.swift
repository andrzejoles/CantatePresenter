import Foundation

public enum SlideType: String, Codable, CaseIterable {
    case verse = "Zwrotka"
    case chorus = "Refren"
    case bridge = "Bridge"
    case preChorus = "Pre-Chorus"
    case coda = "Coda"
    case interlude = "Przejście"
    case intro = "Intro"
    case outro = "Outro"
    case ending = "Zakończenie"
    case tag = "Tag"
    case blank = "Pusty"
    case custom = "Własny"
    
    /// Nieznany typ (np. z nowszej wersji aplikacji) staje się `.custom` zamiast psuć całą bibliotekę.
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = SlideType(rawValue: rawValue) ?? .custom
    }
    
    public var shortBadge: String {
        switch self {
        case .verse: return "Z"
        case .chorus: return "R"
        case .bridge: return "B"
        case .preChorus: return "PC"
        case .coda: return "CODA"
        case .interlude: return "PRZ"
        case .intro: return "IN"
        case .outro: return "OUT"
        case .ending: return "ZAK"
        case .tag: return "TAG"
        case .blank: return "—"
        case .custom: return "•"
        }
    }
}

public struct SongSlide: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var type: SlideType
    public var label: String
    public var text: String
    
    public init(id: UUID = UUID(), type: SlideType = .verse, label: String = "Zwrotka", text: String = "") {
        self.id = id
        self.type = type
        self.label = label
        self.text = text
    }
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, type, label, text
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decodeIfPresent(SlideType.self, forKey: .type) ?? .verse
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? type.rawValue
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
    
    public var lines: [String] {
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    public var previewText: String {
        let clean = lines.joined(separator: " / ")
        if clean.count > 90 {
            return String(clean.prefix(87)) + "..."
        }
        return clean
    }
}
