import Foundation

/// Result of content sanitization — either cleaned output or rejection.
public enum SanitizationResult: Sendable, Equatable {
    /// Content passed all filters and is safe for use.
    case clean(content: String)

    /// Content was rejected by the sanitization pipeline.
    case rejected(reason: String)

    /// Whether the result is clean.
    public var isSafe: Bool {
        switch self {
        case .clean: return true
        case .rejected: return false
        }
    }

    /// Extract the cleaned content, or `nil` if rejected.
    public var content: String? {
        switch self {
        case .clean(let c): return c
        case .rejected: return nil
        }
    }
}
