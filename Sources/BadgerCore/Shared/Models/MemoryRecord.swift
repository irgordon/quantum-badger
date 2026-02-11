import Foundation
import SwiftData

@Model
public final class MemoryRecord: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var content: String
    public var createdAt: Date
    public var lastAccessedAt: Date
    public var trustLevel: Int
    
    public init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        trustLevel: Int = 0
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.lastAccessedAt = createdAt
        self.trustLevel = trustLevel
    }
}
