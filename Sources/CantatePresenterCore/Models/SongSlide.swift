import Foundation

/// Typ slajdu. W JSON zapisywany jako stały kod (S10); nazwa do wyświetlenia jest tłumaczona osobno.
public enum SlideType: String, Codable, CaseIterable, Sendable {
    case verse
    case chorus
    case bridge
    case preChorus
    case coda
    case interlude
    case intro
    case outro
    case ending
    case tag
    case blank
    case custom
    
    /// Polskie nazwy zapisywane przez wcześniejsze wersje aplikacji.
    private static let legacyNames: [String: SlideType] = [
        "Zwrotka": .verse, "Refren": .chorus, "Bridge": .bridge, "Pre-Chorus": .preChorus,
        "Coda": .coda, "Przejście": .interlude, "Intro": .intro, "Outro": .outro,
        "Zakończenie": .ending, "Tag": .tag, "Pusty": .blank, "Własny": .custom
    ]
    
    /// Przyjmuje kod albo starą polską nazwę; nieznany typ (np. z nowszej wersji) staje się `.custom`
    /// zamiast psuć całą bibliotekę.
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = SlideType(rawValue: rawValue) ?? Self.legacyNames[rawValue] ?? .custom
    }
    
    /// Domyślna polska nazwa typu, jak w etykietach tworzonych przez `Song.parseLyrics`.
    public var polishName: String {
        switch self {
        case .verse: return "Zwrotka"
        case .chorus: return "Refren"
        case .bridge: return "Bridge"
        case .preChorus: return "Pre-Chorus"
        case .coda: return "Coda"
        case .interlude: return "Przejście"
        case .intro: return "Intro"
        case .outro: return "Outro"
        case .ending: return "Zakończenie"
        case .tag: return "Tag"
        case .blank: return "Pusty"
        case .custom: return "Własny"
        }
    }
    
    /// Znaczek typu na kartach slajdów: polski skrót, a zarazem klucz katalogu tłumaczeń (widoki: `L(type.shortBadge)`, R8-07).
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

public struct SongSlide: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var type: SlideType
    public var label: String
    public var text: String
    /// Numer sekcji danego typu (np. zwrotka 2). Skok do zwrotki korzysta z numeru, nie z etykiety (S10).
    public var number: Int?
    
    public init(id: UUID = UUID(), type: SlideType = .verse, label: String = "Zwrotka", text: String = "", number: Int? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.text = text
        self.number = number
    }
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, type, label, text, number
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decodeIfPresent(SlideType.self, forKey: .type) ?? .verse
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? type.polishName
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        // Starsze pliki nie mają numeru: odczytujemy go z etykiety, np. „Zwrotka 2”.
        self.number = try container.decodeIfPresent(Int.self, forKey: .number) ?? SongSlide.trailingNumber(in: label)
    }
    
    /// Liczba na końcu etykiety („Zwrotka 2” → 2, „Refren” → nil).
    static func trailingNumber(in label: String) -> Int? {
        let digits = label.reversed().prefix(while: \.isNumber)
        return digits.isEmpty ? nil : Int(String(digits.reversed()))
    }
    
    public var lines: [String] {
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
