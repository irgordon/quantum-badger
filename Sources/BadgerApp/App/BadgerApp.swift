import SwiftUI
import AppKit
import Combine
import SwiftData
import CoreSpotlight
import BadgerCore
import QuantumBadgerRuntime // Combined import

// MARK: - Environment Keys

private struct PrivacyShieldEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isPrivacyShieldEnabled: Bool {
        get { self[PrivacyShieldEnabledKey.self] }
        set { self[PrivacyShieldEnabledKey.self] = newValue }
    }
}

// MARK: - App Entry Point

@main
struct QuantumBadgerApp: App {
    // State management
    @State private var modelContainer: ModelContainer?
    @State private var appState: AppState?
    @State private var onboardingStateStore: OnboardingStateStore?
    @State private var isSafeMode: Bool = false
    @State private var safeModeMessage: String = ""
    @State private var didStartServices = false
    @State private var shouldConfirmReset = false
    
    // Preferences
    @AppStorage("qb.privacyShieldEnabled") private var isPrivacyShieldEnabled = false
    
    // Lifecycle
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Initialize Schema and Container
        let schema = Schema([MemoryRecord.self])
        do {
            let container = try ModelContainer(for: schema)
            _modelContainer = State(initialValue: container)
            // Initialize AppState with the context
            _appState = State(initialValue: AppState(modelContext: container.mainContext))
        } catch {
            _modelContainer = State(initialValue: nil)
            _appState = State(initialValue: nil)
            _isSafeMode = State(initialValue: true)
            _safeModeMessage = State(initialValue: "Database Error: \(error.localizedDescription)")
        }
        
