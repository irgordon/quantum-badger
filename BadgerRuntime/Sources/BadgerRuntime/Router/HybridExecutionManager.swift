import Foundation
import BadgerCore

// MARK: - Execution Result

/// Result of a hybrid execution
public struct HybridExecutionResult: Sendable {
    /// Generated text
    public let text: String
    
    /// The routing decision that was made
    public let decision: RouterDecision
    
    /// Intent analysis result (if performed)
    public let intentAnalysis: IntentAnalysisResult?
    
    /// Time taken for routing
    public let routingTime: TimeInterval
    
    /// Time taken for generation
    public let generationTime: TimeInterval
    
    /// Total time (routing + generation)
    public let totalTime: TimeInterval
    
    /// Whether PII was redacted
    public let piiRedacted: Bool
    
    /// Metadata about the execution
    public let metadata: [String: String]
}

// MARK: - Execution Configuration

/// Configuration for hybrid execution
public struct ExecutionConfiguration: Sendable {
    /// Whether to perform intent analysis
    public let useIntentAnalysis: Bool
    
    /// Whether to force local execution
    public let forceLocal: Bool
    
    /// Whether to force cloud execution
    public let forceCloud: Bool
    
    /// Preferred cloud tier (if cloud is used)
    public let preferredCloudTier: CloudModelTier
    
    /// Generation parameters for local inference
    public let localGenerationParams: GenerationParameters
    
    /// Generation parameters for cloud inference
    public let cloudGenerationParams: GenerationParameters
    
    /// Whether to allow fallback on failure
    public let allowFallback: Bool
    
    public init(
        useIntentAnalysis: Bool = true,
        forceLocal: Bool = false,
        forceCloud: Bool = false,
        preferredCloudTier: CloudModelTier = .normal,
        localGenerationParams: GenerationParameters = .balanced,
        cloudGenerationParams: GenerationParameters = .balanced,
        allowFallback: Bool = true
    ) {
        self.useIntentAnalysis = useIntentAnalysis
        self.forceLocal = forceLocal
        self.forceCloud = forceCloud
        self.preferredCloudTier = preferredCloudTier
        self.localGenerationParams = localGenerationParams
        self.cloudGenerationParams = cloudGenerationParams
        self.allowFallback = allowFallback
    }
    
    /// Default configuration with intent analysis enabled
    public static let `default` = ExecutionConfiguration()
    
    /// Fast configuration without intent analysis
    public static let fast = ExecutionConfiguration(
        useIntentAnalysis: false,
        allowFallback: true
    )
    
    /// Privacy-focused configuration preferring local
    public static let privacy = ExecutionConfiguration(
        useIntentAnalysis: false,
        forceLocal: true,
        allowFallback: false
    )
    
    /// Performance configuration preferring cloud
    public static let performance = ExecutionConfiguration(
        useIntentAnalysis: true,
        forceCloud: true,
        preferredCloudTier: .normal
    )
}

// MARK: - Execution Phase

/// Represents the current phase of execution
public enum ExecutionPhase: String, Sendable {
    case idle = "Idle"
    case sanitizing = "Sanitizing"
    case analyzingIntent = "AnalyzingIntent"
    case routing = "Routing"
    case loadingModel = "LoadingModel"
    case generating = "Generating"
    case completed = "Completed"
    case failed = "Failed"
}

// MARK: - Execution Progress

/// Progress update during execution
public struct ExecutionProgress: Sendable {
    public let phase: ExecutionPhase
    public let percentComplete: Double
    public let message: String
    public let timestamp: Date
}

// MARK: - Hybrid Execution Manager Delegate

public protocol HybridExecutionManagerDelegate: AnyObject, Sendable {
    func executionDidUpdateProgress(_ progress: ExecutionProgress)
    func executionDidComplete(_ result: HybridExecutionResult)
    func executionDidFail(_ error: Error)
}

// MARK: - Hybrid Execution Manager

