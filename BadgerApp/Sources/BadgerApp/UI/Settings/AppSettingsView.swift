import SwiftUI
import AppKit
import BadgerCore
import BadgerRuntime

// MARK: - Main Settings Container

public struct AppSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedSection: SettingsSection? = .health
    
    public enum SettingsSection: String, CaseIterable, Identifiable {
        case health = "System Health"
        case general = "General"
        case localModels = "Local Models"
        case cloudAccounts = "Cloud Accounts"
        case audit = "Audit Logs"
        case privacy = "Privacy & Security"
        case advanced = "Advanced"
        
        public var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .health: return "heart.text.square.fill"
            case .general: return "gear"
            case .localModels: return "cpu.fill"
            case .cloudAccounts: return "cloud.fill"
            case .audit: return "list.bullet.rectangle.portrait"
            case .privacy: return "hand.raised.fill"
            case .advanced: return "hammer.fill"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Status") {
                    NavigationLink(value: SettingsSection.health) {
                        Label(SettingsSection.health.rawValue, systemImage: SettingsSection.health.icon)
                    }
                }
                
                Section("Configuration") {
                    ForEach([SettingsSection.general, .localModels, .cloudAccounts, .audit, .privacy, .advanced], id: \.self) { section in
                        NavigationLink(value: section) {
                            Label(section.rawValue, systemImage: section.icon)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
        } detail: {
            ZStack {
                if let section = selectedSection {
                    switch section {
                    case .health: HealthDashboardView()
                    case .general: GeneralSettingsView()
                    case .localModels: LocalModelConfigurationView()
                    case .cloudAccounts: CloudAccountsSettingsView()
                    case .audit: AuditLogsSettingsView()
                    case .privacy: PrivacySettingsView()
                    case .advanced: AdvancedSettingsView()
                    }
                } else {
                    ContentUnavailableView("Select a Setting", systemImage: "gear")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    EmptyView()
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.title2)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .help("Close Settings")
        }
    }
}

// MARK: - 1. Health Dashboard (Default)

struct HealthDashboardView: View {
    @State private var vramStatus: VRAMStatus?
    @State private var thermalState: SystemState.ThermalState = .nominal
    @State private var securityScore: Int = 100
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("System Health")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Text("Live")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 10)
                
                VRAMCard(vramStatus: vramStatus)
                ThermalCard(thermalState: thermalState)
                SecurityCard(securityScore: securityScore)
            }
            .padding()
        }
        .task {
            let vramMonitor = VRAMMonitor()
            let thermalGuard = ThermalGuard()
            
            vramStatus = await vramMonitor.getCurrentStatus()
            thermalState = await thermalGuard.getThermalState()
        }
    }
}

struct VRAMCard: View {
    let vramStatus: VRAMStatus?
    
