import Foundation
import Observation

enum NetworkPurpose: String, CaseIterable, Codable, Identifiable {
    case webContentRetrieval
    case cloudInference
    case sdkAuthentication
    case sdkTelemetry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .webContentRetrieval: return "Web content"
        case .cloudInference: return "Online model services"
        case .sdkAuthentication: return "Sign-in and authentication"
        case .sdkTelemetry: return "Diagnostics and updates"
        }
    }
}

struct NetworkEndpointPolicy: Codable, Hashable {
    var host: String
    var allowedMethods: [String]
    var allowedPathPrefixes: [String]
    var allowRedirects: Bool
    var requiresAppleTrust: Bool
    var pinnedSPKIHashes: [String]
    var timeoutSeconds: TimeInterval
    var maxResponseBytes: Int
    var requiredPurpose: NetworkPurpose

    init(
        host: String,
        allowedMethods: [String] = ["GET"],
        allowedPathPrefixes: [String] = ["/"],
        allowRedirects: Bool = false,
        requiresAppleTrust: Bool = false,
        pinnedSPKIHashes: [String] = [],
        timeoutSeconds: TimeInterval = 15,
        maxResponseBytes: Int = 5_000_000,
        requiredPurpose: NetworkPurpose = .webContentRetrieval
    ) {
        self.host = host.lowercased()
        self.allowedMethods = allowedMethods
        self.allowedPathPrefixes = allowedPathPrefixes
        self.allowRedirects = allowRedirects
        self.requiresAppleTrust = requiresAppleTrust
        self.pinnedSPKIHashes = pinnedSPKIHashes
        self.timeoutSeconds = timeoutSeconds
        self.maxResponseBytes = maxResponseBytes
        self.requiredPurpose = requiredPurpose
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case allowedMethods
        case allowedPathPrefixes
        case allowRedirects
        case requiresAppleTrust
        case pinnedSPKIHashes
        case timeoutSeconds
        case maxResponseBytes
        case requiredPurpose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host).lowercased()
        allowedMethods = try container.decodeIfPresent([String].self, forKey: .allowedMethods) ?? ["GET"]
        allowedPathPrefixes = try container.decodeIfPresent([String].self, forKey: .allowedPathPrefixes) ?? ["/"]
        allowRedirects = try container.decodeIfPresent(Bool.self, forKey: .allowRedirects) ?? false
        requiresAppleTrust = try container.decodeIfPresent(Bool.self, forKey: .requiresAppleTrust) ?? false
        pinnedSPKIHashes = try container.decodeIfPresent([String].self, forKey: .pinnedSPKIHashes) ?? []
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds) ?? 15
        maxResponseBytes = try container.decodeIfPresent(Int.self, forKey: .maxResponseBytes) ?? 5_000_000
        requiredPurpose = try container.decodeIfPresent(NetworkPurpose.self, forKey: .requiredPurpose) ?? .webContentRetrieval
    }
}

@MainActor
@Observable
final class NetworkPolicyStore {
    private(set) var enabledPurposes: Set<NetworkPurpose>
    private(set) var endpoints: [NetworkEndpointPolicy]
    private(set) var defaultSessionMinutes: Int
    private(set) var avoidAutoSwitchOnExpensive: Bool
    private var purposeExpirations: [NetworkPurpose: Date]
    private let storageURL: URL
    private let auditLog: AuditLog?

    init(
        storageURL: URL = AppPaths.networkPolicyURL,
        enabledPurposes: Set<NetworkPurpose> = [],
        endpoints: [NetworkEndpointPolicy] = [],
        defaultSessionMinutes: Int = 10,
        avoidAutoSwitchOnExpensive: Bool = false,
        auditLog: AuditLog? = nil
    ) {
        self.storageURL = storageURL
        self.auditLog = auditLog

        let defaults = PolicySnapshot(
            enabledPurposes: enabledPurposes,
            endpoints: endpoints,
            defaultSessionMinutes: defaultSessionMinutes,
            avoidAutoSwitchOnExpensive: avoidAutoSwitchOnExpensive
        )
        let snapshot = JSONStore.load(PolicySnapshot.self, from: storageURL, defaultValue: defaults)

        let migrated = Self.migrate(snapshot)
        self.enabledPurposes = migrated.enabledPurposes
        self.endpoints = migrated.endpoints
        self.defaultSessionMinutes = migrated.defaultSessionMinutes
        self.avoidAutoSwitchOnExpensive = migrated.avoidAutoSwitchOnExpensive
        self.purposeExpirations = [:]
    }

