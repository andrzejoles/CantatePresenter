import Foundation
import os

/// Wyszukiwanie pieśni w Wikiźródłach przez API MediaWiki (S9). Teksty są w domenie publicznej albo na wolnej licencji,
/// a każdy wynik ma adres strony źródłowej. Wcześniejsze źródła (DuckDuckGo, LRCLIB, wbudowany katalog) usunięte.
public final class OnlineSearchService: Sendable {
    public static let shared = OnlineSearchService()
    
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "online-search")
    /// Zasady Wikimedia wymagają przedstawienia się programu w nagłówku User-Agent.
    private static let userAgent = "CantatePresenter/\(AppVersion.current) (https://github.com/andrzejoles/CantatePresenter)"
    private static let maxResults = 12
    
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": OnlineSearchService.userAgent]
        return URLSession(configuration: configuration)
    }()
    
    /// Wyniki tylko ze stron, które zawierają tekst pieśni lub wiersza (ujednoznacznienia i spisy są pomijane).
    public func search(query: String, language: String = "pl") async -> [OnlineSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        let titles = await searchTitles(query: clean, language: language)
        let pages = await withTaskGroup(of: (Int, OnlineSearchResult?).self) { group in
            for (index, title) in titles.enumerated() {
                group.addTask { (index, await self.fetchPage(title: title, language: language)) }
            }
            var collected: [(Int, OnlineSearchResult)] = []
            for await (index, result) in group {
                if let result { collected.append((index, result)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return pages
    }
    
    // MARK: - API
    
    private func searchTitles(query: String, language: String) async -> [String] {
        guard let json = await apiRequest(language: language, parameters: [
            "action": "query", "list": "search", "srsearch": query,
            "srnamespace": "0", "srlimit": String(Self.maxResults)
        ]),
              let queryObject = json["query"] as? [String: Any],
              let hits = queryObject["search"] as? [[String: Any]] else {
            return []
        }
        return hits.compactMap { $0["title"] as? String }
    }
    
    private func fetchPage(title: String, language: String) async -> OnlineSearchResult? {
        guard let json = await apiRequest(language: language, parameters: [
            "action": "parse", "page": title, "prop": "text|wikitext", "disablelimitreport": "1"
        ]),
              let parse = json["parse"] as? [String: Any],
              let html = parse["text"] as? String else {
            return nil
        }
        let wikitext = parse["wikitext"] as? String ?? ""
        let lyrics = WikisourceParser.lyrics(fromHTML: html)
        guard !lyrics.isEmpty else { return nil }
        
        // Tytuł z nazwy strony: parametr `tytuł` na podstronach antologii zawiera tytuł całej książki.
        let displayTitle = Self.shortTitle(fromPageTitle: title)
        let license = WikisourceParser.license(fromHTML: html)
        
        return OnlineSearchResult(
            title: displayTitle,
            artist: WikisourceParser.author(fromWikitext: wikitext),
            snippet: title,
            lyrics: lyrics,
            source: Lnow("Wikiźródła"),
            url: WikisourceParser.pageURL(title: title, language: language).absoluteString,
            license: license.label
        )
    }
    
    /// „Śpiewnik kościelny/Boże z twoich rąk żyjemy” → „Boże z twoich rąk żyjemy”; nawias z wydaniem odcięty.
    static func shortTitle(fromPageTitle title: String) -> String {
        let last = title.components(separatedBy: "/").last ?? title
        if let range = last.range(of: #"\s*\([^)]*\)$"#, options: .regularExpression) {
            return String(last[..<range.lowerBound])
        }
        return last
    }
    
    private func apiRequest(language: String, parameters: [String: String]) async -> [String: Any]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = WikisourceParser.host(forLanguage: language)
        components.path = "/w/api.php"
        components.queryItems = (parameters.merging(["format": "json", "formatversion": "2"]) { a, _ in a })
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                Self.logger.error("Wikiźródła: HTTP \(http.statusCode)")
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            Self.logger.error("Wikiźródła: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
