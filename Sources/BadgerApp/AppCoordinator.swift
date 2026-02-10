import Foundation
import BadgerCore
import BadgerRuntime
import BadgerRemote

/// App‑level coordinator that owns startup tasks and cancellation.
///
/// The coordinator is the single source of truth for all runtime
/// subsystem references. It runs on `@MainActor` to guarantee
/// safe UI updates.
@MainActor
public final class AppCoordinator: ObservableObject {

    // MARK: - Published State

    @Published public var systemStatus: SystemStatus
    @Published public var isSafeModeActive: Bool = false
    @Published public var isRemoteControlEnabled: Bool = false
    @Published public var lastVoiceTranscription: String = ""
    @Published public var isRecording: Bool = false

    /// Non‑blocking user notice. Consumed by ``NotificationBanner``.
    @Published public var lastUserNotice: UserNotice?

    /// Currently selected model descriptor for the UI.
    @Published public var selectedModel: ModelDescriptor?

    /// Whether a model validation is in progress.
    @Published public var isValidatingModel: Bool = false

    /// Last model validation result.
    @Published public var lastValidationResult: ModelValidationResult?
    
    /// Live conversation history for the UI.
    @Published public var conversationHistory: [QuantumMessage] = []
    
    /// Available conversation archives.
    @Published public var conversationArchives: [ConversationArchiveMetadata] = []

    // MARK: - Runtime Subsystems

    public let executionManager: HybridExecutionManager
    public let scheduler: PriorityScheduler
    public let remoteHandler: RemoteCommandHandler
    public let fileManager: SecureFileManager
    public let memoryController: MemoryController
    public let modelCatalog: ModelCatalog
    public let modelValidator: ModelValidator
    public let modelLoader: ModelLoader

    // MARK: - Logging

    /// Persistent, append‑only error log — shared with ``ErrorLogViewer``.
    public let errorLog: ErrorLog

    /// Category‑specific loggers for each subsystem.
    public let logRuntime: AppLogger
    public let logUI: AppLogger
    public let logRemote: AppLogger
    public let logSecurity: AppLogger

    /// Resource sentinel — started on launch, cancelled on deinit.
    private var sentinelStartTask: Task<Void, Never>?

    /// Periodic status refresh task.
    private var statusRefreshTask: Task<Void, Never>?
    
    /// Current model loading task (cancellable).
    private var modelLoadingTask: Task<Void, Never>?

    // MARK: - Init

    public init() {
        let exec = HybridExecutionManager()
        let sched = PriorityScheduler()
        let remote = RemoteCommandHandler(executionManager: exec)
        let fileMgr = SecureFileManager()
        let memory = MemoryController()

        self.executionManager = exec
        self.scheduler = sched
        self.remoteHandler = remote
        self.fileManager = fileMgr
        self.memoryController = memory

        let catalog = ModelCatalog()
        let validator = ModelValidator()
        let loader = ModelLoader()
        self.modelCatalog = catalog
        self.modelValidator = validator
        self.modelLoader = loader

        // Logging infrastructure.
        let log = ErrorLog()
        self.errorLog = log
        self.logRuntime = AppLogger(category: .runtime, errorLog: log)
        self.logUI = AppLogger(category: .ui, errorLog: log)
        self.logRemote = AppLogger(category: .remote, errorLog: log)
        self.logSecurity = AppLogger(category: .security, errorLog: log)

        // Initial status snapshot.
        self.systemStatus = SystemStatus(
            totalRAMBytes: UInt64(ProcessInfo.processInfo.physicalMemory),
            availableRAMBytes: 0,
            executionLocation: .local,
            thermalState: "nominal",
            isThrottled: false,
            isSafeModeActive: false,
            isRemoteControlEnabled: false,
            localModelBudgetBytes: 0,
            conversationTokenCount: 0,
            isConversationCompacted: false
        )
        
        // Wire up Semantic Search dependency.
        BadgerGoalQuery.provider = TaskPlanner.shared
    }

    // MARK: - Lifecycle

    /// Start all subsystems. Called from the SwiftUI app `onAppear`.
    public func start() {
        logRuntime.info("Application started")

        sentinelStartTask = Task {
            // Refresh initial status.
            await refreshStatus()

            // Auto‑select cloud model for low‑RAM systems.
            applyLowRAMCloudDefault()

            // Start periodic status refresh (every 5 seconds).
            startStatusRefresh()
        }
    }

