import Foundation

/// Deterministic priority tiers for the Preemptive Priority Scheduler.
///
/// Tier 0 events **immediately preempt** active inference.
@frozen
public enum PriorityTier: String, Sendable, Codable, Equatable, Hashable, Comparable {
    /// Heavy App Sentinel, thermal `.critical`, memory pressure `.critical`.
    case critical

    /// Direct user commands, voice commands, prompt refinements.
    case userInitiated

    /// Autonomous planning, web research, long‑running reasoning.
    case background

    // MARK: - Comparable

    private var rank: Int {
        switch self {
        case .critical: return 0
        case .userInitiated: return 1
        case .background: return 2
        }
    }

    public static func < (lhs: PriorityTier, rhs: PriorityTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A discrete unit of work submitted to the ``PriorityScheduler``.
public struct SchedulerTask: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID

    /// Priority tier.
    public let tier: PriorityTier

    /// Human‑readable label for debugging.
    public let label: String

    /// Submission timestamp.
    public let submittedAt: Date

    public init(
        id: UUID = UUID(),
        tier: PriorityTier,
        label: String,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.tier = tier
        self.label = label
        self.submittedAt = submittedAt
    }
}
