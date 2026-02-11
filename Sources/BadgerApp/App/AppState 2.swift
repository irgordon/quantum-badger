import Foundation
import Observation
import Network
import SwiftData
import Combine
import QuantumBadgerRuntime 
import BadgerCore

// MARK: - Sub-Models (State Separation)

@MainActor
@Observable
final class NavigationModel {
    var selection: NavigationSelection = .console
    var settingsSelection: SettingsSelection = .general
    var showPairingSheet: Bool = false
    var memoryDeepLinkId: UUID?
    var goalDeepLinkId: UUID?
    
    func navigateToMemory(_ id: UUID) {
        memoryDeepLinkId = id
        selection = .settings
        settingsSelection = .general 
    }
    
    func navigateToGoal(_ id: UUID) {
        goalDeepLinkId = id
        selection = .goals
    }
}

@MainActor
@Observable
final class UXFeedbackModel {
    var banner: BannerState?
    var memoryToast: MemoryToastState?
    
    func showBanner(message: String, isError: Bool = false, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        let bannerId = UUID()
        
        // Resolve default action for errors
        let finalActionTitle = (isError && actionTitle == nil) ? "Open Settings" : actionTitle
        
        self.banner = BannerState(
            id: bannerId,
            message: message,
            isError: isError,
            actionTitle: finalActionTitle,
            action: action
        )
        
        // Auto-dismiss after 2.5s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.banner?.id == bannerId {
                self.banner = nil
            }
        }
    }
    
    func showToast(_ message: String) {
        let toastId = UUID()
        self.memoryToast = MemoryToastState(id: toastId, message: message)
        
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.memoryToast?.id == toastId {
                self.memoryToast = nil
            }
        }
    }
}

// MARK: - App State (Root)

@MainActor
@Observable
final class AppState {
    // MARK: - Child Models
    let navigation = NavigationModel()
    let feedback = UXFeedbackModel()

    // MARK: - Core Status
    var isLockedDown: Bool = false
    var pendingExternalPrompt: String?
    
    // MARK: - Dependencies (The "Sovereign Assembly")
    // Note: These are 'let' constants. They don't need to be observed for changes usually.
    let reachability: NetworkReachabilityMonitor
    let securityCapabilities: SecurityCapabilities
    let modelCapabilities: ModelCapabilities
    let storageCapabilities: StorageCapabilities
    let runtimeCapabilities: RuntimeCapabilities
    
    // Policy & Stores
    let toolLimitsStore: ToolLimitsStore
    let messagingInboxStore: MessagingInboxStore
    let lockdownService: LockdownService
    let identityRecoveryManager: IdentityRecoveryManager
    let conversationHistoryStore: ConversationHistoryStore
    let executionRecoveryManager: ExecutionRecoveryManager
    let pairingCoordinator: PairingCoordinator
    let appIntentScanner: AppIntentScanner
    let systemOperatorCapabilities: SystemOperatorCapabilityStore
    
    // Additional Policies
    let identityPolicy: IdentityPolicyStore
    let untrustedParsingPolicy: UntrustedParsingPolicyStore
    let intentProviderSelection: IntentProviderSelectionStore
    let healthCheckStore: HealthCheckStore

    // Private Managers
    private let thermalWatcher: NPUThermalWatcher
    private let memoryPressureMonitor: MemoryPressureMonitor
    private var eventHandler: SystemEventHandler? // Now optional/set later to avoid init cycle issues

    // Tasks
    private var backgroundTasks: Set<Task<Void, Never>> = []
    private var didWarnInfoPlist: Bool = false
    
    // Computed Accessors for backward compatibility or convenience
    var webFilterStore: WebFilterStore { securityCapabilities.webFilterStore }
    var messagingPolicy: MessagingPolicyStore { securityCapabilities.messagingPolicy }
    var auditRetentionPolicy: AuditRetentionPolicyStore { storageCapabilities.auditRetentionPolicy }
    var openCircuitsStore: OpenCircuitsStore { runtimeCapabilities.networkClient.openCircuitsStore }

    // MARK: - Initialization
    init(modelContext: ModelContext) {
        // 1. Build the graph
        let dependencies = AppDependencyFactory.buildDependencies(modelContext: modelContext)
        
        // 2. Assign Dependencies
        self.reachability = dependencies.reachability
        self.securityCapabilities = dependencies.securityCapabilities
        self.modelCapabilities = dependencies.modelCapabilities
        self.storageCapabilities = dependencies.storageCapabilities
        self.runtimeCapabilities = dependencies.runtimeCapabilities
        self.toolLimitsStore = dependencies.toolLimitsStore
        self.messagingInboxStore = dependencies.messagingInboxStore
        self.identityRecoveryManager = dependencies.identityRecoveryManager
        self.thermalWatcher = dependencies.thermalWatcher
        self.memoryPressureMonitor = dependencies.memoryPressureMonitor
        self.conversationHistoryStore = dependencies.conversationHistoryStore
        self.executionRecoveryManager = dependencies.executionRecoveryManager
        self.pairingCoordinator = dependencies.pairingCoordinator
        self.appIntentScanner = dependencies.appIntentScanner
        self.systemOperatorCapabilities = dependencies.systemOperatorCapabilities
        self.identityPolicy = dependencies.identityPolicy
        self.untrustedParsingPolicy = dependencies.untrustedParsingPolicy
        self.intentProviderSelection = dependencies.intentProviderSelection
        self.healthCheckStore = dependencies.healthCheckStore
        
        // 3. Init Services
        self.lockdownService = LockdownService(
            auditLog: dependencies.storageCapabilities.auditLog,
            messagingGateway: dependencies.messagingGateway,
            webScoutService: dependencies.webScoutClient,
            purgeLocalInference: {
                await LocalMLXInference.shared.purgeContext()
            }
        )

        // 4. Configure Global Singletons/Coordinators
        // 4. Configure Global Singletons/Coordinators
        self.configureCoordinators(
            runtime: dependencies.runtimeCapabilities,
            scanner: dependencies.appIntentScanner,
            audit: dependencies.storageCapabilities.auditLog
        )
        
        // 5. Setup Event Handler (Break cycle)
        self.eventHandler = SystemEventHandler(appState: self)
    }
    