    /// Cancel all owned tasks. Called on coordinator teardown.
    public func stop() {
        logRuntime.info("Application stopping")
        sentinelStartTask?.cancel()
        sentinelStartTask = nil
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
    }

    // MARK: - Safe Mode

    /// Toggle safe mode and propagate to runtime.
    public func toggleSafeMode(_ enabled: Bool) {
        isSafeModeActive = enabled
        logRuntime.info("Safe mode \(enabled ? "enabled" : "disabled")")
        Task {
            await executionManager.setSafeMode(enabled)
        }
    }

    // MARK: - Remote Control

    /// Toggle remote command handling.
    public func toggleRemoteControl(_ enabled: Bool) {
        isRemoteControlEnabled = enabled
        logRemote.info("Remote control \(enabled ? "enabled" : "disabled")")
        Task {
            await remoteHandler.setEnabled(enabled)
            await executionManager.setRemoteControlEnabled(enabled)
        }
    }

    // MARK: - Voice Command Submission

    /// Submit a voice‑transcribed command through the sanitization pipeline.
    public func submitVoiceCommand(_ text: String) {
        lastVoiceTranscription = text
        Task {
            let intent = ExecutionIntent(
                prompt: text,
                tier: .userInitiated
            )
            do {
                _ = try await executionManager.process(intent: intent)
                logRuntime.info("Voice command processed successfully")
            } catch {
                logRuntime.warning("Voice command could not be processed: \(error.localizedDescription)")
                lastUserNotice = UserNotice.processingPaused(
                    reason: "Your voice command could not be processed right now. The system is protecting your resources. Please try again shortly."
                )
            }
            await refreshStatus()
        }
    }
    
    /// Submit a text command from the UI.
    public func submitTextCommand(_ text: String) {
        Task {
            // Optimistic update
            await memoryController.append(role: .user, content: text)
            await refreshStatus() // Pulls new history
            
            let intent = ExecutionIntent(
                prompt: text,
                tier: .userInitiated
            )
            
            do {
                let result = try await executionManager.process(intent: intent)
                await memoryController.append(role: .assistant, content: result.output)
            } catch {
                await memoryController.append(role: .system, content: "Error: \(error.localizedDescription)")
            }
            await refreshStatus()
        }
    }
    
    /// Load a specific archive.
    public func loadArchive(_ id: UUID) {
        Task {
            do {
                try await memoryController.loadArchive(id: id)
                await refreshStatus()
            } catch {
                lastUserNotice = UserNotice(
                    title: "Load Failed",
                    detail: "Could not load conversation: \(error.localizedDescription)",
                    severity: .warning
                )
            }
        }
    }

    // MARK: - Settings Application

    /// Apply a new execution mode from Settings.
    ///
    /// Changes are idempotent and safe under rapid toggling.
    public func applyExecutionMode(_ mode: String) {
        logRuntime.info("Execution mode changed to \(mode)")
        Task {
            switch mode {
            case "alwaysLocal":
                await executionManager.forceLocal(true)
            case "alwaysCloud":
                await executionManager.forceCloud(true)
            default:
                await executionManager.forceLocal(false)
                await executionManager.forceCloud(false)
            }
            await refreshStatus()
        }
    }

    /// Apply a new conversation history limit.
    public func applyHistoryLimit(maxEntries: Int) {
        logRuntime.info("Conversation history limit set to \(maxEntries)")
    }

    /// Archive the current conversation to disk and reset.
    public func archiveConversation() {
        Task {
            do {
                try await memoryController.archiveAndReset()
                logRuntime.info("Conversation archived and reset")
                lastUserNotice = UserNotice.settingsApplied(setting: "Conversation archived")
                await refreshStatus()
            } catch {
                logRuntime.warning("Conversation archive failed: \(error.localizedDescription)")
                lastUserNotice = UserNotice(
                    title: "Archive not completed",
                    detail: "The conversation could not be saved to disk right now. Your data is still in memory and safe.",
                    severity: .warning
                )
            }
        }
    }

