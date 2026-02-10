import SwiftUI
import BadgerRuntime
import UniformTypeIdentifiers

/// Model selection tab for the Settings window.
///
/// Separates cloud and local models into distinct sections with
/// hardware‑aware fit indicators. Selection is always explicit —
/// choosing a model does **not** load it. Loading requires pressing
/// a separate "Load Model" button.
struct ModelSelectionTab: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var cloudModels: [ModelDescriptor] = []
    @State private var localModels: [ModelDescriptor] = []
    @State private var showModelImporter = false
    @State private var showUnverifiedConfirmation = false
    @State private var pendingUnverifiedModel: ModelDescriptor?

    var body: some View {
        Form {
            // MARK: - Active Model Banner

            activeModelBanner

            // MARK: - Cloud Models

            Section {
                ForEach(cloudModels) { model in
                    cloudModelRow(model)
                }
            } header: {
                Label("Cloud Models", systemImage: "cloud.fill")
            } footer: {
                Text("Cloud models process on remote servers. Your data is redacted before sending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Local Models

            Section {
                ForEach(localModels) { model in
                    localModelRow(model)
                }

                Button {
                    showModelImporter = true
                } label: {
                    Label("Add Local Model…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.accent)
            } header: {
                Label("Local Models (On‑Device)", systemImage: "desktopcomputer")
            } footer: {
                Text("Local models run entirely on your Mac. They require available RAM and are never sent to the cloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Actions

            Section {
                HStack {
                    Button("Load Model") {
                        if let model = coordinator.selectedModel,
                           !model.isVerified {
                            pendingUnverifiedModel = model
                            showUnverifiedConfirmation = true
                        } else {
                            coordinator.loadSelectedModel()
                        }
                    }
                    .disabled(coordinator.selectedModel == nil
                              || coordinator.selectedModel?.location == .cloud)
                    .help("Load the selected local model into memory")

                    Button("Unload") {
                        coordinator.unloadModel()
                    }
                    .help("Free memory by unloading the current local model")

                    Spacer()

                    if coordinator.isValidatingModel {
                        ProgressView()
                            .controlSize(.small)
                        Text("Validating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Model Actions", systemImage: "play.circle")
            }

            // MARK: - Low RAM Warning

            if isLowRAMSystem {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Low Memory System")
                                .font(.headline)
                            Text("Your Mac has limited RAM. Cloud models are recommended for the best experience. Local models may cause instability.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "safetensors") ?? .data,
                UTType(filenameExtension: "gguf") ?? .data,
                .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                coordinator.importCustomModel(url)
            }
        }
        .confirmationDialog(
            "This model is unverified",
            isPresented: $showUnverifiedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Load Anyway") {
                coordinator.loadSelectedModel()
                pendingUnverifiedModel = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUnverifiedModel = nil
            }
        } message: {
            Text("This model does not come from a verified source. Unverified models may behave unpredictably. Are you sure you want to load it?")
        }
        .task {
            await loadCatalog()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func cloudModelRow(_ model: ModelDescriptor) -> some View {
        Button {
            coordinator.selectCloudModel(model)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .fontWeight(isSelected(model) ? .semibold : .regular)
                        Text("· \(model.provider)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(model.capabilityTier.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                        Text("Cloud")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected(model) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name), \(model.provider), \(model.capabilityTier.displayName), Cloud")
    }

    @ViewBuilder
    private func localModelRow(_ model: ModelDescriptor) -> some View {
        let budget = coordinator.systemStatus.localModelBudgetBytes
        let fits = model.fitsInBudget(budget)

        Button {
            if fits {
                coordinator.selectLocalModel(model)
            } else {
                coordinator.lastUserNotice = UserNotice(
                    title: "Model Too Large",
                    detail: "\(model.name) requires \(model.formattedRAM) but your Mac's memory budget is \(formatBytes(budget)). Try a smaller model or close other apps.",
                    severity: .warning
                )
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .fontWeight(isSelected(model) ? .semibold : .regular)
                        if !model.isVerified {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .help("Unverified model")
                        }
                        if model.isUserSupplied {
                            Text("Custom")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.15), in: Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        if let q = model.quantization {
                            Text(q)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(model.formattedRAM)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fits ? "✅ Fits on this Mac" : "⚠️ May exceed memory")
                            .font(.caption2)
                            .foregroundStyle(fits ? .green : .orange)
                    }
                }

                Spacer()

                if isSelected(model) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accent)
                }

                if !fits {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red.opacity(0.6))
                        .help("This model may not fit in available memory")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!fits)
        .accessibilityLabel("\(model.name), \(model.formattedRAM), \(fits ? "fits on this Mac" : "may exceed available memory")")
    }

    // MARK: - Active Model Banner

    @ViewBuilder
    private var activeModelBanner: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(coordinator.systemStatus.activeModelName)
                        .font(.headline)
                }
                Spacer()
                Text(coordinator.systemStatus.activeModelLocation == .local ? "On‑Device" : "Cloud")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        coordinator.systemStatus.activeModelLocation == .local
                            ? Color.green.opacity(0.15)
                            : Color.blue.opacity(0.15),
                        in: Capsule()
                    )
            }
        } header: {
            Label("Active Model", systemImage: "brain.head.profile")
        }
    }

    // MARK: - Helpers

    private func isSelected(_ model: ModelDescriptor) -> Bool {
        coordinator.selectedModel?.id == model.id
    }

    private var isLowRAMSystem: Bool {
        coordinator.systemStatus.totalRAMBytes <= 8 * 1024 * 1024 * 1024
    }

    private func loadCatalog() async {
        cloudModels = await coordinator.modelCatalog.cloudModels
        localModels = await coordinator.modelCatalog.localModels
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "Unavailable" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}
