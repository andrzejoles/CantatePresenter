import Foundation

public struct PlanItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var songId: UUID
    public var note: String
    
    public init(id: UUID = UUID(), songId: UUID, note: String = "") {
        self.id = id
        self.songId = songId
        self.note = note
    }
}

public struct ServicePlan: Identifiable, Codable, Equatable, Hashable {
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
}