    /// Purge the current conversation permanently.
    public func purgeConversation() {
        Task {
            await memoryController.purge()
            logRuntime.info("Conversation purged")
            lastUserNotice = UserNotice.settingsApplied(setting: "Conversation cleared")
            await refreshStatus()
        }
    }

    // MARK: - Status Refresh

    private func startStatusRefresh() {
        statusRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    await self?.refreshStatus()
                } catch {
                    break
                }
            }
        }
    }

    public func refreshStatus() async {
        let runtimeSnapshot = await executionManager.statusSnapshot()

        // Pull conversation metrics from MemoryController.
        let entryCount = await memoryController.entryCount()
        let isCompacted = await memoryController.hasCompacted()

        // Merge into a combined snapshot.
        systemStatus = SystemStatus(
            totalRAMBytes: runtimeSnapshot.totalRAMBytes,
            availableRAMBytes: runtimeSnapshot.availableRAMBytes,
            executionLocation: runtimeSnapshot.executionLocation,
            thermalState: runtimeSnapshot.thermalState,
            isThrottled: runtimeSnapshot.isThrottled,
            isSafeModeActive: runtimeSnapshot.isSafeModeActive,
            isRemoteControlEnabled: runtimeSnapshot.isRemoteControlEnabled,
            localModelBudgetBytes: runtimeSnapshot.localModelBudgetBytes,
            conversationTokenCount: UInt64(entryCount),
            isConversationCompacted: isCompacted,
            activeModelName: selectedModel?.name ?? "Automatic",
            activeModelLocation: selectedModel?.location ?? runtimeSnapshot.executionLocation
        )
    }

    deinit {
        sentinelStartTask?.cancel()
        statusRefreshTask?.cancel()
    }
    // MARK: - File Ingestion

    /// Ingest a file from a security-scoped URL (e.g. from fileImporter).
    public func ingestFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            logSecurity.warning("Failed to access security-scoped resource: \(url.path)")
            lastUserNotice = UserNotice(
                title: "File Access Denied",
                detail: "Could not access the selected file due to sandbox restrictions.",
                severity: .warning
            )
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        Task {
            do {
                let ingested = try await fileManager.ingest(fileURL: url)
                logUI.info("Ingested file: \(ingested.sourceFilename) (\(ingested.fileType))")
                lastUserNotice = UserNotice(
                    title: "File Imported",
                    detail: "Successfully imported \(ingested.sourceFilename). Content is ready for use.",
                    severity: .info
                )
                // In a real app, we'd add this to the context or conversation here.
            } catch {
                logRuntime.warning("File ingestion failed: \(error.localizedDescription)")
                 lastUserNotice = UserNotice(
                    title: "Import Failed",
                    detail: "Could not process the file. It may be too large or corrupted.",
                    severity: .warning
                )
            }
        }
    }

    // MARK: - Model Selection

    /// Select a cloud model.
    public func selectCloudModel(_ model: ModelDescriptor) {
        selectedModel = model
        logRuntime.info("Selected cloud model: \(model.name)")
        Task { await refreshStatus() }
    }

    /// Select a local model (does NOT load it).
    public func selectLocalModel(_ model: ModelDescriptor) {
        selectedModel = model
        logRuntime.info("Selected local model: \(model.name)")
        Task { await refreshStatus() }
    }

    /// Load the currently selected local model.
    public func loadSelectedModel() {
        guard let model = selectedModel, model.location == .local else {
            lastUserNotice = UserNotice(
                title: "No Local Model Selected",
                detail: "Please select a local model before loading.",
                severity: .info
            )
            return
        }

        // Final RAM check before loading.
        let available = systemStatus.availableRAMBytes
        if let needed = model.estimatedRAMBytes,
           !model.fitsInBudget(available) {
            let neededGB = String(format: "%.1f", Double(needed) / 1_073_741_824)
            let availGB = String(format: "%.1f", Double(available) / 1_073_741_824)
            lastUserNotice = UserNotice(
                title: "Not Enough Memory",
                detail: "\(model.name) needs about \(neededGB) GB, but only \(availGB) GB is available. Close some apps or choose a cloud model instead.",
                severity: .warning
            )
            logRuntime.warning("Blocked loading \(model.name): insufficient RAM (\(neededGB) GB needed, \(availGB) GB available)")
            return
        }

        // Cancel any existing load.
        modelLoadingTask?.cancel()
        
        modelLoadingTask = Task {
            defer { modelLoadingTask = nil }
            
            do {
                try await modelLoader.load(model, at: URL(fileURLWithPath: "/placeholder"), availableRAM: available)
                
                // Ensure we didn't get cancelled during load
                try Task.checkCancellation()
                
                logRuntime.info("Loaded model: \(model.name)")
                lastUserNotice = UserNotice(
                    title: "Model Loaded",
                    detail: "\(model.name) is ready to use.",
                    severity: .info
                )
            } catch let error as ModelValidationError {
                lastUserNotice = UserNotice(
                    title: "Could Not Load Model",
                    detail: error.friendlyMessage,
                    severity: .warning
                )
                logRuntime.warning("Model load failed: \(error.friendlyMessage)")
            } catch is CancellationError {
                logRuntime.info("Model load cancelled")
            } catch {
                lastUserNotice = UserNotice(
                    title: "Could Not Load Model",
                    detail: "Something unexpected went wrong. Please try again.",
                    severity: .warning
                )
                logRuntime.warning("Model load failed: \(error.localizedDescription)")
            }
            await refreshStatus()
        }
    }

    /// Unload the current local model.
    public func unloadModel() {
        Task {
            await modelLoader.unload()
            logRuntime.info("Model unloaded")
            lastUserNotice = UserNotice(
                title: "Model Unloaded",
                detail: "Local model has been unloaded. Memory has been freed.",
                severity: .info
            )
            await refreshStatus()
        }
    }

    /// Import and validate a custom model file.
    public func importCustomModel(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastUserNotice = UserNotice(
                title: "File Access Denied",
                detail: "Could not access the model file due to sandbox restrictions.",
                severity: .warning
            )
            return
        }

        isValidatingModel = true
        lastValidationResult = nil

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isValidatingModel = false
            }

            do {
                let result = try await modelValidator.validate(
                    fileURL: url,
                    totalRAM: systemStatus.totalRAMBytes,
                    availableRAM: systemStatus.availableRAMBytes
                )

                lastValidationResult = result

                // Create descriptor from validation.
                let descriptor = ModelDescriptor(
                    name: url.deletingPathExtension().lastPathComponent,
                    provider: "Custom",
                    location: .local,
                    capabilityTier: .balanced,
                    estimatedRAMBytes: result.estimatedRAMBytes,
                    isUserSupplied: true,
                    isVerified: result.isVerified,
                    tradeoffDescription: "User‑supplied model. \(result.isVerified ? "Verified source." : "Unverified — use with caution.")"
                )

                await modelCatalog.addCustomModel(descriptor)
                logRuntime.info("Custom model added: \(descriptor.name) (verified: \(result.isVerified))")

                lastUserNotice = UserNotice(
                    title: "Model Added",
                    detail: "\(descriptor.name) passed validation and is ready to select. \(result.isVerified ? "" : "⚠️ This model is unverified.")",
                    severity: result.isVerified ? .info : .warning
                )
            } catch let error as ModelValidationError {
                lastUserNotice = UserNotice(
                    title: "Model Rejected",
                    detail: error.friendlyMessage,
                    severity: .warning
                )
                logSecurity.warning("Custom model rejected: \(error.friendlyMessage)")
            } catch {
                lastUserNotice = UserNotice(
                    title: "Validation Failed",
                    detail: "Could not validate this model file. Please try a different file.",
                    severity: .warning
                )
                logRuntime.warning("Custom model validation error: \(error.localizedDescription)")
            }
        }
    }

    /// Auto‑select cloud model for ≤8 GB systems and notify user.
    public func applyLowRAMCloudDefault() {
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        guard systemStatus.totalRAMBytes <= eightGB else { return }

        Task {
            let defaultModel = await modelCatalog.safeModeDefault
            selectedModel = defaultModel
            toggleSafeMode(true)

            lastUserNotice = UserNotice(
                title: "Using Cloud Model",
                detail: "Due to low system memory, Quantum Badger is using \(defaultModel.name) (cloud) for best stability.",
                severity: .info
            )
            logRuntime.info("Auto‑selected cloud model \(defaultModel.name) for low‑RAM system")
        }
    }

}
