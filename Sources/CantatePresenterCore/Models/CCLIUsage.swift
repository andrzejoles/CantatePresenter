import Foundation

// MARK: - CCLI Usage Entry

/// Jedno wyświetlenie pieśni z numerem CCLI, zapisywane do raportu dla CCLI (`ccli_usage.json`).
public struct CCLIUsageEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var author: String
    public var ccliNumber: String
    public var copyright: String?
    
    public init(id: UUID = UUID(), date: Date, title: String, author: String, ccliNumber: String, copyright: String? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.author = author
        self.ccliNumber = ccliNumber
        self.copyright = copyright
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, date, title, author, ccliNumber, copyright
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        self.ccliNumber = try container.decodeIfPresent(String.self, forKey: .ccliNumber) ?? ""
        self.copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
    }
}

// MARK: - CCLI Usage Report

/// Raport użycia do ręcznego zgłoszenia w CCLI: bez klucza partnera API nie da się raportować automatycznie.
public enum CCLIUsageReport {
    /// Nowy wpis dla pieśni z numerem CCLI, najwyżej jeden na pieśń dziennie (jedno nabożeństwo = jedno użycie).
    public static func entry(for song: Song, at date: Date, existing: [CCLIUsageEntry], calendar: Calendar = .current) -> CCLIUsageEntry? {
        guard let number = song.ccliNumber?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { return nil }
        let alreadyRecorded = existing.contains { $0.ccliNumber == number && calendar.isDate($0.date, inSameDayAs: date) }
        guard !alreadyRecorded else { return nil }
        return CCLIUsageEntry(date: date, title: song.title, author: song.author, ccliNumber: number, copyright: song.copyright)
    }
    
    /// CSV z jednym wierszem na wyświetlenie (nagłówki po angielsku jak w CCLI; to format danych, nie tekst UI).
    public static func csv(_ entries: [CCLIUsageEntry], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        
        var lines = ["Date,Title,Authors,CCLI Song Number,Copyright"]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            lines.append([formatter.string(from: entry.date), entry.title, entry.author, entry.ccliNumber, entry.copyright ?? ""]
                .map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
    
    static func escape(_ field: String) -> String {
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
