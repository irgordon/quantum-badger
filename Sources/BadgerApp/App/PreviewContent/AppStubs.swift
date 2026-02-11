import Foundation
import BadgerCore
import BadgerRuntime
import Combine

// MARK: - Services & Monitors

class LockdownService {
    init(auditLog: AuditLog, messagingGateway: MessagingXPCClient, webScoutService: WebScoutXPCClient, purgeLocalInference: @escaping () async -> Void) {}
    func initiateLockdown(reason: String) async {}
}

class MemoryPressureMonitor {
    func start() {}
    func stop() {}
}


// MARK: - XPC Clients

class MessagingXPCClient {
}

class WebScoutXPCClient {
    init(parsingPolicy: UntrustedParsingPolicyStore) {}
}

class UntrustedParsingXPCClient {
    init(policyStore: UntrustedParsingPolicyStore) {}
}

// MARK: - Policy Stores

@Observable class UntrustedParsingPolicyStore {}
@Observable class IdentityPolicyStore {}
@Observable class AuditRetentionPolicyStore { var retentionDays: Int = 30 }
@Observable class MessagingPolicyStore {}


@Observable class IntentProviderSelectionStore {
    var preferredSearchProviderId: String? = nil
}

// MARK: - Capability Stores

@Observable class SystemOperatorCapabilityStore {}

// MARK: - Runtime & Orchestration

class ToolRuntime {
    init(policy: PolicyEngine, auditLog: AuditLog, bookmarkStore: BookmarkStore, memoryManager: MemoryManager, vaultStore: VaultStore, untrustedParser: UntrustedParsingXPCClient, messagingAdapter: SharingMessagingAdapter, messagingPolicy: MessagingPolicyStore, networkClient: NetworkClient, webScoutService: WebScoutXPCClient, webFilterStore: WebFilterStore, systemActionAdapter: AppIntentBridgeAdapter, systemOperatorCapabilities: SystemOperatorCapabilityStore, toolLimitsStore: ToolLimitsStore, semanticRiskConfirmationHandler: @escaping (String, [String : String], String, Int) async -> Bool) {}
    
    func run(_ request: ToolRequest) async -> ToolResult {
        return ToolResult(id: request.id, toolName: request.toolName, output: ["status": "Stub run"], succeeded: true, finishedAt: Date())
    }
}

class NetworkClient {
    init(policy: NetworkPolicyStore, auditLog: AuditLog) {}
    func updateNetworkAvailability(_ available: Bool) {}
}

class DefaultModelRuntimeFactory: ModelRuntimeFactory {
    init(cloudKeyProvider: KeychainCloudKeyProvider, networkClient: NetworkClient) {}
}

protocol ModelRuntimeFactory {}

class KeychainCloudKeyProvider {}

class PairingCoordinator {}

// MARK: - Tool Registry & Catalog

class ToolRegistry {
    static let shared = ToolRegistry()
    func register(tool: ToolDefinition, handler: @escaping (ToolRequest) async throws -> String) {}
    func upsert(tool: ToolDefinition) {}
}

struct ToolDefinition: Sendable {
    let name: String
}

class ToolCatalog {
    static func hardenedSystemOperatorTool(systemOperatorCapabilities: SystemOperatorCapabilityStore) -> ToolDefinition {
        return ToolDefinition(name: "system.operator")
    }
}

class ToolDefinitionCatalog {
    static func analysisToolDefinition() -> ToolDefinition { ToolDefinition(name: "analysis") }
    static func draftToolDefinition() -> ToolDefinition { ToolDefinition(name: "draft") }
    static func securedToolSchemasJSON() -> String { "[]" }
}

enum ToolRegistryError: Error {
    case executionFailed(String, code: String?)
}

// MARK: - Adapters & Helpers



class AppIntentBridgeAdapter {
    init(capabilities: SystemOperatorCapabilityStore) {}
}

class FocusModeController {
    static let shared = FocusModeController()
    func configure(capabilities: SystemOperatorCapabilityStore) {}
}

class PendingMessageStore {
    static let shared = PendingMessageStore()
    func flush() async {}
}