    func setPurpose(_ purpose: NetworkPurpose, enabled: Bool) {
        if enabled {
            enabledPurposes.insert(purpose)
        } else {
            enabledPurposes.remove(purpose)
            purposeExpirations[purpose] = nil
        }
        persist()
    }

    func enablePurpose(_ purpose: NetworkPurpose, for minutes: Int) {
        let clampedMinutes = max(1, min(minutes, 180))
        enabledPurposes.insert(purpose)
        purposeExpirations[purpose] = Date().addingTimeInterval(TimeInterval(clampedMinutes * 60))
        persist()
    }

    func isPurposeEnabled(_ purpose: NetworkPurpose) -> Bool {
        if let expiration = purposeExpirations[purpose], expiration <= Date() {
            enabledPurposes.remove(purpose)
            purposeExpirations[purpose] = nil
            return false
        }
        return enabledPurposes.contains(purpose)
    }

    func setEndpoints(_ endpoints: [NetworkEndpointPolicy]) {
        self.endpoints = endpoints
        persist()
    }

    func setDefaultSessionMinutes(_ minutes: Int) {
        defaultSessionMinutes = max(1, min(minutes, 180))
        persist()
    }

    func setAvoidAutoSwitchOnExpensive(_ value: Bool) {
        avoidAutoSwitchOnExpensive = value
        persist()
    }

    func endpointsSnapshot() -> [NetworkEndpointPolicy] {
        endpoints
    }

    func startExpirationMonitor() {
        // No-op: expiration is evaluated on demand in isPurposeEnabled.
    }

    private func persist() {
        let snapshot = PolicySnapshot(
            enabledPurposes: enabledPurposes,
            endpoints: endpoints,
            defaultSessionMinutes: defaultSessionMinutes
        )
        do {
            try JSONStore.save(snapshot, to: storageURL)
        } catch {
            AppLogger.storage.error("Failed to persist network policy: \(error.localizedDescription, privacy: .private)")
        }
    }

    private struct PolicySnapshot: Codable {
        var enabledPurposes: Set<NetworkPurpose>
        var endpoints: [NetworkEndpointPolicy]
        var defaultSessionMinutes: Int
        var avoidAutoSwitchOnExpensive: Bool

        init(
            enabledPurposes: Set<NetworkPurpose>,
            endpoints: [NetworkEndpointPolicy],
            defaultSessionMinutes: Int,
            avoidAutoSwitchOnExpensive: Bool
        ) {
            self.enabledPurposes = enabledPurposes
            self.endpoints = endpoints
            self.defaultSessionMinutes = defaultSessionMinutes
            self.avoidAutoSwitchOnExpensive = avoidAutoSwitchOnExpensive
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabledPurposes = try container.decode(Set<NetworkPurpose>.self, forKey: .enabledPurposes)
            endpoints = try container.decode([NetworkEndpointPolicy].self, forKey: .endpoints)
            defaultSessionMinutes = try container.decode(Int.self, forKey: .defaultSessionMinutes)
            avoidAutoSwitchOnExpensive = try container.decodeIfPresent(Bool.self, forKey: .avoidAutoSwitchOnExpensive) ?? false
        }
    }

    private static func migrate(_ snapshot: PolicySnapshot) -> PolicySnapshot {
        let inferredPurpose = snapshot.enabledPurposes.first ?? .webContentRetrieval
        let endpoints = snapshot.endpoints.map { endpoint in
            var updated = endpoint
            if updated.requiredPurpose == .webContentRetrieval && snapshot.enabledPurposes.count > 0 {
                updated.requiredPurpose = inferredPurpose
            }
            return updated
        }
        return PolicySnapshot(
            enabledPurposes: snapshot.enabledPurposes,
            endpoints: endpoints,
            defaultSessionMinutes: snapshot.defaultSessionMinutes,
            avoidAutoSwitchOnExpensive: snapshot.avoidAutoSwitchOnExpensive
        )
    }
}
