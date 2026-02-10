import Foundation

/// A discrete step within an execution plan.
public struct PlanStep: Sendable, Codable, Equatable, Hashable {
    /// Human‑readable description of this step.
    public let description: String

    /// Whether this step has been completed.
    public var isCompleted: Bool

    public init(description: String, isCompleted: Bool = false) {
        self.description = description
        self.isCompleted = isCompleted
    }
}

/// The lifecycle status of a ``Plan``.
@frozen
public enum PlanStatus: String, Sendable, Codable, Equatable, Hashable {
    case active
    case completed
    case archived
    case cancelled
}

/// A structured execution plan produced by the reasoning engine.
///
/// Plans are versioned, archivable, and safe for persistence across
/// process, disk, and iCloud boundaries.
public struct Plan: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier for this plan.
    public let id: UUID

    /// The original user intent that spawned this plan.
    public let sourceIntent: String

    /// Ordered steps to execute.
    public var steps: [PlanStep]

    /// Current lifecycle status.
    public var status: PlanStatus

    /// Creation timestamp (seconds since reference date).
    public let createdAt: Date

    /// Whether this plan has been superseded and archived.
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        sourceIntent: String,
        steps: [PlanStep],
        status: PlanStatus = .active,
        createdAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.sourceIntent = sourceIntent
        self.steps = steps
        self.status = status
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    /// Mark the plan as archived, preserving its data for audit.
    public mutating func archive() {
        status = .archived
        isArchived = true
    }
}
