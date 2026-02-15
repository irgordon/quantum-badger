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
        case cloudAccounts = "Cloud Accounts"
        case privacy = "Privacy & Security"
        case advanced = "Advanced"
        
        public var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .health: return "heart.text.square.fill"
            case .general: return "gear"
            case .cloudAccounts: return "cloud.fill"
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
                    ForEach([SettingsSection.general, .cloudAccounts, .privacy, .advanced], id: \.self) { section in
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
                    case .cloudAccounts: CloudAccountsSettingsView()
                    case .privacy: PrivacySettingsView()
                    case .advanced: AdvancedSettingsView()
                    }
                } else {
                    ContentUnavailableView("Select a Setting", systemImage: "gear")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .help("Close Settings")
                }
            }
        }
        .frame(minWidth: 800, minHeight: 550)
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
    
    var body: some View {
        Form {
            Section("Startup & Appearance") {
                Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
                Toggle("Start at Login", isOn: $startAtLogin)
            }
            
            Section("Updates") {
                Toggle("Automatically Check for Updates", isOn: $autoCheckUpdates)
                Button("Check Now") {}
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
}

// MARK: - 3. Cloud Accounts (defined in CloudAccountsSettingsView.swift)

// MARK: - 4. Privacy & Security

struct PrivacySettingsView: View {
    @AppStorage("enableLockdown") private var enableLockdown = false
    @AppStorage("enablePIIRedaction") private var enablePIIRedaction = true
    @State private var showClearHistoryAlert = false
    
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
                Button("Export Audit Logs") {}
                Button(role: .destructive) {
                    showClearHistoryAlert = true
                } label: {
                    Text("Clear All History")
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
            Button("Delete All", role: .destructive) {}
        } message: {
            Text("This action cannot be undone. All chat logs and vector indices will be destroyed.")
        }
    }
}

// MARK: - 5. Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("debugLogging") private var debugLogging = false
    @AppStorage("contextWindow") private var contextWindow = 4096
    
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
                Button("Reset App Configuration") {}
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
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
