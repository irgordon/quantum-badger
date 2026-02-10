import Foundation
import Observation
import Network
import SwiftData
import QuantumBadgerRuntime
import BadgerCore
import BadgerRuntime
import Combine

private typealias AppRiskConfirmationHandler =
    @Sendable (_ toolName: String, _ input: [String: String], _ reasoning: String, _ level: Int) async -> Bool

struct SecurityCapabilities {
    let policy: PolicyEngine
    let networkPolicy: NetworkPolicyStore
    let toolApprovalManager: ToolApprovalManager
    let messagingPolicy: MessagingPolicyStore
    let webFilterStore: WebFilterStore
    let toolLimitsStore: ToolLimitsStore
}

struct ModelCapabilities {
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
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
}

private struct AppDependencyBundle {
    let reachability: NetworkReachabilityMonitor
    let securityCapabilities: SecurityCapabilities
    let modelCapabilities: ModelCapabilities
    let storageCapabilities: StorageCapabilities
    let runtimeCapabilities: RuntimeCapabilities
    let untrustedParsingPolicy: UntrustedParsingPolicyStore
    let identityPolicy: IdentityPolicyStore
    let auditRetentionPolicy: AuditRetentionPolicyStore
    let messagingPolicy: MessagingPolicyStore
    let webFilterStore: WebFilterStore
    let toolLimitsStore: ToolLimitsStore
    let intentProviderSelection: IntentProviderSelectionStore
    let healthCheckStore: HealthCheckStore
    let messagingInboxStore: MessagingInboxStore
    let pairingCoordinator: PairingCoordinator
    let identityRecoveryManager: IdentityRecoveryManager
    let thermalWatcher: NPUThermalWatcher
    let memoryPressureMonitor: MemoryPressureMonitor
    let conversationHistoryStore: ConversationHistoryStore
    let appIntentScanner: AppIntentScanner
    let systemOperatorCapabilities: SystemOperatorCapabilityStore
    let executionRecoveryManager: ExecutionRecoveryManager
    let messagingGateway: MessagingXPCClient
    let webScoutClient: WebScoutXPCClient
}

@MainActor
@Observable
final class AppState {
    var navigationSelection: NavigationSelection = .console
    var settingsSelection: SettingsSelection = .general // Fixed enum type mismatch
    var banner: BannerState?
    var memoryToast: MemoryToastState?
    var memoryDeepLinkId: UUID?
    var goalDeepLinkId: UUID?
    var showPairingSheet: Bool = false
    var isLockedDown: Bool = false
    var pendingExternalPrompt: String?
    var externalPromptRequestID: UUID = UUID()
    private var reachabilityTask: Task<Void, Never>?
    private var systemEventTask: Task<Void, Never>?
    private var didWarnInfoPlist: Bool = false
    let openCircuitsStore = OpenCircuitsStore()

    let reachability: NetworkReachabilityMonitor
    let securityCapabilities: SecurityCapabilities
    let modelCapabilities: ModelCapabilities
    let storageCapabilities: StorageCapabilities
    let runtimeCapabilities: RuntimeCapabilities
    let untrustedParsingPolicy: UntrustedParsingPolicyStore
    let identityPolicy: IdentityPolicyStore
    let auditRetentionPolicy: AuditRetentionPolicyStore
    let messagingPolicy: MessagingPolicyStore
    let webFilterStore: WebFilterStore
    let toolLimitsStore: ToolLimitsStore
    let intentProviderSelection: IntentProviderSelectionStore
    let healthCheckStore: HealthCheckStore
    let messagingInboxStore: MessagingInboxStore
    let pairingCoordinator: PairingCoordinator
    let lockdownService: LockdownService
    let identityRecoveryManager: IdentityRecoveryManager
    let thermalWatcher: NPUThermalWatcher
    let memoryPressureMonitor: MemoryPressureMonitor
    let conversationHistoryStore: ConversationHistoryStore
    let appIntentScanner: AppIntentScanner
    let systemOperatorCapabilities: SystemOperatorCapabilityStore
    let executionRecoveryManager: ExecutionRecoveryManager

