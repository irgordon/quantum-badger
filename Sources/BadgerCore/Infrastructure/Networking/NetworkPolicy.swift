import Foundation

/// Defines the purpose of a network request.
public enum NetworkPurpose: String, Sendable, Codable, CaseIterable {
    case tool           // External tool API calls
    case analytics      // Telemetry
    case update         // App updates
    case licensing      // License verification
    case modelDownload  // Downloading ML models
}

/// Policy configuration for a specific endpoint.
public struct NetworkEndpointPolicy: Sendable, Codable, Equatable {
    public let host: String
    public let requiredPurpose: NetworkPurpose
    public let allowedMethods: Set<String>
    public let allowedPathPrefixes: [String]
    public let allowRedirects: Bool
    public let requiresAppleTrust: Bool
    public let pinnedSPKIHashes: [String]
    public let maxResponseBytes: Int
    public let timeoutSeconds: TimeInterval
    
    public init(
        host: String,
        requiredPurpose: NetworkPurpose,
        allowedMethods: Set<String> = ["GET"],
        allowedPathPrefixes: [String] = ["/"],
        allowRedirects: Bool = false,
        requiresAppleTrust: Bool = false,
        pinnedSPKIHashes: [String] = [],
        maxResponseBytes: Int = 1_048_576,
        timeoutSeconds: TimeInterval = 30
    ) {
        // 🔒 SECURITY: Normalize host to lowercase to prevent case-sensitivity bypasses
        self.host = host.lowercased()
        self.requiredPurpose = requiredPurpose
        self.allowedMethods = allowedMethods
        self.allowedPathPrefixes = allowedPathPrefixes
        self.allowRedirects = allowRedirects
        self.requiresAppleTrust = requiresAppleTrust
        self.pinnedSPKIHashes = pinnedSPKIHashes
        self.maxResponseBytes = maxResponseBytes
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Store for network policies.
public actor NetworkPolicyStore {
    private var policies: [NetworkPurpose: Bool] = [
        .tool: true,
        .analytics: true,
        .update: true,
        .licensing: true,
        .modelDownload: true
    ]
    
    // ⚡️ PERFORMANCE: Changed from Array to Dictionary for O(1) lookup
    private var endpoints: [String: NetworkEndpointPolicy] = [:]
    
    public init(endpoints: [NetworkEndpointPolicy] = []) {
        for policy in endpoints {
            self.endpoints[policy.host] = policy
        }
    }
    
    public func isPurposeEnabled(_ purpose: NetworkPurpose) -> Bool {
        policies[purpose, default: false]
    }
    
    public func setPurposeEnabled(_ purpose: NetworkPurpose, enabled: Bool) {
        policies[purpose] = enabled
    }
    
    public func endpointsSnapshot() -> [NetworkEndpointPolicy] {
        // Return values sorted for consistent UI/Testing
        Array(endpoints.values).sorted { $0.host < $1.host }
    }
    
    public func addEndpoint(_ endpoint: NetworkEndpointPolicy) {
        // Dictionary automatically handles replacement/deduplication based on host key
        endpoints[endpoint.host] = endpoint
    }
    
    // Helper for direct lookup (saves scanning the snapshot)
    public func policy(forHost host: String) -> NetworkEndpointPolicy? {
        endpoints[host.lowercased()]
    }
}

public struct NetworkDecision: Sendable, CustomStringConvertible {
    public let purpose: NetworkPurpose
    public let host: String?
    public let endpoint: NetworkEndpointPolicy?
    public let reason: String
    
    public init(purpose: NetworkPurpose, host: String?, endpoint: NetworkEndpointPolicy?, reason: String) {
        self.purpose = purpose
        self.host = host
        self.endpoint = endpoint
        self.reason = reason
    }
    
    public var description: String {
        "Decision(\(purpose), host: \(host ?? "nil"), reason: \(reason))"
    }
}
