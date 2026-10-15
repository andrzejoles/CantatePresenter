import Foundation

// MARK: - Wikisource License

/// Licencja tekstu z Wikiźródeł (S9). Serwis przyjmuje tylko teksty w domenie publicznej albo na wolnej licencji.
public enum WikisourceLicense: String, Codable, Sendable {
    case publicDomain
    case ccBySA
    case unknown
    
    public var label: String {
        switch self {
        case .publicDomain: return Lnow("Domena publiczna")
        case .ccBySA: return "CC BY-SA"
        case .unknown: return Lnow("Licencja: zobacz stronę źródła")
        }
    }
}

// MARK: - Wikisource Parser

/// Czyste funkcje do odczytu stron Wikiźródeł zwracanych przez API MediaWiki (`action=parse`).
public enum WikisourceParser {
    /// Wersja językowa Wikiźródeł dla języka wyszukiwania; „wszystkie języki” szukają w polskiej.
    public static func host(forLanguage language: String) -> String {
        let supported: Set<String> = ["pl", "en", "de", "es", "uk", "fr", "it", "la"]
        let code = supported.contains(language) ? language : "pl"
        return "\(code).wikisource.org"
    }
    
    public static func pageURL(title: String, language: String) -> URL {
        let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://\(host(forLanguage: language))/wiki/\(path)")!
    }
    
    /// Tekst pieśni z bloków `<div class="poem">`: zwrotki rozdzielone pustą linią, bez numerów stron i przypisów.
    /// Zwrotka przecięta końcem strony skanu (dwa bloki) jest sklejana z powrotem.
    public static func lyrics(fromHTML html: String) -> String {
        var blocks: [[[String]]] = []
        for body in matches(of: #"<div class="poem"[^>]*>(.*?)</div>"#, in: html) {
            var text = body
            text = replacing(#"<span[^>]*ws-pagenum[^>]*>.*?</span>"#, in: text, with: "")
            text = replacing(#"<sup[^>]*>.*?</sup>"#, in: text, with: "")
            text = text.replacingOccurrences(of: "\n", with: "")
            text = replacing(#"<br\s*/?>"#, in: text, with: "\n")
            text = replacing(#"</p>"#, in: text, with: "\n\n")
            text = decodeEntities(replacing(#"<[^>]+>"#, in: text, with: ""))
            
            var stanzas: [[String]] = []
            var current: [String] = []
            for line in text.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if !line.isEmpty {
                    current.append(line)
                } else if !current.isEmpty {
                    stanzas.append(current)
                    current = []
                }
            }
            if !current.isEmpty { stanzas.append(current) }
            if !stanzas.isEmpty { blocks.append(stanzas) }
        }
        
        let stanzas = mergeSplitStanzas(blocks)
        return stanzas.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }
    
    /// Koniec bloku i początek następnego są jedną zwrotką, gdy obie części są krótsze od typowej zwrotki
    /// i razem jej nie przekraczają.
    static func mergeSplitStanzas(_ blocks: [[[String]]]) -> [[String]] {
        let counts = blocks.flatMap { $0.map(\.count) }
        let frequency = Dictionary(counts.map { ($0, 1) }, uniquingKeysWith: +)
        let typical = frequency.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
        
        var result: [[String]] = []
        var carryMergeable = false
        for block in blocks {
            for (index, stanza) in block.enumerated() {
                if index == 0, carryMergeable, let last = result.last,
                   last.count < typical, stanza.count < typical, last.count + stanza.count <= typical {
                    result[result.count - 1] = last + stanza
                } else {
                    result.append(stanza)
                }
            }
            carryMergeable = true
        }
        return result
    }
    
    public static func license(fromHTML html: String) -> WikisourceLicense {
        let lower = html.lowercased()
        if lower.contains("public domain") || lower.contains("własnością publiczną") || lower.contains("gemeinfrei") {
            return .publicDomain
        }
        if lower.contains("creative commons") {
            return .ccBySA
        }
        return .unknown
    }
    
    /// Autor z parametru `autor` szablonu „Dane tekstu” (albo `author` w „header”); odnośniki zamieniane na nazwę.
    public static func author(fromWikitext wikitext: String) -> String {
        guard let raw = matches(of: #"\|\s*(?:autor|author)\s*=((?:\[\[[^\]]*\]\]|[^\n|\[])*)"#, in: wikitext).first else {
            return ""
        }
        return plainText(fromWikiLinks: raw)
    }
    
    static func plainText(fromWikiLinks text: String) -> String {
        var value = replacing(#"\[\[[^\]|]*\|([^\]]*)\]\]"#, in: text, with: "$1")
        value = replacing(#"\[\[(?:[^\]:]*:)?([^\]]*)\]\]"#, in: value, with: "$1")
        value = value.replacingOccurrences(of: "''", with: "")
        return value.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Helpers
    
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }
    
    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let whole = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let digits = Range(match.range(at: 2), in: result),
                      let code = UInt32(result[digits], radix: result[hexRange].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
