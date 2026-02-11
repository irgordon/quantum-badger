import Foundation
import SwiftData
import Network
import BadgerCore
import QuantumBadgerRuntime // ✅ Removed duplicate 'BadgerRuntime'

// MARK: - Capability Grouping

struct SecurityCapabilities {
    let policy: PolicyEngine
    let networkPolicy: NetworkPolicyStore
    let toolApprovalManager: ToolApprovalManager
    let messagingPolicy: MessagingPolicyStore
    let webFilterStore: WebFilterStore
    let toolLimitsStore: ToolLimitsStore
    // Added SystemOperator to Security, as it manages high-risk entitlements
    let systemOperator: SystemOperatorCapabilityStore 
    let healthCheckStore: HealthCheckStore
}

struct ModelCapabilities {
    let catalog: ModelCatalog // Renamed from modelRegistry for clarity
    let selectionStore: ModelSelectionStore
    let resourcePolicy: ResourcePolicyStore
    let modelLoader: ModelLoader
}

struct StorageCapabilities {
    let vaultStore: VaultStore
    let auditLog: AuditLog
    let memoryManager: MemoryManager
    let bookmarkStore: BookmarkStore
    let auditRetentionPolicy: AuditRetentionPolicyStore
}

struct RuntimeCapabilities {
    let orchestrator: Orchestrator
    let toolRuntime: ToolRuntime
    let networkClient: NetworkClient
    // Added these to Runtime to support Coordinators
    let pairingCoordinator: PairingCoordinator
    let appIntentScanner: AppIntentScanner
    let intentProviderSelection: IntentProviderSelectionStore
}

// MARK: - Dependency Bundle (The Transfer Object)

struct AppDependencyBundle {
    // Infrastructure
    let reachability: NetworkReachabilityMonitor
    
    // Capability Groups
    let securityCapabilities: SecurityCapabilities
    let modelCapabilities: ModelCapabilities
    let storageCapabilities: StorageCapabilities
    let runtimeCapabilities: RuntimeCapabilities
    
    // Top-Level Policies (For AppState direct access)
    let untrustedParsingPolicy: UntrustedParsingPolicyStore
    let identityPolicy: IdentityPolicyStore
    let messagingInboxStore: MessagingInboxStore
    let identityRecoveryManager: IdentityRecoveryManager
    let conversationHistoryStore: ConversationHistoryStore
    let executionRecoveryManager: ExecutionRecoveryManager
    
    // Hardware Monitors
    let thermalWatcher: NPUThermalWatcher
    let memoryPressureMonitor: MemoryPressureMonitor
    
    // XPC Clients (For LockdownService)
    let messagingGateway: MessagingXPCClient
    let webScoutClient: WebScoutXPCClient
}

// MARK: - The Factory

