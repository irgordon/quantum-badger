import Foundation

/// Token‑bucket rate limiter for remote command channels.
///
/// Each channel gets an independent bucket. Tokens refill at a
/// configurable rate. Actor isolation guarantees thread‑safe
/// token accounting.
public actor RateLimiter {

    // MARK: - Configuration

    /// Maximum tokens per bucket.
    private let maxTokens: Int

    /// Tokens added per refill interval.
    private let refillAmount: Int

    /// Refill interval in nanoseconds.
    private let refillIntervalNanoseconds: UInt64

    // MARK: - State

    /// Current token count per channel.
    private var buckets: [RemoteChannel: Int] = [:]

    /// Last refill timestamp per channel.
    private var lastRefill: [RemoteChannel: ContinuousClock.Instant] = [:]

    // MARK: - Init

    /// - Parameters:
    ///   - maxTokens: Maximum tokens per bucket. Default **10**.
    ///   - refillAmount: Tokens added per interval. Default **1**.
    ///   - refillIntervalSeconds: Seconds between refills. Default **6** (10 per minute).
    public init(
        maxTokens: Int = 10,
        refillAmount: Int = 1,
        refillIntervalSeconds: UInt64 = 6
    ) {
        self.maxTokens = maxTokens
        self.refillAmount = refillAmount
        self.refillIntervalNanoseconds = refillIntervalSeconds * 1_000_000_000
    }

    // MARK: - Public API

    /// Attempt to consume a token for the given channel.
    ///
    /// - Returns: `true` if the request is allowed, `false` if rate‑limited.
    public func tryConsume(channel: RemoteChannel) -> Bool {
        refill(channel: channel)

        let current = buckets[channel, default: maxTokens]
        if current > 0 {
            buckets[channel] = current - 1
            return true
        }
        return false
    }

    /// Check remaining tokens without consuming.
    public func remainingTokens(channel: RemoteChannel) -> Int {
        refill(channel: channel)
        return buckets[channel, default: maxTokens]
    }

    // MARK: - Refill Logic

    private func refill(channel: RemoteChannel) {
        let now = ContinuousClock.now
        let last = lastRefill[channel] ?? now
        let elapsed = now - last

        let elapsedNanos = UInt64(elapsed.components.seconds) * 1_000_000_000
            + UInt64(elapsed.components.attoseconds / 1_000_000_000)

        let intervals = Int(elapsedNanos / refillIntervalNanoseconds)
        if intervals > 0 {
            let current = buckets[channel, default: maxTokens]
            buckets[channel] = min(maxTokens, current + intervals * refillAmount)
            lastRefill[channel] = now
        }

        if lastRefill[channel] == nil {
            lastRefill[channel] = now
        }
    }
}