/// Orchestrates the complete flow: Router -> Decision -> Engine (Local or Cloud)
/// Ensures PII redaction happens before any cloud processing
public actor HybridExecutionManager {
    
    // MARK: - Properties
    
    private let shadowRouter: ShadowRouter
    private let localEngine: LocalInferenceEngine
    private let cloudService: CloudInferenceService
    private let vramMonitor: VRAMMonitor
    private let thermalGuard: ThermalGuard
    private let auditService: AuditLogService
    private let clock: FunctionClock
    
    private var delegates: [UUID: WeakExecutionDelegate] = [:]
    private var currentPhase: ExecutionPhase = .idle
    
    // MARK: - Initialization
    
    public init(
        shadowRouter: ShadowRouter? = nil,
        localEngine: LocalInferenceEngine? = nil,
        cloudService: CloudInferenceService? = nil,
        vramMonitor: VRAMMonitor? = nil,
        thermalGuard: ThermalGuard? = nil,
        auditService: AuditLogService? = nil,
        clock: FunctionClock = SystemFunctionClock()
    ) {
        let vram = vramMonitor ?? VRAMMonitor()
        let thermal = thermalGuard ?? ThermalGuard()
        let cloud = cloudService ?? CloudInferenceService()
        
        self.shadowRouter = shadowRouter ?? ShadowRouter(
            cloudService: cloud,
            vramMonitor: vram,
            thermalGuard: thermal
        )
        self.localEngine = localEngine ?? LocalInferenceEngine(
            vramMonitor: vram,
            thermalGuard: thermal
        )
        self.cloudService = cloud
        self.vramMonitor = vram
        self.thermalGuard = thermal
        self.auditService = auditService ?? AuditLogService()
        self.clock = clock
    }
    
    // MARK: - Main Execution Flow
    
    /// Execute a prompt through the complete hybrid pipeline
    /// Flow: PII Redaction -> Intent Analysis -> Routing -> Execution
    public func execute(
        prompt: String,
        configuration: ExecutionConfiguration = .default
    ) async throws -> HybridExecutionResult {
        let result = await executeWithSLA(prompt: prompt, configuration: configuration)
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func executeWithSLA(
        prompt: String,
        configuration: ExecutionConfiguration = .default,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 12_000,
            maxMemoryMb: 1024,
            deterministic: true,
            timeoutSeconds: 12,
            version: "v1"
        )
    ) async -> Result<HybridExecutionResult, FunctionError> {
        await SLARuntimeGuard.run(
            functionName: "HybridExecutionManager.executeWithSLA",
            inputMaterial: "\(prompt)#\(configuration.useIntentAnalysis)#\(configuration.forceLocal)#\(configuration.forceCloud)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.executeCore(prompt: prompt, configuration: configuration)
            },
            outputMaterial: { result in
                "\(result.text)#\(result.totalTime)#\(result.decision.isLocal)"
            }
        )
    }
    
    /// Execute with automatic fallback on failure
    public func executeWithFallback(
        prompt: String,
        configuration: ExecutionConfiguration = .default
    ) async throws -> HybridExecutionResult {
        do {
            return try await execute(prompt: prompt, configuration: configuration)
        } catch {
            guard configuration.allowFallback else {
                throw error
            }
            
            // Log the failure
            try await auditService.log(
                type: .shadowRouterDecision,
                source: "HybridExecutionManager",
                details: "Primary execution failed, attempting fallback: \(error.localizedDescription)"
            )
            
            // Try the opposite of what was attempted
            let fallbackConfig: ExecutionConfiguration
            if configuration.forceLocal {
                // Local failed, try cloud
                fallbackConfig = ExecutionConfiguration(
                    useIntentAnalysis: false,
                    forceLocal: false,
                    forceCloud: true,
                    allowFallback: false
                )
            } else {
                // Cloud or auto failed, try local if possible
                let canUseLocal = await canExecuteLocally()
                if canUseLocal {
                    fallbackConfig = ExecutionConfiguration(
                        useIntentAnalysis: false,
                        forceLocal: true,
                        forceCloud: false,
                        allowFallback: false
                    )
                } else {
                    throw error // Can't fallback
                }
            }
            
            return try await execute(prompt: prompt, configuration: fallbackConfig)
        }
    }
    
    // MARK: - Local Execution
    
    private func executeLocal(
        prompt: String,
        modelClass: ModelClass,
        configuration: ExecutionConfiguration
    ) async throws -> String {
        notifyProgress(phase: .loadingModel, percent: 0.5, message: "Loading \(modelClass.rawValue)...")
        
        // Check if model is already loaded
        let isModelLoaded = await localEngine.isModelLoaded()
        if !isModelLoaded {
            // For now, we need the model to be pre-loaded
            // In a real implementation, we might auto-load here
            throw ShadowRouterError.routingFailed("Local model \(modelClass.rawValue) not loaded")
        }
        
        // Check if loaded model matches what we need
        let loadedInfo = await localEngine.getLoadedModelInfo()
        if let info = loadedInfo, info.modelClass != modelClass {
            // Model mismatch - in production we might unload and reload
            throw ShadowRouterError.routingFailed("Loaded model \(info.modelClass.rawValue) doesn't match required \(modelClass.rawValue)")
        }
        
        notifyProgress(phase: .generating, percent: 0.6, message: "Generating locally...")
        
        let result = try await localEngine.generate(
            prompt: prompt,
            parameters: configuration.localGenerationParams
        )
        
        return result.text
    }
    
    // MARK: - Cloud Execution
    
    private func executeCloud(
        prompt: String,
        provider: CloudProvider,
        model: String,
        configuration: ExecutionConfiguration
    ) async throws -> String {
        notifyProgress(phase: .generating, percent: 0.6, message: "Generating via \(provider.rawValue)...")
        
        let result: CloudInferenceResult
        
        switch configuration.preferredCloudTier {
        case .mini:
            result = try await cloudService.generateMini(prompt: prompt, provider: provider)
        case .normal, .premium:
            result = try await cloudService.generateNormal(prompt: prompt, provider: provider)
        }
        
        return result.text
    }
    
    // MARK: - Preloading
    
    /// Preload a local model for faster execution
    public func preloadModel(
        directory: URL,
        modelClass: ModelClass
    ) async throws {
        notifyProgress(phase: .loadingModel, percent: 0.0, message: "Preloading \(modelClass.rawValue)...")
        try await localEngine.loadModel(directory: directory, modelClass: modelClass)
        notifyProgress(phase: .idle, percent: 1.0, message: "Model loaded")
    }
    
    /// Unload the current model to free memory
    public func unloadModel() async {
        await localEngine.unloadModel()
    }
    
    /// Check if a model is currently loaded
    public func isModelLoaded() async -> Bool {
        await localEngine.isModelLoaded()
    }
    
    // MARK: - Capability Checks
    
    /// Check if local execution is possible
    public func canExecuteLocally() async -> Bool {
        let vramStatus = await vramMonitor.getCurrentStatus()
        let thermalStatus = await thermalGuard.getCurrentStatus()
        return vramStatus.hasSufficientVRAM && !thermalStatus.shouldSuspend
    }
    
    /// Check if cloud execution is possible
    public func canExecuteInCloud() async -> Bool {
        await cloudService.hasAnyProvider()
    }
    
    // MARK: - Delegate Management
    
    @discardableResult
    public func addDelegate(_ delegate: HybridExecutionManagerDelegate) -> UUID {
        let id = UUID()
        delegates[id] = WeakExecutionDelegate(delegate: delegate)
        return id
    }
    
    public func removeDelegate(_ id: UUID) {
        delegates.removeValue(forKey: id)
    }
    
    // MARK: - Private Helpers
    
    private func notifyProgress(phase: ExecutionPhase, percent: Double, message: String) {
        currentPhase = phase
        let progress = ExecutionProgress(
            phase: phase,
            percentComplete: percent,
            message: message,
            timestamp: clock.now()
        )
        
        delegates = delegates.filter { $0.value.delegate != nil }
        for wrapper in delegates.values {
            wrapper.delegate?.executionDidUpdateProgress(progress)
        }
    }
    
    private func notifyCompletion(_ result: HybridExecutionResult) {
        delegates = delegates.filter { $0.value.delegate != nil }
        for wrapper in delegates.values {
            wrapper.delegate?.executionDidComplete(result)
        }
    }
    
    private func notifyFailure(_ error: Error) {
        delegates = delegates.filter { $0.value.delegate != nil }
        for wrapper in delegates.values {
            wrapper.delegate?.executionDidFail(error)
        }
    }
    
    private func selectModelForVRAM(_ vram: UInt64) -> ModelClass {
        let availableGB = Double(vram) / (1024 * 1024 * 1024)
        switch availableGB {
        case 16...: return .phi4
        case 10..<16: return .llama31
        case 6..<10: return .qwen25
        default: return .gemma2
        }
    }
    
    private func executeCore(
        prompt: String,
        configuration: ExecutionConfiguration
    ) async throws -> HybridExecutionResult {
        let executionStartTime = clock.now()
        currentPhase = .sanitizing
        notifyProgress(phase: .sanitizing, percent: 0.1, message: "Sanitizing input...")
        
        let sanitizationResult = sanitizePrompt(prompt)
        let sanitizedPrompt = sanitizationResult.sanitized
        notifyProgress(phase: .sanitizing, percent: 0.2, message: "PII check complete")
        try await logRedactionIfNeeded(sanitizationResult)
        
        let routingStartTime = clock.now()
        notifyProgress(phase: .routing, percent: 0.3, message: "Determining execution path...")
        let decision = try await chooseRoutingDecision(
            prompt: sanitizedPrompt,
            configuration: configuration
        )
        let routingTime = clock.now().timeIntervalSince(routingStartTime)
        notifyProgress(phase: .routing, percent: 0.4, message: "Routing decision: \(decision.isLocal ? "Local" : "Cloud")")
        
        let generationStartTime = clock.now()
        let resultText = try await generateText(
            prompt: sanitizedPrompt,
            decision: decision,
            configuration: configuration
        )
        let generationTime = clock.now().timeIntervalSince(generationStartTime)
        let totalTime = clock.now().timeIntervalSince(executionStartTime)
        
        notifyProgress(phase: .completed, percent: 1.0, message: "Execution complete")
        
        let result = HybridExecutionResult(
            text: resultText,
            decision: decision,
            intentAnalysis: nil,
            routingTime: routingTime,
            generationTime: generationTime,
            totalTime: totalTime,
            piiRedacted: sanitizationResult.wasSanitized,
            metadata: [
                "originalPromptLength": String(prompt.count),
                "sanitizedPromptLength": String(sanitizedPrompt.count),
                "violationsRedacted": String(sanitizationResult.violations.count)
            ]
        )
        
        notifyCompletion(result)
        return result
    }
    
    private func sanitizePrompt(_ prompt: String) -> SanitizationResult {
        InputSanitizer().sanitize(prompt)
    }
    
    private func logRedactionIfNeeded(_ result: SanitizationResult) async throws {
        guard result.wasSanitized else {
            return
        }
        
        let details = result.violations.map { $0.patternName }.joined(separator: ", ")
        try await auditService.log(
            type: .piiRedaction,
            source: "HybridExecutionManager",
            details: "PII redacted: \(details)"
        )
    }
    
    private func chooseRoutingDecision(
        prompt: String,
        configuration: ExecutionConfiguration
    ) async throws -> RouterDecision {
        if configuration.forceLocal {
            let vramStatus = await vramMonitor.getCurrentStatus()
            return RouterDecision.local(selectModelForVRAM(vramStatus.availableVRAM))
        }
        
        if configuration.forceCloud {
            return RouterDecision.cloud(
                .anthropic,
                configuration.preferredCloudTier.defaultModel(for: .anthropic)
            )
        }
        
        if configuration.useIntentAnalysis {
            notifyProgress(phase: .analyzingIntent, percent: 0.35, message: "Analyzing intent with Cloud Mini...")
            return try await shadowRouter.route(prompt: prompt)
        }
        
        return try await shadowRouter.quickRoute(prompt: prompt)
    }
    
    private func generateText(
        prompt: String,
        decision: RouterDecision,
        configuration: ExecutionConfiguration
    ) async throws -> String {
        switch decision {
        case .local(let modelClass):
            return try await executeLocal(
                prompt: prompt,
                modelClass: modelClass,
                configuration: configuration
            )
        case .cloud(let provider, let model):
            return try await executeCloud(
                prompt: prompt,
                provider: provider,
                model: model,
                configuration: configuration
            )
        }
    }
    
    private func mapFunctionError(_ error: FunctionError) -> Error {
        switch error {
        case .invalidInput(let message):
            return ShadowRouterError.routingFailed(message)
        case .timeoutExceeded(let seconds):
            return ShadowRouterError.routingFailed("Execution timed out after \(seconds)s")
        case .cancellationRequested:
            return ShadowRouterError.routingFailed("Execution cancelled")
        case .memoryBudgetExceeded(let limit, let observed):
            return ShadowRouterError.routingFailed("Memory budget exceeded \(observed)MB > \(limit)MB")
        case .deterministicViolation(let message):
            return ShadowRouterError.routingFailed(message)
        case .executionFailed(let message):
            return ShadowRouterError.routingFailed(message)
        }
    }
}

// MARK: - Weak Delegate Wrapper

private struct WeakExecutionDelegate: Sendable {
    weak var delegate: HybridExecutionManagerDelegate?
    
    init(delegate: HybridExecutionManagerDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Convenience Extensions

extension HybridExecutionManager {
    /// Quick execute without intent analysis
    public func quickExecute(prompt: String) async throws -> HybridExecutionResult {
        try await execute(prompt: prompt, configuration: .fast)
    }
    
    /// Privacy-focused execute (prefer local)
    public func privacyExecute(prompt: String) async throws -> HybridExecutionResult {
        try await execute(prompt: prompt, configuration: .privacy)
    }
    
    /// Performance-focused execute (prefer cloud)
    public func performanceExecute(prompt: String) async throws -> HybridExecutionResult {
        try await execute(prompt: prompt, configuration: .performance)
    }
}