enum AppDependencyFactory {
    @MainActor
    static func buildDependencies(modelContext: ModelContext) -> AppDependencyBundle {
        // 1. Foundation (Logs & Network)
        let auditLog = AuditLog()
        configureSharedAuditSinks(auditLog)
        
        let networkPolicy = NetworkPolicyStore(auditLog: auditLog)
        let networkClient = NetworkClient(policy: networkPolicy, auditLog: auditLog)
        let reachability = NetworkReachabilityMonitor()
        
        // 2. Storage & Policies
        let bookmarkStore = BookmarkStore()
        let vaultStore = VaultStore()
        let resourcePolicy = ResourcePolicyStore()
        let messagingPolicy = MessagingPolicyStore()
        let webFilterStore = WebFilterStore()
        let toolLimitsStore = ToolLimitsStore()
        let identityPolicy = IdentityPolicyStore()
        let auditRetentionPolicy = AuditRetentionPolicyStore()
        let untrustedParsingPolicy = UntrustedParsingPolicyStore()
        let healthCheckStore = HealthCheckStore()
        let intentProviderSelection = IntentProviderSelectionStore()
        
        // 3. Managers & Controllers
        let identityRecoveryManager = IdentityRecoveryManager(auditLog: auditLog)
        let thermalWatcher = NPUThermalWatcher.shared
        let memoryPressureMonitor = MemoryPressureMonitor()
        let memoryManager = MemoryManager(modelContext: modelContext, auditLog: auditLog)
        let conversationHistoryStore = ConversationHistoryStore(memoryController: MemoryController())
        let systemOperatorCapabilities = SystemOperatorCapabilityStore()
        let executionRecoveryManager = ExecutionRecoveryManager()
        
        // 4. Scanners & Coordinators
        let appIntentScanner = AppIntentScanner(capabilityStore: systemOperatorCapabilities)
        let pairingCoordinator = PairingCoordinator()
        let toolApprovalManager = ToolApprovalManager()
        let messagingInboxStore = MessagingInboxStore()

        // 5. Config
        FocusModeController.shared.configure(capabilities: systemOperatorCapabilities)

        // 6. The Engines (Logic Layer)
        let policy = PolicyEngine(
            auditLog: auditLog,
            messagingPolicy: messagingPolicy,
            systemOperatorCapabilities: systemOperatorCapabilities
        )
        
        // XPC Clients
        let webScoutClient = WebScoutXPCClient(parsingPolicy: untrustedParsingPolicy)
        let messagingGateway = MessagingXPCClient()
        let untrustedParser = UntrustedParsingXPCClient(policyStore: untrustedParsingPolicy)

        // Tool Runtime (The Hands)
        let toolRuntime = ToolRuntime(
            policy: policy,
            auditLog: auditLog,
            bookmarkStore: bookmarkStore,
            memoryManager: memoryManager,
            vaultStore: vaultStore,
            untrustedParser: untrustedParser,
            messagingAdapter: SharingMessagingAdapter(),
            messagingPolicy: messagingPolicy,
            networkClient: networkClient,
            webScoutService: webScoutClient,
            webFilterStore: webFilterStore,
            systemActionAdapter: AppIntentBridgeAdapter(capabilities: systemOperatorCapabilities),
            systemOperatorCapabilities: systemOperatorCapabilities,
            toolLimitsStore: toolLimitsStore,
            // ⚠️ SECURITY NOTE: This handler is temporarily permissive for the factory build.
            // The Orchestrator should ideally hook into AppState.feedback later for real UI prompts.
            semanticRiskConfirmationHandler: { _,_,_,_ in return true }
        )
        
        // Models (The Brain)
        let modelCatalog = ModelCatalog()
        let modelSelection = ModelSelectionStore()
        let modelRegistry = ModelRegistry(catalog: modelCatalog)
        
        let modelLoader = ModelLoader(
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            factory: DefaultModelRuntimeFactory(
                cloudKeyProvider: KeychainCloudKeyProvider(),
                networkClient: networkClient
            )
        )
        
        // Execution & Orchestration
        let executionManager = HybridExecutionManager(
            modelLoader: modelLoader,
            policy: policy,
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            reachability: reachability,
            auditLog: auditLog,
            toolRiskConfirmationHandler: { _,_,_,_ in return true } // TODO: Wire to UI
        )
        
        let orchestrator = Orchestrator(
            toolRuntime: toolRuntime,
            auditLog: auditLog,
            policy: policy,
            vaultStore: vaultStore,
            reachability: reachability,
            messagingPolicy: messagingPolicy,
            executionManager: executionManager
        )
        
        // 7. Post-Init Configuration
        configureToolRegistry(
            toolRuntime: toolRuntime,
            appIntentScanner: appIntentScanner,
            systemOperatorCapabilities: systemOperatorCapabilities,
            auditLog: auditLog
        )

        // 8. Bundle Assembly
        return AppDependencyBundle(
            reachability: reachability,
            securityCapabilities: SecurityCapabilities(
                policy: policy,
                networkPolicy: networkPolicy,
                toolApprovalManager: toolApprovalManager,
                messagingPolicy: messagingPolicy,
                webFilterStore: webFilterStore,
                toolLimitsStore: toolLimitsStore,
                systemOperator: systemOperatorCapabilities,
                healthCheckStore: healthCheckStore
            ),
            modelCapabilities: ModelCapabilities(
                catalog: modelRegistry, // Mapping ModelRegistry to 'catalog'
                selectionStore: modelSelection,
                resourcePolicy: resourcePolicy,
                modelLoader: modelLoader
            ),
            storageCapabilities: StorageCapabilities(
                vaultStore: vaultStore,
                auditLog: auditLog,
                memoryManager: memoryManager,
                bookmarkStore: bookmarkStore,
                auditRetentionPolicy: auditRetentionPolicy
            ),
            runtimeCapabilities: RuntimeCapabilities(
                orchestrator: orchestrator,
                toolRuntime: toolRuntime,
                networkClient: networkClient,
                pairingCoordinator: pairingCoordinator,
                appIntentScanner: appIntentScanner,
                intentProviderSelection: intentProviderSelection
            ),
            untrustedParsingPolicy: untrustedParsingPolicy,
            identityPolicy: identityPolicy,
            messagingInboxStore: messagingInboxStore,
            identityRecoveryManager: identityRecoveryManager,
            conversationHistoryStore: conversationHistoryStore,
            executionRecoveryManager: executionRecoveryManager,
            thermalWatcher: thermalWatcher,
            memoryPressureMonitor: memoryPressureMonitor,
            messagingGateway: messagingGateway,
            webScoutClient: webScoutClient
        )
    }
    
    private static func configureSharedAuditSinks(_ auditLog: AuditLog) {
        SafeDecodingLog.auditLog = auditLog
        OutboundPrivacyFilter.auditLog = auditLog
    }
    
    @MainActor
    private static func configureToolRegistry(
        toolRuntime: ToolRuntime,
        appIntentScanner: AppIntentScanner,
        systemOperatorCapabilities: SystemOperatorCapabilityStore,
        auditLog: AuditLog
    ) {
        // In a real app, this would register dynamic tools.
        // For now, we stub the registration of the system operator tool.
        let _ = ToolCatalog.hardenedSystemOperatorTool(
            systemOperatorCapabilities: systemOperatorCapabilities
        )
    }
}
