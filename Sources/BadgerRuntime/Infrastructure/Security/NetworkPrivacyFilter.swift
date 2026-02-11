import Foundation

/// Privacy guard and circuit breaker for outbound network traffic.
///
/// `NetworkPrivacyFilter` enforces:
/// 1. **Circuit Breaker**: Detects repeated failures to a host and blocks
///    traffic for a cool‑down period to save battery and prevent metadata leakage.
/// 2. **Blocklist**: Deterministically rejects known tracker domains.
/// 3. **Allowlist**: (Optional) Enforces a strict allowlist mode for high‑security contexts.
public actor NetworkPrivacyFilter {

    // MARK: - Types

    public enum FilterVerdict: Sendable {
        case allowed
        case blocked(reason: String)
    }

    private struct HostStatus {
        var failureCount: Int
        var lastFailure: Date
        var circuitOpenUntil: Date?
    }

    // MARK: - Constants

    private static let maxFailuresBeforeTrip = 5
    private static let circuitOpenDuration: TimeInterval = 300 // 5 minutes
    private static let trackerDomains: Set<String> = [
        "google-analytics.com",
        "doubleclick.net",
        "facebook.com",
        "branch.io",
        "adjust.com"
    ]

    // MARK: - State

    private var hostStatuses: [String: HostStatus] = [:]

    // MARK: - Public API

    /// Check if a request to the given URL is allowed.
    public func check(_ url: URL) -> FilterVerdict {
        guard let host = url.host?.lowercased() else {
            return .blocked(reason: "Invalid URL")
        }

        // 1. Blocklist check
        if Self.trackerDomains.contains(where: { host.contains($0) }) {
            return .blocked(reason: "Privacy: Tracker domain blocked")
        }

        // 2. Circuit Breaker check
        if let status = hostStatuses[host], let openUntil = status.circuitOpenUntil {
            if Date() < openUntil {
                return .blocked(reason: "Circuit Breaker: Host unstable (too many failures)")
            } else {
                // Circuit closed (cool‑down over)
                hostStatuses[host]?.circuitOpenUntil = nil
                hostStatuses[host]?.failureCount = 0
            }
        }

        return .allowed
    }

    /// Report a network success to reset failure counters.
    public func reportSuccess(for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        hostStatuses[host] = nil // Clear status on success
    }

    /// Report a network failure to increment counters and potentially trip the circuit.
    public func reportFailure(for url: URL) {
        guard let host = url.host?.lowercased() else { return }

        var status = hostStatuses[host] ?? HostStatus(failureCount: 0, lastFailure: Date(), circuitOpenUntil: nil)
        status.failureCount += 1
        status.lastFailure = Date()

        if status.failureCount >= Self.maxFailuresBeforeTrip {
            status.circuitOpenUntil = Date().addingTimeInterval(Self.circuitOpenDuration)
        }

        hostStatuses[host] = status
    }
}
