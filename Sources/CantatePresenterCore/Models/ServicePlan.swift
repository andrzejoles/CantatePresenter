import Foundation

public struct PlanItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var songId: UUID
    public var note: String
    
    public init(id: UUID = UUID(), songId: UUID, note: String = "") {
        self.id = id
        self.songId = songId
        self.note = note
    }
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, songId, note
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.songId = try container.decode(UUID.self, forKey: .songId)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

public struct ServicePlan: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [PlanItem]
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String = "Nowy plan",
        items: [PlanItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, name, items, createdAt, updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Nowy plan"
        self.items = try container.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
