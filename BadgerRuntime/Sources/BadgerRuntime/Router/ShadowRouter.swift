import Foundation
import BadgerCore

// MARK: - Intent Analysis Result

/// Result from the intent analysis phase
public struct IntentAnalysisResult: Sendable, Codable {
    public let complexity: PromptComplexity
    public let intent: IntentCategory
    public let confidence: Double
    public let reasoning: String
    public let piiDetected: Bool
    public let safetyFlags: [SafetyFlag]
    
    public init(
        complexity: PromptComplexity,
        intent: IntentCategory,
        confidence: Double,
        reasoning: String,
        piiDetected: Bool,
        safetyFlags: [SafetyFlag] = []
    ) {
        self.complexity = complexity
        self.intent = intent
        self.confidence = confidence
        self.reasoning = reasoning
        self.piiDetected = piiDetected
        self.safetyFlags = safetyFlags
    }
}

// MARK: - Intent Category

public enum IntentCategory: String, Sendable, Codable, CaseIterable {
    case question = "Question"
    case coding = "Coding"
    case creativeWriting = "CreativeWriting"
    case analysis = "Analysis"
    case summarization = "Summarization"
    case translation = "Translation"
    case reasoning = "Reasoning"
    case casual = "Casual"
    case taskAutomation = "TaskAutomation"
    case undefined = "Undefined"
    
    public var typicallyRequiresHighComplexity: Bool {
        switch self {
        case .analysis, .reasoning, .coding:
            return true
        case .creativeWriting:
            return true
        case .question, .summarization, .translation, .casual, .taskAutomation, .undefined:
            return false
        }
    }
}

// MARK: - Safety Flag

public enum SafetyFlag: String, Sendable, Codable {
    case personalInformation = "PersonalInformation"
    case codeExecution = "CodeExecution"
    case externalLinks = "ExternalLinks"
    case sensitiveTopic = "SensitiveTopic"
}

// MARK: - Shadow Router Errors

public enum ShadowRouterError: Error, Sendable {
    case intentAnalysisFailed(String)
    case invalidAnalysisResponse
    case routingFailed(String)
    case allEnginesUnavailable
    case piiRedactionRequired
    case safetyViolation([SafetyFlag])
}

// MARK: - Routing Context

public struct RoutingContext: Sendable {
    public let prompt: String
    public let intentAnalysis: IntentAnalysisResult?
    public let systemState: SystemState
    public let securityPolicy: SecurityPolicy
    public let availableVRAM: UInt64
    
    public var isSafeMode: Bool {
        securityPolicy.executionPolicy == .safeMode
    }
    
    public init(
        prompt: String,
        intentAnalysis: IntentAnalysisResult? = nil,
        systemState: SystemState,
        securityPolicy: SecurityPolicy,
        availableVRAM: UInt64
    ) {
        self.prompt = prompt
        self.intentAnalysis = intentAnalysis
        self.systemState = systemState
        self.securityPolicy = securityPolicy
        self.availableVRAM = availableVRAM
    }
}

// MARK: - Shadow Router

