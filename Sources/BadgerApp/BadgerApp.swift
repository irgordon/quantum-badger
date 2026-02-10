import SwiftUI
import AppKit
import Combine
import SwiftData
import CoreSpotlight
import BadgerCore
import BadgerRuntime

private struct PrivacyShieldEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isPrivacyShieldEnabled: Bool {
        get { self[PrivacyShieldEnabledKey.self] }
        set { self[PrivacyShieldEnabledKey.self] = newValue }
    }
}

@main
struct QuantumBadgerApp: App {
    @State private var modelContainer: ModelContainer?
    @State private var appState: AppState?
    @State private var onboardingStateStore: OnboardingStateStore?
    @State private var isSafeMode: Bool = false
    @State private var safeModeMessage: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStartServices = false
    @AppStorage("qb.privacyShieldEnabled") private var isPrivacyShieldEnabled = false
    @State private var shouldConfirmReset = false

    init() {
        let schema = Schema([MemoryRecord.self])
        do {
            let container = try ModelContainer(for: schema)
            _modelContainer = State(initialValue: container)
            _appState = State(initialValue: AppState(modelContext: container.mainContext))
        } catch {
            _modelContainer = State(initialValue: nil)
            _appState = State(initialValue: nil)
            _isSafeMode = State(initialValue: true)
            _safeModeMessage = State(initialValue: error.localizedDescription)
        }
        BackgroundScoutCoordinator.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            if let appState, let modelContainer, !isSafeMode {
                if let onboardingStateStore {
                    if onboardingStateStore.needsOnboarding {
                        WelcomeView(store: onboardingStateStore)
                            .environment(appState)
                            .modelContainer(modelContainer)
                    } else {
                        RootView()
                            .environment(appState)
                            .modelContainer(modelContainer)
                    }
                } else {
                    ProgressView("Preparing Quantum Badger…")
                        .task {
                            initializeOnboardingStoreIfNeeded(for: appState)
                            await onboardingStateStore?.refresh()
                        }
                }
            } else {
                SafeModeView(message: safeModeMessage) {
                    shouldConfirmReset = true
                }
            }
        }
        .environment(\.isPrivacyShieldEnabled, isPrivacyShieldEnabled)
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            if let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let uuid = extractUUID(from: identifier) {
                Task {
                    let goals = await TaskPlanner.shared.fetchGoals(ids: [uuid])
                    await MainActor.run {
                        if goals.isEmpty {
                            MemoryOpenCoordinator.shared.open(id: uuid)
                        } else {
                            GoalOpenCoordinator.shared.open(id: uuid)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Reset & Repair?",
            isPresented: $shouldConfirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset & Repair", role: .destructive) {
                attemptReset()
            }
            Button("Export Data First") {
                if let appState {
                    Task { await appState.exportAuditLog() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear local storage, including memory and model history. This can’t be undone.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                startServicesIfNeeded()
                Task { await onboardingStateStore?.refresh() }
            }
            BackgroundScoutCoordinator.shared.handleScenePhaseChange(newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task {
                await TaskPlanner.shared.forcePersist()
            }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Export Activity Log") {
                    if let appState {
                        Task { await appState.exportAuditLog() }
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            if let appState, !isSafeMode {
                SystemStatusMenu(appState: appState, isPrivacyShieldEnabled: $isPrivacyShieldEnabled)
            } else {
                Text("Safe Mode")
                    .padding(8)
            }
        } label: {
            if let appState, !isSafeMode {
                SystemStatusMenuLabel(appState: appState)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Safe Mode")
                }
            }
        }
    }

    private func startServicesIfNeeded() {
        guard let appState else { return }
        initializeOnboardingStoreIfNeeded(for: appState)
        guard !didStartServices else { return }
        didStartServices = true
        appState.start()
    }

    private func attemptReset() {
        appState?.storageCapabilities.memoryManager.resetVault()
        do {
            try clearSwiftDataStore()
            try recoverFromSafeMode()
        } catch {
            isSafeMode = true
            safeModeMessage = "Reset failed: \(error.localizedDescription)"
        }
    }

    private func recoverFromSafeMode() throws {
        let schema = Schema([MemoryRecord.self])
        let container = try ModelContainer(for: schema)
        let recoveredAppState = AppState(modelContext: container.mainContext)

        modelContainer = container
        appState = recoveredAppState
        onboardingStateStore = nil
        isSafeMode = false
        safeModeMessage = ""

        // Service startup is managed by scene phase; reset the guard for a clean boot.
        didStartServices = false
        if scenePhase == .active {
            startServicesIfNeeded()
        }
    }

    private func initializeOnboardingStoreIfNeeded(for appState: AppState) {
        guard onboardingStateStore == nil else { return }
        onboardingStateStore = OnboardingStateStore(
            identityRecoveryManager: appState.identityRecoveryManager
        )
    }

    private func clearSwiftDataStore() throws {
        guard let url = modelContainer?.configuration.url else { return }
        let storeURL = url
        let shmURL = storeURL.appendingPathExtension("shm")
        let walURL = storeURL.appendingPathExtension("wal")
        let fileManager = FileManager.default
        var failures: [String] = []

        for target in [storeURL, shmURL, walURL] where fileManager.fileExists(atPath: target.path) {
            do {
                try fileManager.removeItem(at: target)
            } catch {
                failures.append("\(target.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw NSError(
                domain: "QuantumBadger.SafeModeReset",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: failures.joined(separator: "\n")
                ]
            )
        }
    }
}

private func extractUUID(from identifier: String) -> UUID? {
    if let direct = UUID(uuidString: identifier) {
        return direct
    }
    let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(identifier.startIndex..<identifier.endIndex, in: identifier)
    for match in regex.matches(in: identifier, range: range) {
        guard let matchRange = Range(match.range, in: identifier) else { continue }
        if let uuid = UUID(uuidString: String(identifier[matchRange])) {
            return uuid
        }
    }
    return nil
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPrivacyShieldEnabled) private var isPrivacyShieldEnabled
    @AppStorage("qb.navigationSelection") private var persistedNavigationSelectionRaw: String = NavigationSelection.console.rawValue

    var body: some View {
        @Bindable var appState = appState
        @Bindable var approval = appState.securityCapabilities.toolApprovalManager
        NavigationSplitView {
            SidebarView(selected: $appState.navigationSelection)
        } detail: {
            DetailView(selection: appState.navigationSelection)
        }
        .navigationTitle("Quantum Badger")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ActiveModelToolbarView(
                    modelRegistry: appState.modelCapabilities.modelRegistry,
                    modelSelection: appState.modelCapabilities.modelSelection
                )
            }
            ToolbarItem(placement: .automatic) {
                NetworkStatusToolbarView(reachability: appState.reachability)
            }
        }
        .overlay(alignment: .top) {
            if let banner = appState.banner {
                BannerView(banner: banner)
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.memoryToast {
                MemoryToastView(toast: toast)
                    .padding(.bottom, 28)
            }
        }
        .overlay {
            if scenePhase != .active || isPrivacyShieldEnabled {
                PrivacyShieldView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = NotificationManager.shared.currentToast {
                ToastView(toast: toast)
                    .padding(.bottom, 40)
                    .zIndex(100)
            }
        }
        .sheet(item: $approval.pendingContext, onDismiss: {
            approval.clearPending()
        }) { context in
            ToolApprovalSheet(context: context)
        }
        .onAppear {
            restorePersistedNavigationIfNeeded()
        }
        .onChange(of: appState.navigationSelection) { _, newValue in
            persistedNavigationSelectionRaw = newValue.rawValue
        }
    }

    private func restorePersistedNavigationIfNeeded() {
        guard appState.navigationSelection == .console else { return }
        guard let persisted = NavigationSelection(rawValue: persistedNavigationSelectionRaw) else { return }
        appState.navigationSelection = persisted
    }
}

private struct SafeModeView: View {
    let message: String
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safe Mode")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Quantum Badger couldn’t initialize its local storage.")
                .font(.body)
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("You can close the app and try again, or reset local storage.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Reset & Repair") {
                onReset()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct ActiveModelToolbarView: View {
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore

    var body: some View {
        let name = activeModelName()
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .foregroundColor(.secondary)
            Text(name)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .help("Active model")
        .accessibilityLabel("Active model: \(name)")
    }

    private func activeModelName() -> String {
        guard let id = modelSelection.activeModelId,
              let model = modelRegistry.localModels().first(where: { $0.id == id }) else {
            return "No active model"
        }
        return model.name
    }
}

struct NetworkStatusToolbarView: View {
    let reachability: NetworkReachabilityMonitor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
            Text(labelText)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .help("Network status")
        .accessibilityLabel("Network status: \(labelText)")
    }

    private var labelText: String {
        switch reachability.scope {
        case .offline:
            return "Offline"
        case .localNetwork:
            return "Local Network"
        case .internet:
            return "Internet"
        }
    }

    private var iconName: String {
        switch reachability.scope {
        case .offline:
            return "wifi.slash"
        case .localNetwork:
            return "laptopcomputer"
        case .internet:
            return "globe"
        }
    }
}

struct DetailView: View {
    @Environment(AppState.self) private var appState
    let selection: NavigationSelection

    var body: some View {
        switch selection {
        case .console:
            ConsoleView(
                orchestrator: appState.runtimeCapabilities.orchestrator,
                modelRegistry: appState.modelCapabilities.modelRegistry,
                modelSelection: appState.modelCapabilities.modelSelection,
                reachability: appState.reachability,
                memoryManager: appState.storageCapabilities.memoryManager,
                bookmarkStore: appState.storageCapabilities.bookmarkStore,
                vaultStore: appState.storageCapabilities.vaultStore,
                auditLog: appState.storageCapabilities.auditLog,
                policy: appState.securityCapabilities.policy,
                toolApprovalManager: appState.securityCapabilities.toolApprovalManager,
                toolLimitsStore: appState.securityCapabilities.toolLimitsStore,
                messagingInboxStore: appState.messagingInboxStore,
                conversationHistoryStore: appState.conversationHistoryStore,
                executionRecoveryManager: appState.executionRecoveryManager
            )
        case .timeline:
            TimelineView(auditLog: appState.storageCapabilities.auditLog)
        case .vault:
            VaultView(vaultStore: appState.storageCapabilities.vaultStore)
        case .drafts:
            DraftsView()
        case .models:
            ModelsView(
                modelRegistry: appState.modelCapabilities.modelRegistry,
                modelSelection: appState.modelCapabilities.modelSelection,
                resourcePolicy: appState.modelCapabilities.resourcePolicy,
                modelLoader: appState.modelCapabilities.modelLoader,
                reachability: appState.reachability
            )
        case .goals:
            GoalDashboardView(
                executionRecoveryManager: appState.executionRecoveryManager,
                deepLinkGoalId: Binding(
                    get: { appState.goalDeepLinkId },
                    set: { appState.goalDeepLinkId = $0 }
                ),
                onDeepLinkHandled: {
                    appState.goalDeepLinkId = nil
                }
            )
        case .settings:
            SettingsView(
                securityCapabilities: appState.securityCapabilities,
                auditLog: appState.storageCapabilities.auditLog,
                exportAction: appState.exportAuditLog,
                modelRegistry: appState.modelCapabilities.modelRegistry,
                modelSelection: appState.modelCapabilities.modelSelection,
                resourcePolicy: appState.modelCapabilities.resourcePolicy,
                reachability: appState.reachability,
                bookmarkStore: appState.storageCapabilities.bookmarkStore,
                memoryManager: appState.storageCapabilities.memoryManager,
                untrustedParsingPolicy: appState.untrustedParsingPolicy,
                identityPolicy: appState.identityPolicy,
                auditRetentionPolicy: appState.auditRetentionPolicy,
                messagingPolicy: appState.messagingPolicy,
                messagingInboxStore: appState.messagingInboxStore,
                pairingCoordinator: appState.pairingCoordinator,
                webFilterStore: appState.webFilterStore,
                openCircuitsStore: appState.openCircuitsStore,
                intentOrchestrator: IntentOrchestrator.shared,
                intentProviderSelection: appState.intentProviderSelection,
                healthCheckStore: appState.healthCheckStore,
                identityRecoveryManager: appState.identityRecoveryManager,
                conversationHistoryStore: appState.conversationHistoryStore,
                appIntentScanner: appState.appIntentScanner,
                systemOperatorCapabilities: appState.systemOperatorCapabilities,
                selectedTab: Binding(
                    get: { appState.settingsSelection },
                    set: { appState.settingsSelection = $0 }
                ),
                memoryDeepLinkId: Binding(
                    get: { appState.memoryDeepLinkId },

                    set: { appState.memoryDeepLinkId = $0 }
                ),
                goalDeepLinkId: Binding(
                    get: { appState.goalDeepLinkId },
                    set: { appState.goalDeepLinkId = $0 }
                ),
                showPairingSheet: Binding(
                    get: { appState.showPairingSheet },
                    set: { appState.showPairingSheet = $0 }
                )
            )
        }
    }
}

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.title2)
                Text("Hidden for privacy")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct BannerView: View {
    let banner: BannerState

    var body: some View {
        HStack(spacing: 12) {
            Text(banner.message)
                .font(.callout)
                .foregroundColor(.white)
            if let title = banner.actionTitle, let action = banner.action {
                Button(title) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(banner.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
        )
        .shadow(radius: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: banner.id)
    }
}

struct MemoryToastView: View {
    let toast: MemoryToastState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip.fill")
                .foregroundStyle(.indigo)
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: toast.id)
    }
}