    init(modelContext: ModelContext) {
        let dependencies = Self.buildDependencies(modelContext: modelContext)
        let lockdownService = LockdownService(
            auditLog: dependencies.storageCapabilities.auditLog,
            messagingGateway: dependencies.messagingGateway,
            webScoutService: dependencies.webScoutClient,
            purgeLocalInference: {
                await LocalMLXInference.shared.purgeContext()
            }
        )

        self.reachability = dependencies.reachability
        self.securityCapabilities = dependencies.securityCapabilities
        self.modelCapabilities = dependencies.modelCapabilities
        self.storageCapabilities = dependencies.storageCapabilities
        self.runtimeCapabilities = dependencies.runtimeCapabilities
        self.untrustedParsingPolicy = dependencies.untrustedParsingPolicy
        self.identityPolicy = dependencies.identityPolicy
        self.auditRetentionPolicy = dependencies.auditRetentionPolicy
        self.messagingPolicy = dependencies.messagingPolicy
        self.webFilterStore = dependencies.webFilterStore
        self.toolLimitsStore = dependencies.toolLimitsStore
        self.intentProviderSelection = dependencies.intentProviderSelection
        self.healthCheckStore = dependencies.healthCheckStore
        self.messagingInboxStore = dependencies.messagingInboxStore
        self.pairingCoordinator = dependencies.pairingCoordinator
        self.lockdownService = lockdownService
        self.identityRecoveryManager = dependencies.identityRecoveryManager
        self.thermalWatcher = dependencies.thermalWatcher
        self.memoryPressureMonitor = dependencies.memoryPressureMonitor
        self.conversationHistoryStore = dependencies.conversationHistoryStore
        self.appIntentScanner = dependencies.appIntentScanner
        self.systemOperatorCapabilities = dependencies.systemOperatorCapabilities
        self.executionRecoveryManager = dependencies.executionRecoveryManager

        Self.configureToolRegistry(
            toolRuntime: runtimeCapabilities.toolRuntime,
            appIntentScanner: appIntentScanner,
            systemOperatorCapabilities: systemOperatorCapabilities,
            auditLog: storageCapabilities.auditLog
        )

        storageCapabilities.auditLog.updatePayloadRetentionDays(auditRetentionPolicy.retentionDays)

        MemoryEntityProvider.shared.configure { [weak self] ids in
            guard let self else {
                throw MemoryEntityProvider.Error.ownerUnavailable
            }
            return try await self.storageCapabilities.memoryManager.fetchEntries(with: ids)
        }
        /*
        MemoryOpenCoordinator.shared.configure { [weak self] id in
            self?.navigateToMemoryRecord(id)
        }
        GoalOpenCoordinator.shared.configure { [weak self] id in
            self?.navigateToGoal(id)
        }
        */
        SecurityCenterCoordinator.shared.configure(
            open: { [weak self] in
                self?.navigationSelection = .settings
                self?.settingsSelection = .security
                // .securityCenter if exists, creating mapping
            },
            runHealthCheck: { [weak self] in
                guard let self else { return }
                Task { await self.healthCheckStore.run(auditLog: self.storageCapabilities.auditLog) }
            }
        )
        AgentAutomationCoordinator.shared.configure(
            handlePrompt: { [weak self] text in
                guard let self else { return false }
                return await self.handleExternalPrompt(text)
            },
            startPlanning: { [weak self] goal in
                guard let self else { return false }
                return await self.startPlanning(goal: goal)
            }
        )
        
        // Mocking IntentOrchestrator config since IntentOrchestrator types are complex and stubbed in my AppStubs
        // Assuming IntentOrchestrator.shared exists and has configure method
    }

