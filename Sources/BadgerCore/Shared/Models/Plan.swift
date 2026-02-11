import Foundation

/// A discrete step within an execution plan.
public struct PlanStep: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Unique ID to ensure UI lists handle duplicate descriptions correctly.
    public let id: UUID
    
    public let description: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), description: String, isCompleted: Bool = false) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
    }
}

@frozen
public enum PlanStatus: String, Sendable, Codable, Equatable, Hashable {
    case active
    case completed
    case archived
    case cancelled
}

public struct Plan: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let sourceIntent: String
    public var steps: [PlanStep]
    public var status: PlanStatus
    public let createdAt: Date

    // MARK: - Computed Helpers
    
    /// Derived property to avoid state desynchronization.
    public var isArchived: Bool {
        status == .archived
    }
    
    /// Returns the progress as a normalized value (0.0 to 1.0) for UI progress bars.
    public var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let completedCount = steps.filter { $0.isCompleted }.count
        return Double(completedCount) / Double(steps.count)
    }

    public init(
        id: UUID = UUID(),
        sourceIntent: String,
        steps: [PlanStep],
        status: PlanStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceIntent = sourceIntent
        self.steps = steps
        self.status = status
        self.createdAt = createdAt
    }

    public mutating func archive() {
        status = .archived
    }
}