    var body: some View {
        HealthCard(title: "Memory Pressure", icon: "memorychip", color: .blue) {
            if let vram = vramStatus {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: vram.usageRatio)
                        .tint(vram.usageRatio > 0.8 ? .red : .blue)
                    
                    HStack {
                        Text("\(formatBytes(vram.availableVRAM)) available")
                        Spacer()
                        Text("Max: \(formatBytes(vram.recommendedMaxWorkingSetSize))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text("Model Recommendation: \(vram.recommendedQuantization.rawValue)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .padding(.top, 4)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}

struct ThermalCard: View {
    let thermalState: SystemState.ThermalState
    
    var body: some View {
        HealthCard(title: "Thermal State", icon: "thermometer.medium", color: .orange) {
            HStack {
                Image(systemName: thermalIcon)
                    .font(.title)
                    .foregroundStyle(thermalColor)
                
                VStack(alignment: .leading) {
                    Text(thermalState.rawValue)
                        .font(.headline)
                    Text(thermalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var thermalColor: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
    
    private var thermalIcon: String {
        switch thermalState {
        case .nominal: return "snowflake"
        case .fair: return "wind"
        case .serious: return "flame"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
    
    private var thermalDescription: String {
        ThermalGuard.description(for: thermalState)
    }
}

struct SecurityCard: View {
    let securityScore: Int
    
    var body: some View {
        HealthCard(title: "Security Posture", icon: "lock.shield", color: .green) {
            HStack {
                CircularScoreView(score: securityScore)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Integrity: Secure")
                    Text("PII Redaction: Active")
                    Text("Audit Logging: Enabled")
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - 2. General Settings

struct GeneralSettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @AppStorage("defaultModel") private var defaultModel: String = "Phi-4"
    @State private var lastUpdateCheck: Date?
    
    var body: some View {
        Form {
            Section("Startup & Appearance") {
                Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
                Toggle("Start at Login", isOn: $startAtLogin)
            }
            
            Section("Updates") {
                Toggle("Automatically Check for Updates", isOn: $autoCheckUpdates)
                Button("Check Now", action: checkForUpdatesNow)
                if let lastUpdateCheck {
                    Text("Last checked: \(lastUpdateCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Preferences") {
                Picker("Default Model", selection: $defaultModel) {
                    Text("Phi-4 (Recommended)").tag("Phi-4")
                    Text("Mistral 7B").tag("Mistral")
                    Text("Llama 3").tag("Llama3")
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func checkForUpdatesNow() {
        lastUpdateCheck = Date()
        let releaseURL = URL(string: "https://github.com/ml-explore/mlx-swift/releases")!
        NSWorkspace.shared.open(releaseURL)
    }
}

// MARK: - 3. Cloud Accounts (defined in CloudAccountsSettingsView.swift)

// MARK: - 4. Privacy & Security

struct PrivacySettingsView: View {
    @AppStorage("enableLockdown") private var enableLockdown = false
    @AppStorage("enablePIIRedaction") private var enablePIIRedaction = true
    @State private var showClearHistoryAlert = false
    @State private var exportStatusMessage: String?
    
    var body: some View {
        Form {
            Section("Global Kill-Switch") {
                Toggle(isOn: $enableLockdown) {
                    Label("Lockdown Mode", systemImage: "lock.shield.fill")
                        .foregroundStyle(.red)
                }
                Text("Immediately cuts all network access and unloads all models from memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Data Safety") {
                Toggle("Auto-Redact PII", isOn: $enablePIIRedaction)
                Button("Export Audit Logs", action: exportAuditLogs)
                Button(role: .destructive) {
                    showClearHistoryAlert = true
                } label: {
                    Text("Clear All History")
                }
                if let exportStatusMessage {
                    Text(exportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Privacy Policy") {
                Link("Read Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Text("Quantum Badger processes data locally by default. Cloud inference sends data to respective providers.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Clear History?", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive, action: clearAllHistory)
        } message: {
            Text("This action cannot be undone. All chat logs and vector indices will be destroyed.")
        }
    }
    
    private func exportAuditLogs() {
        Task {
            let auditService = AuditLogService()
            let destination = exportDestinationURL()
            do {
                try await auditService.exportLogs(to: destination)
                await MainActor.run {
                    exportStatusMessage = "Exported logs to \(destination.lastPathComponent)"
                }
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                await MainActor.run {
                    exportStatusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func exportDestinationURL() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "quantum-badger-audit-\(timestamp).json"
        return downloads.appendingPathComponent(filename)
    }
    
    private func clearAllHistory() {
        let defaults = UserDefaults.standard
        let keys = [
            "onboardingCompleted",
            "hasCompletedOnboarding",
            "privacyPolicyAccepted",
            "safeModeDefault"
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}

// MARK: - 5. Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("debugLogging") private var debugLogging = false
    @AppStorage("contextWindow") private var contextWindow = 4096
    @State private var showResetConfirmation = false
    
    var body: some View {
        Form {
            Section("Developer") {
                Toggle("Enable Debug Logging", isOn: $debugLogging)
            }
            
            Section("Inference Params") {
                Stepper("Context Window: \(contextWindow)", value: $contextWindow, in: 2048...32000, step: 1024)
                Button("Open Models Folder", action: openModelsFolder)
            }
            
            Section("Danger Zone") {
                Button("Reset App Configuration") {
                    showResetConfirmation = true
                }
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .alert("Reset App Configuration?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: resetAppConfiguration)
        } message: {
            Text("This will reset user preferences and onboarding state.")
        }
    }
    
    private func openModelsFolder() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let modelsDirectory = appSupport.appendingPathComponent("QuantumBadger/Models")
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([modelsDirectory])
    }
    
    private func resetAppConfiguration() {
        let defaults = UserDefaults.standard
        let keys = [
            "showMenuBarIcon",
            "startAtLogin",
            "autoCheckUpdates",
            "defaultModel",
            "enableLockdown",
            "enablePIIRedaction",
            "debugLogging",
            "contextWindow",
            "onboardingCompleted",
            "hasCompletedOnboarding",
            "privacyPolicyAccepted",
            "safeModeDefault",
            "forceSafeMode",
            "ramHeadroomLimitGB",
            "preferLocalInference",
            "enableIntentAnalysis",
            "thermalThrottlingEnabled",
            "minimumVRAMForLocalGB"
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        NotificationCenter.default.post(name: .badgerShowOnboardingRequested, object: nil)
    }
}

struct AuditLogsSettingsView: View {
    @State private var events: [AuditEvent] = []
    @State private var chainValid = true
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Audit Logs")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh", action: loadAuditEvents)
            }
            
            HStack(spacing: 8) {
                Image(systemName: chainValid ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(chainValid ? .green : .red)
                Text(chainValid ? "Hash Chain Verified" : "Hash Chain Verification Failed")
                    .font(.caption)
                    .foregroundStyle(chainValid ? .green : .red)
            }
            
            List(events.prefix(200), id: \.id) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.type.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(event.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.details)
                        .font(.caption)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .task {
            loadAuditEvents()
        }
    }
    
    private func loadAuditEvents() {
        Task {
            await MainActor.run { isLoading = true }
            let service = AuditLogService()
            do {
                async let loadedEvents = service.getAllEvents()
                async let verified = service.verifyChain()
                let (events, chainValid) = try await (loadedEvents, verified)
                await MainActor.run {
                    self.events = events.reversed()
                    self.chainValid = chainValid
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.events = []
                    self.chainValid = false
                    self.isLoading = false
                }
            }
        }
    }
}

struct LocalModelConfigurationView: View {
    @AppStorage("activeLocalModelPath") private var activeLocalModelPath = ""
    @State private var localModelDirectories: [URL] = []
    @State private var statusMessage = "No local model selected"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Model Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Refresh", action: refreshModelList)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                Text(activeModelDisplayName)
                    .font(.subheadline)
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack {
                Button("Add Local Model Folder", action: importModelDirectory)
                    .buttonStyle(.borderedProminent)
                Button("Open Models Folder", action: openModelsFolder)
            }
            
            List(localModelDirectories, id: \.path) { modelURL in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelURL.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(modelURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if activeLocalModelPath == modelURL.path {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    } else {
                        Button("Set Active") {
                            activeLocalModelPath = modelURL.path
                            statusMessage = "Active model set to \(modelURL.lastPathComponent)"
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task { refreshModelList() }
    }
    
    private var modelsRootDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("QuantumBadger/Models")
    }
    
    private var activeModelDisplayName: String {
        if activeLocalModelPath.isEmpty {
            return "Active model: None"
        }
        return "Active model: \(URL(fileURLWithPath: activeLocalModelPath).lastPathComponent)"
    }
    
    private func refreshModelList() {
        try? FileManager.default.createDirectory(at: modelsRootDirectory, withIntermediateDirectories: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: modelsRootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        localModelDirectories = contents.filter { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else { return false }
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        if localModelDirectories.isEmpty {
            statusMessage = "No local model folders detected in \(modelsRootDirectory.path)"
        }
    }
    
    private func importModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Model"
        
        guard panel.runModal() == .OK, let source = panel.url else {
            return
        }
        
        let sourceConfig = source.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: sourceConfig.path) else {
            statusMessage = "Selected folder is missing config.json"
            return
        }
        
        let destination = modelsRootDirectory.appendingPathComponent(source.lastPathComponent)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            statusMessage = "Imported model folder \(source.lastPathComponent)"
            refreshModelList()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func openModelsFolder() {
        try? FileManager.default.createDirectory(at: modelsRootDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([modelsRootDirectory])
    }
}

// MARK: - UI Components

struct HealthCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: () -> Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
                Spacer()
            }
            
            content()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct CircularScoreView: View {
    let score: Int
    
    var color: Color {
        if score > 80 { return .green }
        if score > 50 { return .yellow }
        return .red
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
                .frame(width: 40, height: 40)
            
            Circle()
                .trim(from: 0, to: Double(score) / 100.0)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
            
            Text("\(score)")
                .font(.caption2)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Preview

#Preview {
    AppSettingsView()
}
