import SwiftUI
import QuantumBadgerRuntime
import UniformTypeIdentifiers
import AppKit

struct ModelsView: View {
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let resourcePolicy: ResourcePolicyStore
    let modelLoader: ModelLoader
    let reachability: NetworkReachabilityMonitor

    private let cloudAuthManager = CloudAuthManager(anchorProvider: {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
    })
    private let keychain = KeychainStore()
    @State private var modelDraft = ModelDraft()
    @State private var modelLimitsDraft = ModelLimits(maxContextTokens: 8192, maxTemperature: 1.2, maxTokens: 2048)
    @State private var isModelFileImporterPresented = false
    @State private var fileImportErrorMessage: String?
    @State private var isShowingCloudSetup = false
    @State private var cloudModelName = ""
    @State private var cloudApiKey = ""
    @State private var cloudErrorMessage: String?
    @State private var modelFixTarget: LocalModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Models")
                .font(.title)
                .fontWeight(.semibold)

            ModelLimitsView(limits: $modelLimitsDraft) {
                modelRegistry.updateLimits(modelLimitsDraft)
            }

            Divider()

            let systemCheck = SystemCheck.evaluate(minMemoryGB: resourcePolicy.policy.minAvailableMemoryGB)
            GroupBox("Available Memory") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(systemCheck.memoryGB) GB available")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Threshold: \(resourcePolicy.policy.minAvailableMemoryGB) GB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if resourcePolicy.memoryPressure != .normal {
                        Text(resourcePolicy.memoryPressure == .critical
                             ? "Memory pressure is critical. Loading models is paused."
                             : "Memory pressure is high. Heavy models may not load.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if !systemCheck.hasEnoughMemory {
                        Text("Warning: available memory is below your threshold. Large models may be unstable.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            ActiveModelPicker(
                models: modelRegistry.localModels(),
                selectionId: $modelSelection.activeModelId
            )

            Divider()

            OfflineModelCTA(
                shouldShow: !modelSelection.didDismissOfflineDownloadCTA && modelRegistry.localModels().isEmpty,
                onDismiss: { modelSelection.setDidDismissOfflineDownloadCTA(true) },
                onChooseFile: { isModelFileImporterPresented = true }
            )

            Divider()

            ModelForm(draft: $modelDraft) {
                let inferredEngine = LocalModel.inferEngine(from: modelDraft.path, isCloud: modelDraft.isCloud)
                let model = LocalModel(
                    name: modelDraft.name,
                    path: modelDraft.path,
                    bookmarkData: modelDraft.bookmarkData,
                    hash: modelDraft.hash,
                    engine: inferredEngine,
                    contextTokens: modelDraft.contextTokens,
                    temperatureCap: modelDraft.temperatureCap,
                    maxTokens: modelDraft.maxTokens,
                    cpuThreads: modelDraft.cpuThreads,
                    gpuLayers: modelDraft.gpuLayers,
                    expectedLatencySeconds: modelDraft.expectedLatencySeconds,
                    isCloud: modelDraft.isCloud,
                    maxPromptChars: modelDraft.maxPromptChars,
                    redactSensitivePrompts: modelDraft.redactSensitivePrompts,
                    provenance: modelDraft.provenance
                )
                modelRegistry.addModel(model)
                modelDraft = ModelDraft()
            } onChooseFile: {
                isModelFileImporterPresented = true
            }

            Button("Connect Cloud Model…") {
                Task { await startCloudSetup() }
            }
            .buttonStyle(.bordered)

            let visibleModels = modelsForDisplay()
            if visibleModels.isEmpty {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "cpu",
                    description: Text("Add a local model to get started.")
                )
            } else {
                List {
                    ForEach(visibleModels) { model in
                        let isLocked = modelRegistry.isModelLocked(model.id)
                        ModelRow(
                            model: model,
                            isMissing: !modelRegistry.isModelPathReachable(model),
                            onFix: { prepareFix(for: model) },
                            isLocked: isLocked,
                            onUnload: { modelLoader.unloadModel(model.id) }
                        )
                            .swipeActions {
                                Button(role: .destructive) {
                                    if !modelRegistry.removeModel(model) {
                                        fileImportErrorMessage = "That model is currently in use. Stop it before removing."
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            modelLimitsDraft = modelRegistry.limits
            if let activeId = modelSelection.activeModelId,
               !modelRegistry.localModels().contains(where: { $0.id == activeId }) {
                modelSelection.setActiveModel(nil)
            }
        }
        .fileImporter(
            isPresented: $isModelFileImporterPresented,
            allowedContentTypes: ModelDraft.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    if let target = modelFixTarget {
                        var updated = target
                        updated.bookmarkData = bookmarkData
                        updated.path = url.path
                        modelRegistry.updateModel(updated)
                        modelFixTarget = nil
                    } else {
                        modelDraft.bookmarkData = bookmarkData
                        modelDraft.path = url.path
                        modelDraft.fileName = url.lastPathComponent
                    }
                } catch {
                    fileImportErrorMessage = "We couldn’t access that file. Choose a file from a location you’ve allowed."
                }
            case .failure:
                fileImportErrorMessage = "We couldn’t add that file. Please try again."
            }
        }
        .alert("Can’t Add Model", isPresented: Binding(
            get: { fileImportErrorMessage != nil },
            set: { _ in fileImportErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(fileImportErrorMessage ?? "Something went wrong.")
        }
        .alert("Cloud Model Setup", isPresented: Binding(
            get: { cloudErrorMessage != nil },
            set: { _ in cloudErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cloudErrorMessage ?? "Please try again.")
        }
        .sheet(isPresented: $isShowingCloudSetup) {
            CloudModelSetupSheet(
                modelName: $cloudModelName,
                apiKey: $cloudApiKey,
                onSave: saveCloudModel,
                onCancel: { isShowingCloudSetup = false }
            )
        }
    }

    private func modelsForDisplay() -> [LocalModel] {
        if !reachability.isReachable && modelSelection.hideCloudModelsWhenOffline {
            return modelRegistry.localModels()
        }
        return modelRegistry.models
    }

    private func prepareFix(for model: LocalModel) {
        modelFixTarget = model
        isModelFileImporterPresented = true
    }

    @MainActor
    private func startCloudSetup() async {
        do {
            try await cloudAuthManager.authenticate()
            cloudModelName = ""
            cloudApiKey = ""
            isShowingCloudSetup = true
        } catch {
            cloudErrorMessage = "Sign-in failed. Please try again."
        }
    }

    @MainActor
    private func saveCloudModel() {
        guard !cloudModelName.isEmpty, !cloudApiKey.isEmpty else { return }
        guard let userId = cloudAuthManager.lastUserIdentifier else {
            cloudErrorMessage = "Sign-in details are missing. Please try again."
            return
        }
        let model = LocalModel(
            name: cloudModelName,
            path: "cloud",
            bookmarkData: nil,
            hash: "",
            engine: .cloud,
            contextTokens: modelLimitsDraft.maxContextTokens,
            temperatureCap: modelLimitsDraft.maxTemperature,
            maxTokens: modelLimitsDraft.maxTokens,
            cpuThreads: 0,
            gpuLayers: 0,
            expectedLatencySeconds: 6,
            isCloud: true,
            provenance: "Cloud"
        )
        modelRegistry.addModel(model)
        do {
            try keychain.saveSecret(cloudApiKey, label: "cloud-api-key-\(model.id.uuidString)")
            try keychain.saveSecretOwner(userId, label: "cloud-api-key-\(model.id.uuidString)")
        } catch {
            cloudErrorMessage = "Couldn’t save the API key."
        }
        isShowingCloudSetup = false
    }
}

struct ModelLimitsView: View {
    @Binding var limits: ModelLimits
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limits")
                .font(.headline)
            HStack {
                Stepper("Max Context: \(limits.maxContextTokens)", value: $limits.maxContextTokens, in: 1024...65536, step: 512)
                Stepper("Max Tokens: \(limits.maxTokens)", value: $limits.maxTokens, in: 256...16384, step: 256)
            }
            HStack {
                Slider(value: $limits.maxTemperature, in: 0.1...2.0, step: 0.05) {
                    Text("Max Temp")
                }
                Text(String(format: "%.2f", limits.maxTemperature))
                    .frame(width: 50, alignment: .leading)
            }
            Button("Save Limits", action: save)
                .buttonStyle(.bordered)
        }
    }
}

struct ModelForm: View {
    @Binding var draft: ModelDraft
    let onAdd: () -> Void
    let onChooseFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Model")
                .font(.headline)
            HStack {
                TextField("Name", text: $draft.name)
                Button(draft.fileName.isEmpty ? "Choose Model File…" : draft.fileName) {
                    onChooseFile()
                }
            }
            HStack {
                TextField("File checksum (optional)", text: $draft.hash)
                TextField("Source", text: $draft.provenance)
            }
            HStack {
                Stepper("Max prompt chars: \(draft.maxPromptChars)", value: $draft.maxPromptChars, in: 500...8000, step: 250)
                Toggle("Redact sensitive prompts", isOn: $draft.redactSensitivePrompts)
            }
            Toggle("Cloud model", isOn: $draft.isCloud)
            HStack {
                Stepper("Context: \(draft.contextTokens)", value: $draft.contextTokens, in: 1024...65536, step: 512)
                Stepper("Max Tokens: \(draft.maxTokens)", value: $draft.maxTokens, in: 256...16384, step: 256)
            }
            HStack {
                Slider(value: $draft.temperatureCap, in: 0.1...2.0, step: 0.05) {
                    Text("Max Temperature")
                }
                Text(String(format: "%.2f", draft.temperatureCap))
                    .frame(width: 50, alignment: .leading)
                Stepper("CPU Threads: \(draft.cpuThreads)", value: $draft.cpuThreads, in: 1...16)
                Stepper("GPU Layers: \(draft.gpuLayers)", value: $draft.gpuLayers, in: 0...64)
            }
            Stepper(
                "Expected latency: \(draft.expectedLatencySeconds, specifier: "%.0f")s",
                value: $draft.expectedLatencySeconds,
                in: 5...90,
                step: 5
            )
            Button("Add Model", action: onAdd)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.isEmpty || draft.bookmarkData == nil)
        }
        .onChange(of: draft.isCloud) { _, newValue in
            if newValue {
                draft.expectedLatencySeconds = 6
            } else if draft.expectedLatencySeconds < 10 {
                draft.expectedLatencySeconds = 12
            }
        }
    }
}

