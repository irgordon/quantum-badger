import SwiftUI
import AppKit
import SwiftData
import QuantumBadgerRuntime

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
    private let modelContainer: ModelContainer?
    @State private var appState: AppState?
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
            modelContainer = container
            _appState = State(initialValue: AppState(modelContext: container.mainContext))
        } catch {
            modelContainer = nil
            _appState = State(initialValue: nil)
            _isSafeMode = State(initialValue: true)
            _safeModeMessage = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let appState, let modelContainer, !isSafeMode {
                RootView()
                    .environment(appState)
                    .modelContainer(modelContainer)
            } else {
                SafeModeView(message: safeModeMessage) {
                    shouldConfirmReset = true
                }
            }
        }
        .environment(\.isPrivacyShieldEnabled, isPrivacyShieldEnabled)
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
                @Bindable var openCircuitsStore = appState.openCircuitsStore
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: modelModeIcon())
                        Text(modelModeText())
                    }
                    HStack(spacing: 8) {
                        Image(systemName: networkIcon())
                        Text(networkText())
                    }
                    if !openCircuitsStore.openCircuits.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paused hosts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(openCircuitsStore.openCircuits) { circuit in
                                HStack {
                                    Text(circuit.host)
                                    Spacer()
                                    Text(remainingCooldownText(until: circuit.until))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    Toggle("Privacy Mode", isOn: $isPrivacyShieldEnabled)
                    Divider()
                    Button("Open Quantum Badger") {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .padding(8)
            } else {
                Text("Safe Mode")
                    .padding(8)
            }
        } label: {
            if let appState, !isSafeMode {
                @Bindable var openCircuitsStore = appState.openCircuitsStore
                HStack(spacing: 6) {
                    Image(systemName: modelModeIcon())
                    Text(modelModeText())
                    Text("•")
                        .foregroundColor(.secondary)
                    Image(systemName: networkIcon())
                    Text(networkText())
                    if !openCircuitsStore.openCircuits.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Paused \(openCircuitsStore.openCircuits.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Safe Mode")
                }
            }
        }
    }

    private func modelModeText() -> String {
        activeModel()?.isCloud == true ? "Cloud" : "Local"
    }

    private func modelModeIcon() -> String {
        activeModel()?.isCloud == true ? "cloud" : "cpu"
    }

    private func networkText() -> String {
        guard let appState else { return "Offline" }
        switch appState.reachability.scope {
        case .offline:
            return "Offline"
        case .localNetwork:
            return "Local Network"
        case .internet:
            return "Internet"
        }
    }

    private func networkIcon() -> String {
        guard let appState else { return "wifi.slash" }
        switch appState.reachability.scope {
        case .offline:
            return "wifi.slash"
        case .localNetwork:
            return "laptopcomputer"
        case .internet:
            return "globe"
        }
    }

    private func activeModel() -> LocalModel? {
        guard let appState else { return nil }
        guard let id = appState.modelCapabilities.modelSelection.activeModelId else { return nil }
        return appState.modelCapabilities.modelRegistry.models.first { $0.id == id }
    }

    private func startServicesIfNeeded() {
        guard let appState else { return }
        guard !didStartServices else { return }
        didStartServices = true
        appState.start()
    }

    private func remainingCooldownText(until: Date) -> String {
        let remaining = max(0, Int(until.timeIntervalSinceNow))
        if remaining <= 0 {
            return "Resuming shortly"
        }
        if remaining < 60 {
            return "Resuming in \(remaining)s"
        }
        let minutes = Int(ceil(Double(remaining) / 60.0))
        return "Resuming in \(minutes)m"
    }

    private func attemptReset() {
        guard let appState else { return }
        appState.storageCapabilities.memoryManager.resetVault()
        clearSwiftDataStore()
        isSafeMode = false
        safeModeMessage = ""
    }

    private func clearSwiftDataStore() {
        guard let url = modelContainer?.configuration.url else { return }
        let storeURL = url
        let shmURL = storeURL.appendingPathExtension("shm")
        let walURL = storeURL.appendingPathExtension("wal")
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: shmURL)
        try? FileManager.default.removeItem(at: walURL)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPrivacyShieldEnabled) private var isPrivacyShieldEnabled

    var body: some View {
        @Bindable var appState = appState
        @Bindable var approval = appState.securityCapabilities.toolApprovalManager
        NavigationSplitView {
            SidebarView(selected: $appState.navigationSelection)
        } detail: {
            DetailView(
                selection: appState.navigationSelection,
                orchestrator: appState.runtimeCapabilities.orchestrator,
                auditLog: appState.storageCapabilities.auditLog,
                vaultStore: appState.storageCapabilities.vaultStore,
                modelRegistry: appState.modelCapabilities.modelRegistry,
                modelSelection: appState.modelCapabilities.modelSelection,
                resourcePolicy: appState.modelCapabilities.resourcePolicy,
                modelLoader: appState.modelCapabilities.modelLoader,
                securityCapabilities: appState.securityCapabilities,
                reachability: appState.reachability,
                bookmarkStore: appState.storageCapabilities.bookmarkStore,
                memoryManager: appState.storageCapabilities.memoryManager,
                exportAction: appState.exportAuditLog
            )
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
        .overlay {
            if scenePhase != .active || isPrivacyShieldEnabled {
                PrivacyShieldView()
            }
        }
        .sheet(item: $approval.pendingContext, onDismiss: {
            approval.clearPending()
        }) { context in
            ToolApprovalSheet(context: context)
        }
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
    let selection: NavigationSelection
    let orchestrator: Orchestrator
    let auditLog: AuditLog
    let vaultStore: VaultStore
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let resourcePolicy: ResourcePolicyStore
    let modelLoader: ModelLoader
    let securityCapabilities: SecurityCapabilities
    let reachability: NetworkReachabilityMonitor
    let bookmarkStore: BookmarkStore
    let memoryManager: MemoryManager
    let exportAction: @MainActor () async -> Void

    var body: some View {
        switch selection {
        case .console:
            ConsoleView(
                orchestrator: orchestrator,
                modelRegistry: modelRegistry,
                modelSelection: modelSelection,
                reachability: reachability,
                memoryManager: memoryManager,
                bookmarkStore: bookmarkStore,
                vaultStore: vaultStore,
                auditLog: auditLog,
                policy: securityCapabilities.policy,
                toolApprovalManager: securityCapabilities.toolApprovalManager
            )
        case .timeline:
            TimelineView(auditLog: auditLog)
        case .vault:
            VaultView(vaultStore: vaultStore)
        case .models:
            ModelsView(
                modelRegistry: modelRegistry,
                modelSelection: modelSelection,
                resourcePolicy: resourcePolicy,
                modelLoader: modelLoader,
                reachability: reachability
            )
        case .settings:
            SettingsView(
                securityCapabilities: securityCapabilities,
                auditLog: auditLog,
                exportAction: exportAction,
                modelRegistry: modelRegistry,
                modelSelection: modelSelection,
                resourcePolicy: resourcePolicy,
                reachability: reachability,
                bookmarkStore: bookmarkStore,
                memoryManager: memoryManager,
                untrustedParsingPolicy: appState.untrustedParsingPolicy,
                messagingPolicy: appState.messagingPolicy,
                webFilterStore: appState.webFilterStore,
                openCircuitsStore: appState.openCircuitsStore
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
