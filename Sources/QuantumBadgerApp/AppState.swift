import Foundation
import Observation
import Network
import SwiftData
import QuantumBadgerRuntime

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

@MainActor
@Observable
final class AppState {
    var navigationSelection: NavigationSelection = .console
    var settingsSelection: SettingsTab = .general
    var banner: BannerState?
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

    init(modelContext: ModelContext) {
        let auditLog = AuditLog()
        SafeDecodingLog.auditLog = auditLog
        let networkPolicy = NetworkPolicyStore(auditLog: auditLog)
        let networkClient = NetworkClient(policy: networkPolicy, auditLog: auditLog)
        let reachability = NetworkReachabilityMonitor()
        let bookmarkStore = BookmarkStore()
        let vaultStore = VaultStore(auditLog: auditLog)
        let modelRegistry = ModelRegistry(auditLog: auditLog)
        let modelSelection = ModelSelectionStore()
        let resourcePolicy = ResourcePolicyStore()
        let messagingPolicy = MessagingPolicyStore()
        let webFilterStore = WebFilterStore()
        let toolLimitsStore = ToolLimitsStore()
        let identityPolicy = IdentityPolicyStore()
        let auditRetentionPolicy = AuditRetentionPolicyStore()
        let policy = PolicyEngine(auditLog: auditLog, messagingPolicy: messagingPolicy)
        let memoryManager = MemoryManager(modelContext: modelContext, auditLog: auditLog)
        let toolApprovalManager = ToolApprovalManager(webFilterStore: webFilterStore)
        let untrustedParsingPolicy = UntrustedParsingPolicyStore()
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
            webFilterStore: webFilterStore,
            toolLimitsStore: toolLimitsStore
        )
        let modelLoader = ModelLoader(
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            resourcePolicy: resourcePolicy,
            factory: DefaultModelRuntimeFactory(
                cloudKeyProvider: KeychainCloudKeyProvider()
            )
        )
        let securityCapabilities = SecurityCapabilities(
            policy: policy,
            networkPolicy: networkPolicy,
            toolApprovalManager: toolApprovalManager,
            messagingPolicy: messagingPolicy,
            webFilterStore: webFilterStore,
            toolLimitsStore: toolLimitsStore
        )
        let orchestrator = Orchestrator(
            toolRuntime: toolRuntime,
            auditLog: auditLog,
            modelLoader: modelLoader,
            policy: policy,
            modelRegistry: modelRegistry,
            modelSelection: modelSelection,
            vaultStore: vaultStore,
            resourcePolicy: resourcePolicy,
            reachability: reachability,
            messagingPolicy: messagingPolicy
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

        self.reachability = reachability
        self.securityCapabilities = securityCapabilities
        self.modelCapabilities = modelCapabilities
        self.storageCapabilities = storageCapabilities
        self.runtimeCapabilities = runtimeCapabilities
        self.untrustedParsingPolicy = untrustedParsingPolicy
        self.identityPolicy = identityPolicy
        self.auditRetentionPolicy = auditRetentionPolicy
        self.messagingPolicy = messagingPolicy
        self.webFilterStore = webFilterStore
        self.toolLimitsStore = toolLimitsStore

        auditLog.updatePayloadRetentionDays(auditRetentionPolicy.retentionDays)

    }

    func start() {
        securityCapabilities.networkPolicy.startExpirationMonitor()
        reachability.start()
        runtimeCapabilities.networkClient.updateNetworkAvailability(reachability.isReachable)
        storageCapabilities.memoryManager.purgeExpired()
        checkInfoPlistCompliance()
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
    }

    private func handleOfflineMode() {
        guard !reachability.isReachable else { return }
        if let fallbackId = modelCapabilities.modelSelection.offlineFallbackModelId {
            modelCapabilities.modelSelection.setActiveModel(fallbackId)
            showBanner(message: "Switched to your offline model.")
        }
    }