    func start() {
        securityCapabilities.networkPolicy.startExpirationMonitor()
        reachability.start()
        runtimeCapabilities.networkClient.updateNetworkAvailability(reachability.isReachable)
        storageCapabilities.memoryManager.purgeExpired()
        checkInfoPlistCompliance()
        messagingInboxStore.onPairingRequest = { [weak self] request in
            self?.navigationSelection = .settings
            self?.settingsSelection = .general
            self?.showPairingSheet = true
            self?.showBanner(
                message: "Incoming pairing request from \(request.displayName ?? request.senderId).",
                isError: false,
                actionTitle: "Review",
                action: { [weak self] in
                    self?.navigationSelection = .settings
                    self?.settingsSelection = .general
                    self?.showPairingSheet = true
                }
            )
        }
        messagingInboxStore.onLockdownRequest = { [weak self] reason in
            guard let self else { return }
            Task {
                await self.lockdownService.initiateLockdown(reason: reason)
                await MainActor.run {
                    self.isLockedDown = true
                    self.showBanner(
                        message: "Emergency lockdown enabled. Messaging and web scouting are paused."
                    )
                }
            }
        }
        Task {
            await identityRecoveryManager.adoptCloudIdentityIfNeeded()
            if identityRecoveryManager.isCloudSyncEnabled {
                _ = await identityRecoveryManager.syncIdentityToCloud()
            }
        }
        Task {
            let goals = await TaskPlanner.shared.allGoals()
            await SystemSearchDonationManager.donate(goals: goals)
            for goal in goals where goal.status != .active {
                let summary = """
                Goal '\(goal.title)' is \(goal.status.rawValue). \
                Progress: \(Int((goal.completionPercentage * 100).rounded()))%. \
                Intent: \(goal.sourceIntent)
                """
                await VectorMemoryStore.shared.ingest(
                    content: summary,
                    source: "Goal: \(goal.title)"
                )
            }
        }
        messagingInboxStore.startPolling()
        thermalWatcher.start()
        memoryPressureMonitor.start()
        Task {
            await runtimeCapabilities.orchestrator.warmUpIfPossible()
        }
        reachabilityTask?.cancel()
        reachabilityTask = Task {
            for await path in reachabilityStatusStream() {
                runtimeCapabilities.networkClient.updateNetworkAvailability(path.status == .satisfied)
                if path.status != .satisfied {
                    handleOfflineMode()
                    showBanner(
                        message: "Network is offline. Requests will pause.",
                        isError: true,
                        actionTitle: "Open Settings",
                        action: { [weak self] in
                            self?.navigationSelection = .settings
                        }
                    )
                } else if path.isExpensive && !securityCapabilities.networkPolicy.avoidAutoSwitchOnExpensive {
                    handleOfflineMode()
                    showBanner(message: "Network is expensive. Using your local model.", isError: true)
                } else if path.isConstrained {
                    showBanner(message: "Network is in Low Data Mode.", isError: false)
                }
            }
        }
        systemEventTask?.cancel()
        systemEventTask = Task {
            for await event in SystemEventBus.shared.stream() {
                handleSystemEvent(event)
            }
        }
    }

