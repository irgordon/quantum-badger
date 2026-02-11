import Foundation
import AppIntents
import CoreSpotlight

/// A long-running agent mission or goal, indexed in Spotlight.
///
/// Conforms to `IndexedEntity` to allow system-wide search and
/// semantic understanding of the agent's current workload.
public struct TaskGoal: AppEntity, IndexedEntity, Identifiable, Sendable {
    
    // MARK: - AppEntity Requirements
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Agent Mission"
    public static var defaultQuery = BadgerGoalQuery()
    
    public var id: UUID
    
    @Property(title: "Title")
    public var title: String
    
    @Property(title: "Status")
    public var status: String
    
    @Property(title: "Created")
    public var createdAt: Date
    
    // MARK: - Init
    
    public init(id: UUID = UUID(), title: String, status: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
    }
    
    // MARK: - IndexedEntity Requirements
    
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(status)")
    }
    
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.displayName = title
        attributes.contentDescription = "Quantum Badger Mission: \(status)"
        attributes.keywords = ["Badger", "Mission", "Agent", status, title]
        
        // Visual Metadata
        // 🔒 SAFETY: Removed unsafe system path read.
        // On newer OS versions, we can use symbol names.
        if #available(macOS 13.0, iOS 16.0, *) {
            if status.lowercased().contains("complete") {
                attributes.symbolName = "checkmark.circle.fill"
            } else if status.lowercased().contains("failed") {
                 attributes.symbolName = "exclamationmark.triangle.fill"
            } else {
                 attributes.symbolName = "target"
            }
        }
        
        return attributes
    }
}

// MARK: - Query Dependency

/// Protocol to abstract the goal provider (TaskPlanner).
public protocol TaskGoalProvider: Sendable {
    func activeGoals() async -> [TaskGoal]
    func goals(matching: String) async -> [TaskGoal]
    func goals(for ids: [UUID]) async -> [TaskGoal]
}

// MARK: - Query

public struct BadgerGoalQuery: EntityQuery {
    
    /// Dependency injection point.
    /// Needs to be set by the App/Runtime on startup.
    /// ⚠️ Ensure this is set before indexing begins.
    public static var provider: (any TaskGoalProvider)?
    
    public init() {}
    
    public func entities(for identifiers: [UUID]) async throws -> [TaskGoal] {
        guard let provider = Self.provider else { return [] }
        return await provider.goals(for: identifiers)
    }
    
    public func suggestedEntities() async throws -> [TaskGoal] {
        guard let provider = Self.provider else { return [] }
        return await provider.activeGoals()
    }
    
    public func entities(matching string: String) async throws -> [TaskGoal] {
        guard let provider = Self.provider else { return [] }
        // Pass the search string to the provider to handle case-insensitive/fuzzy matching
        return await provider.goals(matching: string)
    }
}