    private func reachabilityStatusStream() -> AsyncStream<NWPath> {
        reachability.statusStream()
    }

    func exportAuditLog() async {
        guard let option = await ExportOptionsPrompt.present() else { return }
        let defaultName = "QuantumBadger-Audit-\(Date().formatted(date: .numeric, time: .omitted))"
        let url = await SavePanelPresenter.present(
            defaultFileName: defaultName,
            allowedFileTypes: option.allowedFileTypes
        )
        guard let url else { return }
        let succeeded = await storageCapabilities.auditLog.export(to: url, option: option)
        if succeeded {
            showBanner(message: "Export complete.")
        } else {
            showBanner(message: "Export failed. Try again or choose a different location.", isError: true)
        }
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

    @MainActor
    private func handleSystemEvent(_ event: SystemEvent) {
        switch event {
        case .networkResponseTruncated(let host):
            showBanner(message: "Response from \(host) was too large and was stopped.", isError: true)
        case .modelLoadBlocked(let level):
            let message: String
            let isError: Bool
            switch level {
            case .critical:
                storageCapabilities.memoryManager.clearEphemeralCache()
                message = "Your Mac is under heavy memory pressure. Model loading is paused to keep things stable."
                isError = true
            case .warning:
                message = "Memory is running high. Model loading is paused for now."
                isError = false
            case .normal:
                message = "Model loading is paused to keep your Mac stable."
                isError = false
            }
            showBanner(message: message, isError: isError)
        case .networkCircuitTripped(let host, let cooldownSeconds):
            showBanner(
                message: "Network requests to \(host) are paused for \(cooldownSeconds)s after repeated failures.",
                isError: true,
                actionTitle: "Open Settings",
                action: { [weak self] in
                    self?.navigationSelection = .settings
                }
            )
        case .networkCircuitOpened(let host, let until):
            openCircuitsStore.handleOpened(host: host, until: until)
        case .networkCircuitClosed(let host):
            openCircuitsStore.handleClosed(host: host)
        case .decodingSkipped(let count, let source):
            let sourceLabel = source ?? "results"
            let message = "Skipped \(count) malformed \(sourceLabel.lowercased()) item\(count == 1 ? "" : "s")."
            showBanner(message: message, isError: false)
        case .memoryWriteNeedsConfirmation(let origin):
            showBanner(
                message: "Memory from \(origin) needs confirmation before saving.",
                isError: false,
                actionTitle: "Open Memory",
                action: { [weak self] in
                    self?.navigationSelection = .settings
                    self?.settingsSelection = .memory
                }
            )
        }
    }
}

@MainActor
@Observable
final class OpenCircuitsStore {
    var openCircuits: [NetworkOpenCircuit] = []
    private var closeTasks: [String: Task<Void, Never>] = [:]

    func handleOpened(host: String, until: Date) {
        openCircuits.removeAll { $0.host == host }
        openCircuits.append(NetworkOpenCircuit(host: host, until: until))
        openCircuits.sort { $0.host < $1.host }
        closeTasks[host]?.cancel()
        closeTasks[host] = Task { [weak self] in
            let wait = max(0, until.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await MainActor.run {
                self?.handleClosed(host: host)
            }
        }
    }

    func handleClosed(host: String) {
        openCircuits.removeAll { $0.host == host }
        closeTasks[host]?.cancel()
        closeTasks[host] = nil
    }
}

struct BannerState: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
    let actionTitle: String?
    let action: (@MainActor () -> Void)?
}

enum NavigationSelection: String, CaseIterable, Identifiable {
    case console
    case timeline
    case vault
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .console: return "Assistant"
        case .timeline: return "Activity"
        case .vault: return "Secure Items"
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .console: return "terminal"
        case .timeline: return "clock.arrow.circlepath"
        case .vault: return "lock.shield"
        case .models: return "cpu"
        case .settings: return "gearshape"
        }
    }
}
