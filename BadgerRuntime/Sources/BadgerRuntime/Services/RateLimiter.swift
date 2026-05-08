import Foundation
import BadgerCore

// MARK: - Rate Limit Errors

public enum RateLimitError: Error, Sendable {
    case limitExceeded(bucket: RateBucket, retryAfter: TimeInterval)
}

// MARK: - Rate Bucket

public enum RateBucket: String, Sendable, Codable {
    case localExecution = "LocalExecution"
    case cloudExecution = "CloudExecution"
    case webAccess = "WebAccess"
    case fileAccess = "FileAccess"

    public var capacity: Int {
        switch self {
        case .localExecution: return 20
        case .cloudExecution: return 10
        case .webAccess: return 15
        case .fileAccess: return 30
        }
    }

    public var refillRate: Double { // tokens per second
        switch self {
        case .localExecution: return 0.5 // 1 every 2s
        case .cloudExecution: return 0.1 // 1 every 10s
        case .webAccess: return 0.2
        case .fileAccess: return 1.0
        }
    }
}

// MARK: - Rate Limiter

/// Actor responsible for enforcing resource usage limits using a token-bucket algorithm.
public actor RateLimiter {

    private struct BucketState: Sendable {
        var tokens: Double
        var lastRefill: Date
    }

    private var buckets: [RateBucket: BucketState] = [:]
    private let clock: FunctionClock

    public init(clock: FunctionClock = SystemFunctionClock()) {
        self.clock = clock
    }

    /// Consume tokens from a specific bucket.
    /// - Parameters:
    ///   - tokens: Number of tokens to consume
    ///   - bucket: The target resource bucket
    /// - Throws: RateLimitError if insufficient tokens are available
    public func consume(tokens: Int = 1, bucket: RateBucket) throws {
        let now = clock.now()
        var state = buckets[bucket] ?? BucketState(tokens: Double(bucket.capacity), lastRefill: now)

        // 1. Refill tokens based on elapsed time
        let elapsed = now.timeIntervalSince(state.lastRefill)
        let refillAmount = elapsed * bucket.refillRate
        state.tokens = min(Double(bucket.capacity), state.tokens + refillAmount)
        state.lastRefill = now

        // 2. Check if we have enough tokens
        if state.tokens < Double(tokens) {
            let needed = Double(tokens) - state.tokens
            let retryAfter = needed / bucket.refillRate
            buckets[bucket] = state
            throw RateLimitError.limitExceeded(bucket: bucket, retryAfter: retryAfter)
        }

        // 3. Deduct tokens
        state.tokens -= Double(tokens)
        buckets[bucket] = state
    }

    /// Get current token count for a bucket
    public func getAvailableTokens(for bucket: RateBucket) -> Int {
        let now = clock.now()
        let state = buckets[bucket] ?? BucketState(tokens: Double(bucket.capacity), lastRefill: now)
        let elapsed = now.timeIntervalSince(state.lastRefill)
        let refillAmount = elapsed * bucket.refillRate
        return Int(min(Double(bucket.capacity), state.tokens + refillAmount))
    }

    /// Reset all buckets
    public func reset() {
        buckets.removeAll()
    }
}
