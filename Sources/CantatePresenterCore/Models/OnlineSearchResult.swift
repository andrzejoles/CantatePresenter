import Foundation

public struct OnlineSearchResult: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var snippet: String
    public var lyrics: String
    public var source: String
    public var url: String?
    /// Opis licencji tekstu (S9), np. „Domena publiczna”.
    public var license: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        snippet: String = "",
        lyrics: String = "",
        source: String = "Web",
        url: String? = nil,
        license: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.snippet = snippet
        self.lyrics = lyrics
        self.source = source
        self.url = url
        self.license = license
    }
}