public actor ShadowRouter {
    
    private let cloudService: CloudInferenceService
    private let vramMonitor: VRAMMonitor
    private let thermalGuard: ThermalGuard
    private let policyManager: SecurityPolicyManager
    private let inputSanitizer: InputSanitizer
    private let auditService: AuditLogService
    
    private let highVRAMThreshold: UInt64 = 16 * 1024 * 1024 * 1024
    private let minimumVRAMThreshold: UInt64 = 8 * 1024 * 1024 * 1024
    
    public init(
        cloudService: CloudInferenceService = CloudInferenceService(),
        vramMonitor: VRAMMonitor = VRAMMonitor(),
        thermalGuard: ThermalGuard = ThermalGuard(),
        policyManager: SecurityPolicyManager = SecurityPolicyManager(),
        inputSanitizer: InputSanitizer = InputSanitizer(),
        auditService: AuditLogService = AuditLogService()
    ) {
        self.cloudService = cloudService
        self.vramMonitor = vramMonitor
        self.thermalGuard = thermalGuard
        self.policyManager = policyManager
        self.inputSanitizer = inputSanitizer
        self.auditService = auditService
    }
    
    public func route(prompt: String) async throws -> RouterDecision {
        let startTime = Date()
        
        let sanitizationResult = inputSanitizer.sanitize(prompt)
        let sanitizedPrompt = sanitizationResult.sanitized
        
        if sanitizationResult.wasSanitized {
            try await auditService.log(
                type: .piiRedaction,
                source: "ShadowRouter",
                details: "Redacted \(sanitizationResult.violations.count) violations"
            )
        }
        
        let intentAnalysis = try await performIntentAnalysis(prompt: sanitizedPrompt)
        
        if !intentAnalysis.safetyFlags.isEmpty {
            try await auditService.log(
                type: .sanitizationTriggered,
                source: "ShadowRouter",
                details: "Safety flags: \(intentAnalysis.safetyFlags.map { $0.rawValue }.joined(separator: ", "))"
            )
        }
        
        let (systemState, securityPolicy, vramStatus) = try await gatherSystemContext()
        
        let context = RoutingContext(
            prompt: sanitizedPrompt,
            intentAnalysis: intentAnalysis,
            systemState: systemState,
            securityPolicy: securityPolicy,
            availableVRAM: vramStatus.availableVRAM
        )
        
        let decision = try await makeRoutingDecision(context: context)
        
        let routingTime = Date().timeIntervalSince(startTime)
        try await auditService.log(
            type: .shadowRouterDecision,
            source: "ShadowRouter",
            details: "Decision: \(decision.isLocal ? "Local" : "Cloud"), Target: \(decision.targetModel), Complexity: \(intentAnalysis.complexity.rawValue), Intent: \(intentAnalysis.intent.rawValue), Time: \(String(format: "%.3f", routingTime))s"
        )
        
        return decision
    }
    
    public func quickRoute(prompt: String) async throws -> RouterDecision {
        let sanitizationResult = inputSanitizer.sanitize(prompt)
        let sanitizedPrompt = sanitizationResult.sanitized
        let complexity = PromptComplexity.assess(prompt: sanitizedPrompt)
        
        let (systemState, securityPolicy, vramStatus) = try await gatherSystemContext()
        
        let context = RoutingContext(
            prompt: sanitizedPrompt,
            intentAnalysis: IntentAnalysisResult(
                complexity: complexity,
                intent: .undefined,
                confidence: 0.5,
                reasoning: "Local heuristic",
                piiDetected: sanitizationResult.wasSanitized,
                safetyFlags: []
            ),
            systemState: systemState,
            securityPolicy: securityPolicy,
            availableVRAM: vramStatus.availableVRAM
        )
        
        return try await makeRoutingDecision(context: context)
    }
    
    private func performIntentAnalysis(prompt: String) async throws -> IntentAnalysisResult {
        // SECURITY: Use JSON serialization to prevent injection attacks
        let promptData: [String: Any] = [
            "prompt": prompt,
            "instruction": "Analyze complexity and intent"
        ]
        
        guard let promptJson = try? JSONSerialization.data(withJSONObject: promptData),
              let promptString = String(data: promptJson, encoding: .utf8) else {
            // Fallback to local heuristic if serialization fails
            let complexity = PromptComplexity.assess(prompt: prompt)
            return IntentAnalysisResult(
                complexity: complexity,
                intent: .undefined,
                confidence: 0.5,
                reasoning: "Fallback (serialization error)",
                piiDetected: false,
                safetyFlags: []
            )
        }
        
        let analysisPrompt = """
        Analyze the following user prompt data. Return ONLY JSON:
        
        Input: \(promptString)
        
        Format:
        {
            "complexity": "Low|High",
            "intent": "Question|Coding|CreativeWriting|Analysis|Summarization|Translation|Reasoning|Casual|TaskAutomation",
            "confidence": 0.0-1.0,
            "reasoning": "Brief explanation",
            "piiDetected": false,
            "safetyFlags": []
        }
        
        Guidelines:
        - Low: Simple questions, casual chat, basic tasks
        - High: Multi-step reasoning, code, complex analysis
        """
        
        do {
            // Dynamic provider selection with fallback
            let provider = await selectCloudProvider()
            let result = try await cloudService.generateMini(prompt: analysisPrompt, provider: provider)
            return try parseIntentAnalysis(result.text)
        } catch CloudInferenceError.noTokenAvailable {
            let complexity = PromptComplexity.assess(prompt: prompt)
            return IntentAnalysisResult(
                complexity: complexity,
                intent: .undefined,
                confidence: 0.5,
                reasoning: "Fallback (no cloud token)",
                piiDetected: false,
                safetyFlags: []
            )
        } catch {
            throw ShadowRouterError.intentAnalysisFailed(error.localizedDescription)
        }
    }
    
    private func parseIntentAnalysis(_ response: String) throws -> IntentAnalysisResult {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw ShadowRouterError.invalidAnalysisResponse
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(IntentAnalysisResult.self, from: data)
        } catch {
            return try parseLenientAnalysis(cleaned)
        }
    }
    
    private func parseLenientAnalysis(_ response: String) throws -> IntentAnalysisResult {
        func extractQuoted(key: String, from text: String) -> String? {
            let pattern = "\\\"\(key)\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
            guard let range = text.range(of: pattern, options: .regularExpression) else {
                return nil
            }
            let match = String(text[range])
            let components = match.components(separatedBy: "\"")
            return components.count >= 4 ? components[3] : nil
        }
        
        func extractNumber(key: String, from text: String) -> Double? {
            let pattern = "\\\"\(key)\\\"\\s*:\\s*([0-9.]+)"
            guard let range = text.range(of: pattern, options: .regularExpression) else {
                return nil
            }
            let match = String(text[range])
            let numStr = match.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            return Double(numStr ?? "")
        }
        
        let complexityStr = extractQuoted(key: "complexity", from: response) ?? "Low"
        let complexity = PromptComplexity(rawValue: complexityStr) ?? .low
        
        let intentStr = extractQuoted(key: "intent", from: response) ?? "Undefined"
        let intent = IntentCategory(rawValue: intentStr) ?? .undefined
        
        let confidence = extractNumber(key: "confidence", from: response) ?? 0.5
        let reasoning = extractQuoted(key: "reasoning", from: response) ?? "Fallback parsing"
        
        return IntentAnalysisResult(
            complexity: complexity,
            intent: intent,
            confidence: confidence,
            reasoning: reasoning,
            piiDetected: false,
            safetyFlags: []
        )
    }
    
    private func makeRoutingDecision(context: RoutingContext) async throws -> RouterDecision {
        if context.isSafeMode {
            return RouterDecision.cloud(.applePCC, CloudProvider.applePCC.defaultModel)
        }
        
        if context.systemState.thermalState == .critical {
            let provider = await selectCloudProvider()
            return RouterDecision.cloud(provider, CloudModelTier.normal.defaultModel(for: provider))
        }
        
        guard let intentAnalysis = context.intentAnalysis else {
            throw ShadowRouterError.routingFailed("No intent analysis")
        }
        
        let complexity = intentAnalysis.complexity
        let availableVRAM = context.availableVRAM
        
        // Rule: complexity == low AND RAM > 16GB → Route Local
        if complexity == .low && availableVRAM > highVRAMThreshold {
            if context.systemState.thermalState.allowsIntensiveCompute {
                return RouterDecision.local(selectLocalModel(vram: availableVRAM))
            }
        }
        
        // Rule: complexity == high OR RAM < 8GB → Route Cloud
        if complexity == .high || availableVRAM < minimumVRAMThreshold {
            let provider = await selectCloudProvider()
            return RouterDecision.cloud(provider, CloudModelTier.normal.defaultModel(for: provider))
        }
        
        // Default
        if availableVRAM > minimumVRAMThreshold && context.systemState.thermalState != .serious {
            return RouterDecision.local(selectLocalModel(vram: availableVRAM))
        } else {
            let provider = await selectCloudProvider()
            return RouterDecision.cloud(provider, CloudModelTier.normal.defaultModel(for: provider))
        }
    }
    
    private func gatherSystemContext() async throws -> (SystemState, SecurityPolicy, VRAMStatus) {
        async let vramStatus = vramMonitor.getCurrentStatus()
        async let securityPolicy = policyManager.getPolicy()
        
        let vram = await vramStatus
        let policy = await securityPolicy
        
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let systemState = SystemState(
            ramAvailable: vram.availableVRAM,
            ramTotal: physicalMemory,
            thermalState: await thermalGuard.getThermalState(),
            batteryState: .unknown,
            batteryLevel: nil,
            cpuUtilization: 0.0
        )
        
        return (systemState, policy, vram)
    }
    
    private func selectLocalModel(vram: UInt64) -> ModelClass {
        let availableGB = Double(vram) / (1024 * 1024 * 1024)
        switch availableGB {
        case 16...: return .phi4
        case 10..<16: return .llama31
        case 6..<10: return .qwen25
        default: return .gemma2
        }
    }
    
    /// Selects the best available cloud provider dynamically
    /// Priority: User preference > Available providers > Default (.anthropic)
    private func selectCloudProvider() async -> CloudProvider {
        await cloudService.getPreferredProvider() ?? .anthropic
    }
}

extension ShadowRouter {
    public func routeAndExecute(
        prompt: String,
        localEngine: LocalInferenceEngine,
        cloudService: CloudInferenceService
    ) async throws -> String {
        let decision = try await route(prompt: prompt)
        
        switch decision {
        case .local:
            let isLoaded = await localEngine.isModelLoaded()
            guard isLoaded else {
                throw ShadowRouterError.routingFailed("Model not loaded")
            }
            return try await localEngine.generate(prompt: prompt).text
        case .cloud(let provider, _):
            return try await cloudService.generateNormal(prompt: prompt, provider: provider).text
        }
    }
}
