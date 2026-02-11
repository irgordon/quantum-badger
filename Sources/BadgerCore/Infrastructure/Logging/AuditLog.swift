import Foundation

/// Immutable audit log for system events.
public actor AuditLog {
    public init() {}
    
    public func record(event: AuditEvent) {
        // In a real implementation, this would write to an append-only file or SQLite DB.
        // For now, we print to console for debugging.
        print("📝 [AUDIT] \(event)")
    }
    
    public func recordNetworkPayloadRedaction(decision: NetworkDecision, before: Data, after: Data) {
        print("📝 [AUDIT] Redacted payload for \(decision.host ?? "unknown"). Size: \(before.count) -> \(after.count)")
    }
}

public enum AuditEvent: Sendable, CustomStringConvertible {
    case networkAttempt(decision: NetworkDecision, allowed: Bool, reason: String? = nil)
    case networkCircuitTripped(host: String, cooldownSeconds: Int)
    case networkRedirectBlocked(host: String)
    case networkResponseTruncated(host: String, reason: String)
    case securityViolationDetected(String)
    
    public var description: String {
        switch self {
        case .networkAttempt(let decision, let allowed, let reason):
            return "Network Attempt: \(decision.purpose) -> \(decision.host ?? "nil") [\(allowed ? "ALLOWED" : "DENIED")] \(reason ?? "")"
        case .networkCircuitTripped(let host, let cooldown):
            return "Circuit Tripped: \(host) (Cooldown: \(cooldown)s)"
        case .networkRedirectBlocked(let host):
            return "Redirect Blocked: \(host)"
        case .networkResponseTruncated(let host, let reason):
            return "Response Truncated: \(host) (\(reason))"
        case .securityViolationDetected(let reason):
            return "Security Violation: \(reason)"
        }
    }
}

// NetworkDecision needs to be available to AuditEvent.
// It is defined in NetworkClient.swift in the User Snippet.
// I can define it here or forward declare?
// I'll put it in a separate file or `NetworkTypes.swift` if needed,
// but usually `NetworkClient.swift` will contain it. 
// However, AuditLog needs it. So I should extract `NetworkDecision` to `NetworkPolicy.swift` or similar shared file.
// I'll add `NetworkDecision` to `NetworkPolicy.swift`.