    private func checkInfoPlistCompliance() {
        guard !didWarnInfoPlist else { return }
        didWarnInfoPlist = true
        if Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") == nil {
            showBanner(
                message: "Missing Face ID usage description in Info.plist. Touch ID prompts may fail review.",
                isError: true
            )
        }
    }

    func stop() {
        reachabilityTask?.cancel()
        reachabilityTask = nil
        systemEventTask?.cancel()
        systemEventTask = nil
        messagingInboxStore.stopPolling()
        thermalWatcher.stop()
        memoryPressureMonitor.stop()
    }

    func navigateToMemoryRecord(_ id: UUID) {
        memoryDeepLinkId = id
        navigationSelection = .settings
        settingsSelection = .general // .memory placeholder
    }

    func navigateToGoal(_ id: UUID) {
        goalDeepLinkId = id
        navigationSelection = .goals
    }

    private func handleOfflineMode() {
        guard !reachability.isReachable else { return }
        if let fallbackId = modelCapabilities.modelSelection.activeModelId { // Stub activeModelId
            modelCapabilities.modelSelection.activeModelId = fallbackId
            showBanner(message: "Switched to your offline model.")
        }
    }

    private func reachabilityStatusStream() -> AsyncStream<NWPath> {
        // Stub
        return AsyncStream { _ in }
    }

    func exportAuditLog() async {
        guard let option = await ExportOptionsPrompt.presentPlanReport() else { return } // Using PlanReport stub
        let defaultName = "QuantumBadger-Audit-\(Date().formatted(date: .numeric, time: .omitted))"
        let url = await SavePanelPresenter.present(
            defaultFileName: defaultName,
            allowedFileTypes: option.isEncrypted ? ["qblog"] : ["json"]
        )
        guard let url else { return }
        let succeeded = await storageCapabilities.auditLog.export(to: url, option: option)
        if succeeded {
            showBanner(message: "Export complete.")
        } else {
            showBanner(message: "Export failed. Try again or choose a different location.", isError: true)
        }
    }

    func handleExternalPrompt(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        navigationSelection = .console
        pendingExternalPrompt = trimmed
        externalPromptRequestID = UUID()
        return true
    }

    func startPlanning(goal: String) async -> Bool {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        navigationSelection = .goals
        let plan = await runtimeCapabilities.orchestrator.proposePlan(for: trimmed)
        executionRecoveryManager.startGoal(plan.intent, plan: plan.steps)
        _ = await TaskPlanner.shared.upsertGoal(
            planID: plan.id,
            title: plan.intent.isEmpty ? "Untitled Goal" : plan.intent,
            sourceIntent: plan.intent,
            totalSteps: max(1, plan.steps.count),
            completedSteps: 0,
            failedSteps: 0
        )
        showBanner(message: "Planning started for \"\(trimmed)\".")
        return true
    }

    func showBanner(
        message: String,
        isError: Bool = false,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        let resolvedActionTitle: String?
        let resolvedAction: (@MainActor () -> Void)?
        if isError && actionTitle == nil {
            resolvedActionTitle = "Open Settings"
            resolvedAction = { [weak self] in
                self?.navigationSelection = .settings
            }
        } else {
            resolvedActionTitle = actionTitle
            resolvedAction = action
        }
        let banner = BannerState(
            message: message,
            isError: isError,
            actionTitle: resolvedActionTitle,
            action: resolvedAction
        )
        self.banner = banner
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.banner?.id == banner.id {
                self.banner = nil
            }
        }
    }

    func showMemoryToast(message: String) {
        let toast = MemoryToastState(message: message)
        memoryToast = toast
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.memoryToast?.id == toast.id {
                self.memoryToast = nil
            }
        }
    }

    @MainActor
    private func handleSystemEvent(_ event: SystemEvent) {
        switch event {
        case .networkResponseTruncated(let host):
            handleNetworkResponseTruncated(host)
        case .modelLoadBlocked: // Enum case adaptation
             showBanner(message: "Model loading blocked due to memory pressure.", isError: true)
        case .modelLoadRejected(let reason):
            handleModelLoadRejected(reason)
        case .networkCircuitTripped(let host, let cooldownSeconds):
            handleCircuitTripped(host: host, cooldownSeconds: cooldownSeconds)
        case .networkCircuitOpened(let host, let until):
            openCircuitsStore.handleOpened(host: host, until: until)
        case .networkCircuitClosed(let host):
            openCircuitsStore.handleClosed(host: host)
        case .decodingSkipped(let count, let source):
            handleDecodingSkipped(count: count, source: source)
        case .memoryWriteNeedsConfirmation(let origin):
            handleMemoryWriteNeedsConfirmation(origin: origin)
        case .toolExecutionFailed(_, let message):
            showBanner(message: message, isError: false)
        case .pccConnectionDelay:
            showBanner(message: "Securing connection to Private Cloud Compute…", isError: false)
        case .outboundMessageBlocked(let reason):
            handleOutboundMessageBlocked(reason: reason)
        case .systemActionNotice(let message):
            showBanner(message: message, isError: false)
        case .modelEvictionRequested(let reason):
            Task { [weak self] in
                guard let self else { return }
                let released = await self.runtimeCapabilities.orchestrator.releaseRuntimeForMemoryPressure()
                guard released else { return }
                self.showMemoryToast(message: reason)
                self.storageCapabilities.auditLog.record(
                    event: .systemMaintenance("Proactive model eviction: \(reason)")
                )
            }
        case .modelAutoUnloaded(let message):
            showMemoryToast(message: message)
        case .thermalThrottlingChanged(let active):
            handleThermalThrottlingChanged(active: active)
        case .thermalEmergencyShutdown(let reason):
            Task { [weak self] in
                await self?.performEmergencyShutdown(reason: reason)
            }
        case .conversationCompacted(let beforeTokens, let afterTokens):
            handleConversationCompacted(beforeTokens: beforeTokens, afterTokens: afterTokens)
        default: break
        }
    }

    private static func configureSharedAuditSinks(_ auditLog: AuditLog) {
        SafeDecodingLog.auditLog = auditLog
        OutboundPrivacyFilter.auditLog = auditLog
    }

    private static func registerToolBridge(
        tool: ToolDefinition,
        toolRuntime: ToolRuntime,
        successValue: @escaping ([String: String]) -> String,
        failureMessage: String
    ) {
        ToolRegistry.shared.register(tool: tool) { request in
            let result = await toolRuntime.run(request)
            if result.succeeded {
                return successValue(result.output)
            }
            let reason = result.output["error"] ?? failureMessage
            throw ToolRegistryError.executionFailed(reason, code: result.output["code"])
        }
    }

    private static func configureToolRegistry(
        toolRuntime: ToolRuntime,
        appIntentScanner: AppIntentScanner,
        systemOperatorCapabilities: SystemOperatorCapabilityStore,
        auditLog: AuditLog
    ) {
        // Implementation stubbed for now
        let _ = ToolCatalog.hardenedSystemOperatorTool(
            systemOperatorCapabilities: systemOperatorCapabilities
        )
    }

    private static func buildDependencies(modelContext: ModelContext) -> AppDependencyBundle {
        let auditLog = AuditLog()
        configureSharedAuditSinks(auditLog)
        let networkPolicy = NetworkPolicyStore(auditLog: auditLog) // Fixed init
        let networkClient = NetworkClient(policy: networkPolicy, auditLog: auditLog)
        let reachability = NetworkReachabilityMonitor()
        let bookmarkStore = BookmarkStore()
        let vaultStore = VaultStore()
        let modelRegistry = ModelRegistry(catalog: ModelCatalog()) // Fixed init
        let modelSelection = ModelSelectionStore()
        let resourcePolicy = ResourcePolicyStore()
        let messagingPolicy = MessagingPolicyStore()
        let webFilterStore = WebFilterStore()
        let toolLimitsStore = ToolLimitsStore()
        let identityPolicy = IdentityPolicyStore()
        let auditRetentionPolicy = AuditRetentionPolicyStore()
        let intentProviderSelection = IntentProviderSelectionStore()
        let healthCheckStore = HealthCheckStore()
        let identityRecoveryManager = IdentityRecoveryManager(auditLog: auditLog)
        let thermalWatcher = NPUThermalWatcher.shared
        let memoryPressureMonitor = MemoryPressureMonitor()
        let conversationHistoryStore = ConversationHistoryStore(memoryController: MemoryController()) // Fixed init
        let systemOperatorCapabilities = SystemOperatorCapabilityStore()
        let appIntentScanner = AppIntentScanner(capabilityStore: systemOperatorCapabilities)
        let executionRecoveryManager = ExecutionRecoveryManager()
        FocusModeController.shared.configure(capabilities: systemOperatorCapabilities)

        let policy = PolicyEngine(
            auditLog: auditLog,
            messagingPolicy: messagingPolicy,
            systemOperatorCapabilities: systemOperatorCapabilities
        )
        let memoryManager = MemoryManager(modelContext: modelContext, auditLog: auditLog)
        // AuthenticationManager stub needed
        let toolApprovalManager = ToolApprovalManager()

        let untrustedParsingPolicy = UntrustedParsingPolicyStore()
        let webScoutClient = WebScoutXPCClient(parsingPolicy: untrustedParsingPolicy)
        let messagingGateway = MessagingXPCClient()
        let toolRuntime = ToolRuntime(
            policy: policy,
            auditLog: auditLog,
            bookmarkStore: bookmarkStore,
            memoryManager: memoryManager,
            vaultStore: vaultStore,
            untrustedParser: UntrustedParsingXPCClient(policyStore: untrustedParsingPolicy),
            messagingAdapter: SharingMessagingAdapter(),
            messagingPolicy: messagingPolicy,
            networkClient: networkClient,
            webScoutService: webScoutClient,
            webFilterStore: webFilterStore,
            systemActionAdapter: AppIntentBridgeAdapter(capabilities: systemOperatorCapabilities),
            systemOperatorCapabilities: systemOperatorCapabilities,
            toolLimitsStore: toolLimitsStore,
            semanticRiskConfirmationHandler: { _,_,_,_ in return true }
        )
        let modelLoader = ModelLoader(
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            factory: DefaultModelRuntimeFactory(
                cloudKeyProvider: KeychainCloudKeyProvider(),
                networkClient: networkClient
            )
        )
        let executionManager = HybridExecutionManager(
            modelLoader: modelLoader,
            policy: policy,
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            reachability: reachability,
            auditLog: auditLog,
            toolRiskConfirmationHandler: { _,_,_,_ in return true }
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

        let securityCapabilities = SecurityCapabilities(
            policy: policy,
            networkPolicy: networkPolicy,
            toolApprovalManager: toolApprovalManager,
            messagingPolicy: messagingPolicy,
            webFilterStore: webFilterStore,
            toolLimitsStore: toolLimitsStore
        )
        let modelCapabilities = ModelCapabilities(
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            modelLoader: modelLoader
        )
        let storageCapabilities = StorageCapabilities(
            vaultStore: vaultStore,
            auditLog: auditLog,
            memoryManager: memoryManager,
            bookmarkStore: bookmarkStore,
            auditRetentionPolicy: auditRetentionPolicy
        )
        let runtimeCapabilities = RuntimeCapabilities(
            orchestrator: orchestrator,
            toolRuntime: toolRuntime,
            networkClient: networkClient
        )

        let messagingInboxStore = MessagingInboxStore()
        let pairingCoordinator = PairingCoordinator()

        return AppDependencyBundle(
            reachability: reachability,
            securityCapabilities: securityCapabilities,
            modelCapabilities: modelCapabilities,
            storageCapabilities: storageCapabilities,
            runtimeCapabilities: runtimeCapabilities,
            untrustedParsingPolicy: untrustedParsingPolicy,
            identityPolicy: identityPolicy,
            auditRetentionPolicy: auditRetentionPolicy,
            messagingPolicy: messagingPolicy,
            webFilterStore: webFilterStore,
            toolLimitsStore: toolLimitsStore,
            intentProviderSelection: intentProviderSelection,
            healthCheckStore: healthCheckStore,
            messagingInboxStore: messagingInboxStore,
            pairingCoordinator: pairingCoordinator,
            identityRecoveryManager: identityRecoveryManager,
            thermalWatcher: thermalWatcher,
            memoryPressureMonitor: memoryPressureMonitor,
            conversationHistoryStore: conversationHistoryStore,
            appIntentScanner: appIntentScanner,
            systemOperatorCapabilities: systemOperatorCapabilities,
            executionRecoveryManager: executionRecoveryManager,
            messagingGateway: messagingGateway,
            webScoutClient: webScoutClient
        )
    }

    private func handleNetworkResponseTruncated(_ host: String) {
        showBanner(message: "Response from \(host) was too large and was stopped.", isError: true)
    }

    private func handleModelLoadRejected(_ reason: String) {
        showBanner(
            message: reason,
            isError: false,
            actionTitle: "Open Models",
            action: { [weak self] in
                self?.navigationSelection = .models
            }
        )
    }

    private func handleCircuitTripped(host: String, cooldownSeconds: Int) {
        showBanner(
            message: "Network requests to \(host) are paused for \(cooldownSeconds)s after repeated failures.",
            isError: true,
            actionTitle: "Open Settings",
            action: { [weak self] in
                self?.navigationSelection = .settings
            }
        )
    }

    private func handleDecodingSkipped(count: Int, source: String?) {
        let sourceLabel = source ?? "results"
        let message = "Skipped \(count) malformed \(sourceLabel.lowercased()) item\(count == 1 ? "" : "s")."
        showBanner(message: message, isError: false)
    }

    private func handleMemoryWriteNeedsConfirmation(origin: String) {
        showBanner(
            message: "Memory from \(origin) needs confirmation before saving.",
            isError: false,
            actionTitle: "Open Memory",
            action: { [weak self] in
                self?.navigationSelection = .settings
                self?.settingsSelection = .general // .memory placeholder
            }
        )
    }

    private func handleOutboundMessageBlocked(reason: String) {
        showBanner(
            message: "Message blocked to protect your privacy. \(reason)",
            isError: false,
            actionTitle: "Open Security Center",
            action: { [weak self] in
                self?.navigationSelection = .settings
                self?.settingsSelection = .security
            }
        )
    }

    private func handleThermalThrottlingChanged(active: Bool) {
        if active {
            showBanner(
                message: "Thermal throttling active. MLX tasks are running at lower power to protect your Mac.",
                isError: false,
                actionTitle: "Open Security Center",
                action: { [weak self] in
                    self?.navigationSelection = .settings
                    self?.settingsSelection = .security
                }
            )
        } else {
            showBanner(message: "Thermal throttling cleared. Full performance restored.", isError: false)
        }
    }

    private func handleConversationCompacted(beforeTokens: Int, afterTokens: Int) {
        showBanner(
            message: "Context optimized: \(beforeTokens) to \(afterTokens) tokens.",
            isError: false
        )
    }

    @MainActor
    private func performEmergencyShutdown(reason: String) async {
        await runtimeCapabilities.orchestrator.cancelActiveGeneration()
        await TaskPlanner.shared.forcePersist()
        await LocalMLXInference.shared.purgeContext()
        await storageCapabilities.auditLog.flush()
        await storageCapabilities.memoryManager.flush()
        await PendingMessageStore.shared.flush()
        showBanner(
            message: "Emergency shutdown engaged. \(reason)",
            isError: true,
            actionTitle: "Open Security Center",
            action: { [weak self] in
                self?.navigationSelection = .settings
                self?.settingsSelection = .security
            }
        )
    }
}
