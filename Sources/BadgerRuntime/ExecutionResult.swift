import Foundation

/// The result of a completed inference cycle.
public struct ExecutionResult: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier matching the originating ``ExecutionIntent``.
    public let intentID: UUID

    /// The generated output text.
    public let output: String

    /// Where the inference was executed.
    public let location: ExecutionLocation

    /// Number of tokens consumed.
    public let tokensUsed: UInt64

    /// Wall‑clock duration of the inference in nanoseconds.
    public let durationNanoseconds: UInt64

    public init(
        intentID: UUID,
        output: String,
        location: ExecutionLocation,
        tokensUsed: UInt64,
        durationNanoseconds: UInt64
    ) {
        self.intentID = intentID
        self.output = output
        self.location = location
        self.tokensUsed = tokensUsed
        self.durationNanoseconds = durationNanoseconds
    }
}