    private func configureCoordinators(runtime: RuntimeCapabilities, scanner: AppIntentScanner, audit: AuditLog) {
        // ... (ToolRegistry config stub if needed, but omitted in snippet)
        
        SecurityCenterCoordinator.shared.configure(
            open: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.navigation.selection = .settings
                    self.navigation.settingsSelection = .security
                }
            },
            runHealthCheck: { [weak self] in
                guard let self else { return }
                Task {
                    await self.healthCheckStore.run(auditLog: audit)
                }
            }
        )
        
        AgentAutomationCoordinator.shared.configure(
            handlePrompt: { [weak self] text in
                guard let self else { return false }
                self.pendingExternalPrompt = text
                self.navigation.selection = .console
                return true
            },
            startPlanning: { [weak self] goal in
                guard let self else { return false }
                return await self.startPlanning(goal: goal)
            }
        )
    }
    
    private func startPlanning(goal: String) async -> Bool {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // 1. Generate the Plan
        let plan = await runtimeCapabilities.orchestrator.proposePlan(for: trimmed)
        
        // 2. Start Execution Recovery tracking
        executionRecoveryManager.startGoal(plan.intent, plan: plan.steps)
        
        // 3. Persist to TaskPlanner (The "Database")
        let goalID = await TaskPlanner.shared.upsertGoal(
            planID: plan.id,
            title: plan.intent.isEmpty ? "Untitled Goal" : plan.intent,
            sourceIntent: plan.intent,
            totalSteps: max(1, plan.steps.count),
            completedSteps: 0,
            failedSteps: 0
        )
        
        // 4. Navigate
        await MainActor.run {
            self.feedback.showBanner(message: "Planning started for \"\(trimmed)\".")
            self.navigation.navigateToGoal(plan.id) 
        }
        
        return true
    }

    // MARK: - Lifecycle
    
    func start() {
        // 1. Hardware Monitors
        thermalWatcher.start()
        memoryPressureMonitor.start()
        reachability.start()
        
        // 2. Capability Warming
        Task { await runtimeCapabilities.orchestrator.warmUpIfPossible() }
        
        // 3. Network Monitoring
        let networkTask = Task { [weak self] in
            guard let self else { return }
            for await path in self.reachabilityStatusStream() {
                self.handleReachabilityChange(path)
            }
        }
        backgroundTasks.insert(networkTask)
        
        // 4. System Event Bus
        let eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in SystemEventBus.shared.stream() {
                self.eventHandler?.handle(event)
            }
        }
        backgroundTasks.insert(eventTask)
        
        // 5. Identity & Security (Detached to unblock Main Thread)
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.identityRecoveryManager.adoptCloudIdentityIfNeeded()
            
            // Ingest Goals into Vector Store (Heavy Lifting)
            let goals = await TaskPlanner.shared.allGoals()
            await SystemSearchDonationManager.donate(goals: goals)
            
            for goal in goals where goal.status != .active {
                await VectorMemoryStore.shared.ingest(
                    content: "Goal '\(goal.title)' is \(goal.status.rawValue). Intent: \(goal.sourceIntent)",
                    source: "Goal: \(goal.title)"
                )
            }
        }

        setupCallbacks()
    }
    
    func stop() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        messagingInboxStore.stopPolling()
        thermalWatcher.stop()
        memoryPressureMonitor.stop()
    }

    // MARK: - Logic Handlers
    
    private func setupCallbacks() {
        messagingInboxStore.onPairingRequest = { [weak self] request in
            guard let self else { return }
            self.feedback.showBanner(
                message: "Pairing request from \(request.displayName ?? "Unknown").",
                actionTitle: "Review"
            ) {
                self.navigation.selection = .settings
                self.navigation.showPairingSheet = true
            }
        }
        
        messagingInboxStore.onLockdownRequest = { [weak self] reason in
            guard let self else { return }
            Task {
                await self.lockdownService.initiateLockdown(reason: reason)
                self.isLockedDown = true
                self.feedback.showBanner(message: "Emergency lockdown enabled.", isError: true)
            }
        }
    }

    private func handleReachabilityChange(_ path: NWPath) {
        runtimeCapabilities.networkClient.updateNetworkAvailability(path.status == .satisfied)
        
        if path.status != .satisfied {
            feedback.showBanner(message: "Offline. Switched to local mode.", isError: true)
            // Logic to switch model ID should be in ModelSelectionStore, not here
        }
    }

    func exportAuditLog(to url: URL, encrypted: Bool) async {
         let succeeded = await storageCapabilities.auditLog.export(
            to: url, 
            option: encrypted ? .encrypted : .plainJSON
         )
         if succeeded {
             feedback.showBanner(message: "Audit log exported.")
         } else {
             feedback.showBanner(message: "Export failed.", isError: true)
         }
    }
    
    // Stub
    private func reachabilityStatusStream() -> AsyncStream<NWPath> { AsyncStream { _ in } }
}