struct ModelRow: View {
    let model: LocalModel
    let isMissing: Bool
    let onFix: () -> Void
    let isLocked: Bool
    let onUnload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.name)
                .font(.headline)
            Text(model.path)
                .font(.caption)
                .foregroundColor(.secondary)
            if isMissing {
                HStack(spacing: 8) {
                    Label("File not found. Select the model again.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Fix…", action: onFix)
                        .buttonStyle(.link)
                }
            }
            if isLocked {
                HStack(spacing: 8) {
                    Label("In use", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Stop/Unload", action: onUnload)
                        .buttonStyle(.link)
                }
            }
            HStack(spacing: 12) {
                Label("Context \(model.contextTokens)", systemImage: "square.stack.3d.up")
                Label("Temp cap \(String(format: "%.2f", model.temperatureCap))", systemImage: "thermometer")
                Label("Tokens \(model.maxTokens)", systemImage: "text.justify")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

struct ModelDraft {
    var name: String = ""
    var path: String = ""
    var fileName: String = ""
    var bookmarkData: Data? = nil
    var hash: String = ""
    var contextTokens: Int = 8192
    var temperatureCap: Double = 1.0
    var maxTokens: Int = 2048
    var cpuThreads: Int = 4
    var gpuLayers: Int = 0
    var expectedLatencySeconds: Double = 12
    var provenance: String = ""
    var isCloud: Bool = false
    var maxPromptChars: Int = 2000
    var redactSensitivePrompts: Bool = true

    static var allowedContentTypes: [UTType] {
        let extensions = ["gguf", "bin", "safetensors", "mlx"]
        let customTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        return customTypes + [.data]
    }
}

private struct ActiveModelPicker: View {
    let models: [LocalModel]
    @Binding var selectionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Model")
                .font(.headline)
            Picker("Active Model", selection: $selectionId) {
                Text("None").tag(UUID?.none)
                ForEach(models) { model in
                    Text(model.name).tag(UUID?.some(model.id))
                }
            }
            .pickerStyle(.menu)
            Text("Active models must be local.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct OfflineModelCTA: View {
    let shouldShow: Bool
    let onDismiss: () -> Void
    let onChooseFile: () -> Void

    var body: some View {
        guard shouldShow else { return EmptyView() }
        let check = SystemCheck.evaluate()
        return GroupBox("Download an Offline Model") {
            VStack(alignment: .leading, spacing: 8) {
                Text("You’re offline-ready when you add a local model.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Memory: \(check.memoryGB) GB")
                    .font(.caption)
                    .foregroundColor(check.hasEnoughMemory ? .secondary : .red)
                Text("Disk available: \(check.diskGB) GB")
                    .font(.caption)
                    .foregroundColor(check.hasEnoughDisk ? .secondary : .red)
                HStack {
                    Button("Choose Model File…", action: onChooseFile)
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct CloudModelSetupSheet: View {
    @Binding var modelName: String
    @Binding var apiKey: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let canSave = !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Cloud Model")
                .font(.headline)
            TextField("Model name", text: $modelName)
            SecureField("API key", text: $apiKey)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}