        // Register Background Tasks
        BackgroundScoutCoordinator.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
                        ProgressView("Initializing Quantum Badger…")
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
            .onAppear {
                // Ensure services start if we launch directly into active
                if scenePhase == .active {
                    startServicesIfNeeded()
                }
            }
        }
        .environment(\.isPrivacyShieldEnabled, isPrivacyShieldEnabled)
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            handleSpotlightDeepLink(userActivity)
        }
        .confirmationDialog(
            "Reset & Repair?",
            isPresented: $shouldConfirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset & Repair", role: .destructive) {
                attemptReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will wipe all local memory and history. This action cannot be undone.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                startServicesIfNeeded()
                Task { await onboardingStateStore?.refresh() }
            }
            BackgroundScoutCoordinator.shared.handleScenePhaseChange(newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task { await TaskPlanner.shared.forcePersist() }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Export Activity Log…") {
                    // Action: Navigate user to Settings -> Audit where they can export properly
                    if let appState {
                        appState.navigation.selection = .settings
                        appState.navigation.settingsSelection = .audit // Assuming .audit exists, or fallback
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            if let appState, !isSafeMode {
                SystemStatusMenu(appState: appState, isPrivacyShieldEnabled: $isPrivacyShieldEnabled)
            } else {
                Text("Safe Mode Active").padding(8)
            }
        } label: {
            if let appState, !isSafeMode {
                SystemStatusMenuLabel(appState: appState)
            } else {
                Label("Safe Mode", systemImage: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Helper Logic

    private func handleSpotlightDeepLink(_ userActivity: NSUserActivity) {
        if let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           let uuid = extractUUID(from: identifier) {
            Task {
                let goals = await TaskPlanner.shared.fetchGoals(ids: [uuid])
                await MainActor.run {
                    if goals.isEmpty {
                        appState?.navigation.navigateToMemory(uuid)
                    } else {
                        appState?.navigation.navigateToGoal(uuid)
                    }
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
        let fileManager = FileManager.default
        let paths = [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")]
        
        for path in paths where fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }
}

// MARK: - Utilities

private func extractUUID(from identifier: String) -> UUID? {
    if let direct = UUID(uuidString: identifier) { return direct }
    // Regex to find UUID pattern inside a string
    let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(identifier.startIndex..<identifier.endIndex, in: identifier)
    if let match = regex.firstMatch(in: identifier, range: range),
       let range = Range(match.range, in: identifier) {
        return UUID(uuidString: String(identifier[range]))
    }
    return nil
}

// MARK: - Views

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPrivacyShieldEnabled) private var isPrivacyShieldEnabled
    @AppStorage("qb.navigationSelection") private var persistedNavigationSelectionRaw: String = NavigationSelection.console.rawValue

    var body: some View {
        @Bindable var appState = appState
        @Bindable var navigation = appState.navigation
        @Bindable var feedback = appState.feedback
        // Access via capabilities
        @Bindable var approval = appState.securityCapabilities.toolApprovalManager
        
        NavigationSplitView {
            SidebarView(selected: $navigation.selection)
        } detail: {
            DetailView(selection: navigation.selection)
        }
        .navigationTitle("Quantum Badger")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ActiveModelToolbarView(
                    modelRegistry: appState.modelCapabilities.catalog,
                    modelSelection: appState.modelCapabilities.selectionStore
                )
            }
            ToolbarItem(placement: .automatic) {
                NetworkStatusToolbarView(reachability: appState.reachability)
            }
        }
        // Feedback Overlays
        .overlay(alignment: .top) {
            if let banner = feedback.banner {
                BannerView(banner: banner).padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = feedback.memoryToast {
                MemoryToastView(toast: toast).padding(.bottom, 28)
            }
        }
        // Privacy Shield
        .overlay {
            if scenePhase != .active || isPrivacyShieldEnabled {
                PrivacyShieldView()
            }
        }
        // System Toasts
        .overlay(alignment: .bottom) {
            if let toast = NotificationManager.shared.currentToast {
                ToastView(toast: toast).padding(.bottom, 40).zIndex(100)
            }
        }
        // Modals
        .sheet(item: $approval.pendingContext, onDismiss: { approval.clearPending() }) { context in
            ToolApprovalSheet(context: context)
        }
        .onAppear {
            restorePersistedNavigationIfNeeded()
        }
        .onChange(of: navigation.selection) { _, newValue in
            persistedNavigationSelectionRaw = newValue.rawValue
        }
    }

    private func restorePersistedNavigationIfNeeded() {
        guard appState.navigation.selection == .console else { return }
        if let persisted = NavigationSelection(rawValue: persistedNavigationSelectionRaw) {
            appState.navigation.selection = persisted
        }
    }
}

// MARK: - Detail View (FIXED)

struct DetailView: View {
    @Environment(AppState.self) private var appState
    let selection: NavigationSelection

    var body: some View {
        @Bindable var appState = appState
        @Bindable var navigation = appState.navigation
        
        switch selection {
        case .console:
            ConsoleView() // Assumes ConsoleView pulls AppState from Environment
        case .timeline:
            TimelineView(auditLog: appState.storageCapabilities.auditLog)
        case .vault:
            VaultView(vaultStore: appState.storageCapabilities.vaultStore)
        case .drafts:
            DraftsView()
        case .models:
            ModelsView(
                modelRegistry: appState.modelCapabilities.catalog,
                modelSelection: appState.modelCapabilities.selectionStore,
                resourcePolicy: appState.modelCapabilities.resourcePolicy,
                modelLoader: appState.modelCapabilities.modelLoader,
                reachability: appState.reachability
            )
        case .goals:
            GoalDashboardView(
                executionRecoveryManager: appState.executionRecoveryManager, // FIXED: Correct dependency
                deepLinkGoalId: Binding(
                    get: { navigation.goalDeepLinkId },
                    set: { navigation.goalDeepLinkId = $0 }
                ),
                onDeepLinkHandled: { navigation.goalDeepLinkId = nil }
            )
        case .settings:
            SettingsView(
                // Security
                securityCapabilities: appState.securityCapabilities,
                
                // Storage & Logs
                auditLog: appState.storageCapabilities.auditLog,
                exportAction: { url, encrypted in 
                    await appState.exportAuditLog(to: url, encrypted: encrypted) 
                },
                
                // Models
                modelRegistry: appState.modelCapabilities.catalog,
                modelSelection: appState.modelCapabilities.selectionStore,
                resourcePolicy: appState.modelCapabilities.resourcePolicy,
                
                // System
                reachability: appState.reachability,
                bookmarkStore: appState.storageCapabilities.vaultStore,
                memoryManager: appState.storageCapabilities.memoryManager,
                
                // FIXED: Direct Access Properties (No longer nested deep in securityCapabilities.policy)
                untrustedParsingPolicy: appState.untrustedParsingPolicy,
                identityPolicy: appState.identityPolicy,
                auditRetentionPolicy: appState.auditRetentionPolicy,
                messagingPolicy: appState.messagingPolicy, // Computed accessor
                
                // Stores
                messagingInboxStore: appState.messagingInboxStore,
                pairingCoordinator: appState.pairingCoordinator, // FIXED: Top-level dependency
                webFilterStore: appState.webFilterStore, // Computed accessor
                openCircuitsStore: appState.openCircuitsStore, // Computed accessor
                
                // Runtime
                intentOrchestrator: IntentOrchestrator.shared,
                intentProviderSelection: appState.intentProviderSelection,
                healthCheckStore: appState.healthCheckStore,
                identityRecoveryManager: appState.identityRecoveryManager,
                conversationHistoryStore: appState.conversationHistoryStore,
                appIntentScanner: appState.appIntentScanner,
                systemOperatorCapabilities: appState.systemOperatorCapabilities,
                
                // Navigation Bindings
                selectedTab: $navigation.settingsSelection,
                memoryDeepLinkId: $navigation.memoryDeepLinkId,
                goalDeepLinkId: $navigation.goalDeepLinkId,
                showPairingSheet: $navigation.showPairingSheet
            )
        }
    }
}

// MARK: - Safe Mode & Components

private struct SafeModeView: View {
    let message: String
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safe Mode Active", systemImage: "exclamationmark.triangle.fill")
                .font(.title2)
                .symbolRenderingMode(.multicolor)
            
            Text("Quantum Badger couldn’t initialize its database.")
                .font(.body)
            
            if !message.isEmpty {
                GroupBox {
                    Text(message)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            Text("You can try restarting the app, or perform a reset to clear local storage.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Reset & Repair Storage", role: .destructive) {
                onReset()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: 500)
    }
}

// ... ActiveModelToolbarView and NetworkStatusToolbarView (Unchanged)
struct ActiveModelToolbarView: View {
    let modelRegistry: ModelCatalog
    let modelSelection: ModelSelectionStore
    var body: some View {
        let name = activeModelName()
        HStack(spacing: 6) {
            Image(systemName: "cpu").foregroundColor(.secondary)
            Text(name).font(.callout).foregroundColor(.secondary)
        }
        .help("Active model")
    }
    private func activeModelName() -> String {
        guard let id = modelSelection.activeModelId,
              let model = modelRegistry.models.first(where: { $0.id == id }) else {
            return "No active model"
        }
        return model.name
    }
}

struct NetworkStatusToolbarView: View {
    let reachability: NetworkReachabilityMonitor
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName).foregroundColor(.secondary)
            Text(labelText).font(.callout).foregroundColor(.secondary)
        }
        .help("Network status")
    }
    private var labelText: String {
        switch reachability.scope {
        case .offline: return "Offline"
        case .localNetwork: return "Local Network"
        case .internet: return "Internet"
        }
    }
    private var iconName: String {
        switch reachability.scope {
        case .offline: return "wifi.slash"
        case .localNetwork: return "laptopcomputer"
        case .internet: return "globe"
        }
    }
}
