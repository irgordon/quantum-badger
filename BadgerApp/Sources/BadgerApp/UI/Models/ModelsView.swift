import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Models View

public struct ModelsView: View {
    @State private var viewModel = ModelsViewModel()
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Settings Section
                settingsSection
                
                // Downloaded Models Summary
                downloadedSummarySection
                
                // Available Models
                availableModelsSection
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
        .navigationTitle("Models")
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Model Manager")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            
            Text("Download and configure local AI models")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Settings
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Shadow Router Settings")
                    .font(.headline)
                
                Spacer()
                
                Button("Reset to Defaults") {
                    viewModel.resetToDefaults()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            VStack(spacing: 16) {
                // Safe Mode Toggle
                Toggle(isOn: $viewModel.shadowRouterSettings.forceSafeMode) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Force Safe Mode")
                                .font(.subheadline)
                            Text("Always use cloud inference (bypasses local models)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: viewModel.shadowRouterSettings.forceSafeMode) { _, _ in
                    viewModel.saveSettings()
                }
                
                Divider()
                
                // RAM Headroom Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "memorychip")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        
                        Text("RAM Headroom Limit")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f GB", viewModel.shadowRouterSettings.ramHeadroomLimitGB))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $viewModel.shadowRouterSettings.ramHeadroomLimitGB,
                        in: 1...8,
                        step: 0.5
                    ) {
                        Text("RAM Headroom")
                    } minimumValueLabel: {
                        Text("1 GB")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("8 GB")
                            .font(.caption)
                    }
                    .onChange(of: viewModel.shadowRouterSettings.ramHeadroomLimitGB) { _, _ in
                        viewModel.saveSettings()
                    }
                    
                    Text("Minimum free RAM required for local inference")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Minimum VRAM Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "gpu")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        
                        Text("Minimum VRAM for Local")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f GB", viewModel.shadowRouterSettings.minimumVRAMForLocalGB))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $viewModel.shadowRouterSettings.minimumVRAMForLocalGB,
                        in: 4...16,
                        step: 1
                    ) {
                        Text("Min VRAM")
                    } minimumValueLabel: {
                        Text("4 GB")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("16 GB")
                            .font(.caption)
                    }
                    .onChange(of: viewModel.shadowRouterSettings.minimumVRAMForLocalGB) { _, _ in
                        viewModel.saveSettings()
                    }
                    
                    Text("Minimum GPU memory for loading local models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Toggles Row
                HStack(spacing: 24) {
                    Toggle(isOn: $viewModel.shadowRouterSettings.preferLocalInference) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prefer Local")
                                .font(.subheadline)
                            Text("When possible")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: viewModel.shadowRouterSettings.preferLocalInference) { _, _ in
                        viewModel.saveSettings()
                    }
                    
                    Toggle(isOn: $viewModel.shadowRouterSettings.enableIntentAnalysis) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intent Analysis")
                                .font(.subheadline)
                            Text("Use Cloud Mini")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: viewModel.shadowRouterSettings.enableIntentAnalysis) { _, _ in
                        viewModel.saveSettings()
                    }
                    
                    Toggle(isOn: $viewModel.shadowRouterSettings.thermalThrottlingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thermal Throttle")
                                .font(.subheadline)
                            Text("Auto offload")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: viewModel.shadowRouterSettings.thermalThrottlingEnabled) { _, _ in
                        viewModel.saveSettings()
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Downloaded Summary
    
    private var downloadedSummarySection: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Downloaded",
                value: "\(viewModel.downloadedCount)",
                subtitle: "models",
                icon: "checkmark.circle",
                color: .green
            )
            
            StatCard(
                title: "Storage Used",
                value: String(format: "%.1f", viewModel.totalDownloadedSize),
                subtitle: "GB",
                icon: "externaldrive",
                color: .blue
            )
            
            StatCard(
                title: "Available",
                value: "\(viewModel.availableModels.count - viewModel.downloadedCount)",
                subtitle: "to download",
                icon: "arrow.down.circle",
                color: .orange
            )
        }
    }
    
    // MARK: - Available Models
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Models")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.downloadedCount > 0 {
                    Button("Download All Missing") {
                        downloadAllMissing()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            
            LazyVStack(spacing: 12) {
                ForEach(viewModel.availableModels) { modelInfo in
                    ModelDownloadRow(
                        modelInfo: modelInfo,
                        onDownload: {
                            Task {
                                await viewModel.downloadModel(modelInfo)
                            }
                        },
                        onCancel: {
                            viewModel.cancelDownload(for: modelInfo.modelClass)
                        },
                        onDelete: {
                            viewModel.deleteModel(modelInfo.modelClass)
                        }
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helper Methods
    
    private func downloadAllMissing() {
        for modelInfo in viewModel.availableModels where !modelInfo.isDownloaded {
            Task {
                await viewModel.downloadModel(modelInfo)
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
            }
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ModelDownloadRow: View {
    let modelInfo: ModelsViewModel.ModelDownloadInfo
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Model Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(modelInfo.isDownloaded ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                if modelInfo.isDownloaded {
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            
            // Model Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(modelInfo.name)
                        .font(.headline)
                    
                    if modelInfo.isDownloaded {
                        Text("Ready")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                
                Text(modelInfo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(modelInfo.formattedSize, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("·")
                        .foregroundStyle(.secondary)
                    
                    Text(modelInfo.huggingFaceRepo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Download/Status Button
            VStack(alignment: .trailing, spacing: 8) {
                if modelInfo.isDownloaded {
                    Menu {
                        Button("Show in Finder", action: {})
                        Divider()
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                } else if case .downloading = modelInfo.downloadState {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(width: 44)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(modelInfo.isDownloaded ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .overlay {
            // Download Progress Overlay
            if case .downloading(let progress, _, _) = modelInfo.downloadState {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                            Rectangle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: geometry.size.width * progress)
                                .animation(.linear(duration: 0.3), value: progress)
                        }
                        .frame(height: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ModelsView()
        .frame(minWidth: 800, minHeight: 600)
}
