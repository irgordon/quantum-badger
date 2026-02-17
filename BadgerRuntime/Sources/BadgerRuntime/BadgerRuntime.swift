import Foundation
import BadgerCore

// MARK: - BadgerRuntime

public enum BadgerRuntime {
    public static let version = "1.0.1"
    
    public static func initialize() async throws {
        let auditService = AuditLogService()
        try await auditService.initialize()
        _ = try await auditService.log(
            type: .policyChange,
            source: "BadgerRuntime",
            details: "BadgerRuntime v\(version) initialized"
        )
    }
}

// MARK: - Hardware

public typealias BadgerVRAMMonitor = VRAMMonitor
public typealias BadgerVRAMStatus = VRAMStatus
public typealias BadgerQuantizationLevel = QuantizationLevel
public typealias BadgerThermalGuard = ThermalGuard
public typealias BadgerThermalStatus = ThermalStatus
public typealias BadgerThermalAction = ThermalAction

// MARK: - Local Inference

public typealias BadgerLocalInferenceEngine = LocalInferenceEngine
public typealias BadgerModelLoadConfiguration = ModelLoadConfiguration
public typealias BadgerGenerationParameters = GenerationParameters
public typealias BadgerInferenceResult = InferenceResult
public typealias BadgerLoadedModelInfo = LoadedModelInfo

// MARK: - Cloud Inference

public typealias BadgerCloudInferenceService = CloudInferenceService
public typealias BadgerCloudModelTier = CloudModelTier
public typealias BadgerCloudRequestConfiguration = CloudRequestConfiguration
public typealias BadgerCloudMessage = CloudMessage
public typealias BadgerCloudInferenceResult = CloudInferenceResult

// MARK: - Router

public typealias BadgerShadowRouter = ShadowRouter
public typealias BadgerIntentAnalysisResult = IntentAnalysisResult
public typealias BadgerIntentCategory = IntentCategory
public typealias BadgerSafetyFlag = SafetyFlag
public typealias BadgerRoutingContext = RoutingContext

// MARK: - Execution Manager

public typealias BadgerHybridExecutionManager = HybridExecutionManager
public typealias BadgerHybridExecutionResult = HybridExecutionResult
public typealias BadgerExecutionConfiguration = ExecutionConfiguration
public typealias BadgerExecutionPhase = ExecutionPhase
public typealias BadgerExecutionProgress = ExecutionProgress

// MARK: - Services (NEW)

public typealias BadgerWebBrowserService = WebBrowserService
public typealias BadgerFetchedContent = FetchedContent
public typealias BadgerBrowserSecurityPolicy = BrowserSecurityPolicy
public typealias BadgerWebBrowserError = WebBrowserError

// MARK: - Streaming & Resilience (NEW)

public typealias BadgerStreamEvent = StreamEvent
public typealias BadgerStreamingConfiguration = StreamingConfiguration
public typealias BadgerRetryConfiguration = RetryConfiguration
public typealias BadgerCircuitBreaker = CircuitBreaker
public typealias BadgerCircuitBreakerState = CircuitBreakerState
public typealias BadgerStreamingError = StreamingError

// MARK: - Unified Inference Engine

// Note: UnifiedInferenceEngine is planned but not yet implemented
// Use HybridExecutionManager for now
// InferenceResult is defined in LocalInferenceEngine.swift

// MARK: - Errors

public typealias BadgerShadowRouterError = ShadowRouterError
// RuntimeError removed - use specific error types from each module