class VectorMemoryStore {
    static let shared = VectorMemoryStore()
    func ingest(content: String, source: String) async {}
}

class SafeDecodingLog {
    static var auditLog: AuditLog?
}


class MemoryEntityProvider {
    static let shared = MemoryEntityProvider()
    enum Error: Swift.Error { case ownerUnavailable }
    func configure(fetcher: @escaping ([UUID]) async throws -> [MemoryRecord]) {}
}

class SecurityCenterCoordinator {
    static let shared = SecurityCenterCoordinator()
    func configure(open: @escaping () -> Void, runHealthCheck: @escaping () -> Void) {}
}

class AgentAutomationCoordinator {
    static let shared = AgentAutomationCoordinator()
    func configure(handlePrompt: @escaping (String) async -> Bool, startPlanning: @escaping (String) async -> Bool) {}
}

class WebScoutSearchProvider: IntentProvider {
    init(toolRuntime: ToolRuntime) {}
}

protocol IntentProvider {}

struct IntentSelectionContext {
    let isNetworkAvailable: Bool
    let enabledPurposes: Set<String> // Mock type
    let preferredSearchProviderId: String?
}

enum SystemActionError: Error {
    case executionFailed(String)
}

// Extensions for existing types to match new signatures

extension PolicyEngine {
    convenience init(auditLog: AuditLog, messagingPolicy: MessagingPolicyStore, systemOperatorCapabilities: SystemOperatorCapabilityStore) {
        self.init() // Assuming empty init exists or allows this
    }
}

extension MemoryManager {
    convenience init(modelContext: Any, auditLog: AuditLog) {
        self.init() // Mock
    }
    func fetchEntries(with ids: [UUID]) async throws -> [MemoryRecord] { return [] }
    func purgeExpired() {}
    func clearEphemeralCache() {}
    func flush() async {}
}

extension NetworkPolicyStore {
    var enabledPurposes: Set<String> { [] }
    var avoidAutoSwitchOnExpensive: Bool { true }
    func startExpirationMonitor() {}
}



extension MessagingInboxStore {
    var onPairingRequest: ((PairingRequest) -> Void)? { get { nil } set {} }
    var onLockdownRequest: ((String) -> Void)? { get { nil } set {} }
    func startPolling() {}
    func stopPolling() {}
}

struct PairingRequest {
    let displayName: String?
    let senderId: String
}

extension IdentityRecoveryManager {
    convenience init(auditLog: AuditLog) { self.init() }
    var isCloudSyncEnabled: Bool { false }
    func adoptCloudIdentityIfNeeded() async {}
    func syncIdentityToCloud() async -> Bool { return true }
}



extension ModelLoader {
    static var shared: ModelLoader!
    
    convenience init(modelRegistry: ModelRegistry, modelSelection: ModelSelectionStore, resourcePolicy: ResourcePolicyStore, factory: ModelRuntimeFactory) {
        self.init()
        Self.shared = self
    }
    
    func unloadActiveRuntime() async {
        // Mock unload logic for stub
        print("ModelLoader: Unloading active runtime due to pressure.")
        await MainActor.run {
             try? NotificationManager.shared.show(message: "Unloading model to keep your Mac snappy.", style: .memory)
        }
    }
}

extension HybridExecutionManager {
    convenience init(modelLoader: ModelLoader, policy: PolicyEngine, modelRegistry: ModelRegistry, modelSelection: ModelSelectionStore, resourcePolicy: ResourcePolicyStore, reachability: NetworkReachabilityMonitor, auditLog: AuditLog, toolRiskConfirmationHandler: Any) {
        self.init()
    }
}

extension AuditLog {
    func updatePayloadRetentionDays(_ days: Int) {}
    func flush() async {}
    func record(event: AuditEvent) {} // Already exists
    func export(to url: URL, option: ExportOptionsPrompt.Options) async -> Bool { return true }
}

extension AppIntentScanner {
    convenience init(capabilityStore: SystemOperatorCapabilityStore) { self.init() }
    var onToolDefinitionUpdated: ((ToolDefinition) -> Void)? { get { nil } set {} }
}

struct NetworkOpenCircuit: Identifiable {
    let id = UUID()
    let host: String
    let until: Date
}
