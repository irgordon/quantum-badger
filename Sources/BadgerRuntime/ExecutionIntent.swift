import Foundation

/// Where inference was executed.
@frozen
public enum ExecutionLocation: String, Sendable, Codable, Equatable, Hashable {
    case local
    case cloud
}

/// A request submitted to ``HybridExecutionManager``.
public struct ExecutionIntent: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier for this intent.
    public let id: UUID

    /// The user prompt or task description.
    public let prompt: String

    /// Priority tier for scheduling.
    public let tier: PriorityTier

    /// Maximum tokens the caller is willing to budget.
    public let tokenBudget: UInt64

    public init(
        id: UUID = UUID(),
        prompt: String,
        tier: PriorityTier = .userInitiated,
        tokenBudget: UInt64 = 2048
    ) {
        self.id = id
        self.prompt = prompt
        self.tier = tier
        self.tokenBudget = tokenBudget
    }
}
