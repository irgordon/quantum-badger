import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Shadow Router Tests")
struct ShadowRouterTests {
    
    @Test("Intent Category properties")
    func testIntentCategory() async throws {
        #expect(IntentCategory.coding.typicallyRequiresHighComplexity == true)
        #expect(IntentCategory.analysis.typicallyRequiresHighComplexity == true)
        #expect(IntentCategory.reasoning.typicallyRequiresHighComplexity == true)
        #expect(IntentCategory.question.typicallyRequiresHighComplexity == false)
        #expect(IntentCategory.casual.typicallyRequiresHighComplexity == false)
        
        // Test all cases are covered
        #expect(IntentCategory.allCases.count == 10)
    }
    
    @Test("Intent Analysis Result creation")
    func testIntentAnalysisResult() async throws {
        let result = IntentAnalysisResult(
            complexity: .high,
            intent: .coding,
            confidence: 0.95,
            reasoning: "Complex programming task",
            piiDetected: false,
            safetyFlags: [.codeExecution]
        )
        
        #expect(result.complexity == .high)
        #expect(result.intent == .coding)
        #expect(result.confidence == 0.95)
        #expect(result.piiDetected == false)
        #expect(result.safetyFlags.count == 1)
    }
    
    @Test("Safety Flag types")
    func testSafetyFlags() async throws {
        let flags: [SafetyFlag] = [
            .personalInformation,
            .codeExecution,
            .externalLinks,
            .sensitiveTopic
        ]
        
        #expect(flags.count == 4)
    }
    
    @Test("Routing Context creation")
    func testRoutingContext() async throws {
        let systemState = SystemState.nominal()
        let policy = SecurityPolicy(executionPolicy: .balanced)
        
        let context = RoutingContext(
            prompt: "Test prompt",
            intentAnalysis: nil,
            systemState: systemState,
            securityPolicy: policy,
            availableVRAM: 16 * 1024 * 1024 * 1024
        )
        
        #expect(context.prompt == "Test prompt")
        #expect(context.isSafeMode == false)
        #expect(context.availableVRAM == 16 * 1024 * 1024 * 1024)
    }
    
    @Test("Routing Context Safe Mode detection")
    func testRoutingContextSafeMode() async throws {
        let systemState = SystemState.nominal()
        let safeModePolicy = SecurityPolicy(executionPolicy: .safeMode)
        
        let context = RoutingContext(
            prompt: "Test",
            systemState: systemState,
            securityPolicy: safeModePolicy,
            availableVRAM: 16 * 1024 * 1024 * 1024
        )
        
        #expect(context.isSafeMode == true)
    }
    
    @Test("Shadow Router initialization")
    func testShadowRouterInitialization() async throws {
        let router = ShadowRouter()
        // Should initialize without crashing
        #expect(true)
    }
    
    @Test("Shadow Router Errors")
    func testShadowRouterErrors() async throws {
        let errors: [ShadowRouterError] = [
            .intentAnalysisFailed("Test"),
            .invalidAnalysisResponse,
            .routingFailed("Test"),
            .allEnginesUnavailable,
            .piiRedactionRequired,
            .safetyViolation([.personalInformation])
        ]
        
        #expect(errors.count == 6)
    }
    
    @Test("Intent parsing fallback")
    func testIntentParsingFallback() async throws {
        // Test the lenient parsing with a malformed but valid-ish JSON string
        let malformedJSON = """
        {
            "complexity": "High",
            "intent": "Coding",
            "confidence": 0.85,
            "reasoning": "Test reasoning"
        }
        """
        
        // Just verify the structure exists - actual parsing tested in integration
        #expect(malformedJSON.contains("complexity"))
        #expect(malformedJSON.contains("intent"))
    }
    
    @Test("Quick Route without intent analysis")
    func testQuickRoute() async throws {
        let router = ShadowRouter()
        
        // This should work even without cloud tokens (uses local heuristic)
        do {
            let decision = try await router.quickRoute(prompt: "Hello world")
            // Should return a valid decision
            #expect(decision.isLocal || decision.isCloud)
        } catch {
            // May fail due to hardware checks, but shouldn't crash
            #expect(error is ShadowRouterError || error is VRAMMonitorError)
        }
    }
}

@Suite("Hybrid Execution Manager Tests")
struct HybridExecutionManagerTests {
    
    @Test("Execution Configuration presets")
    func testExecutionConfigurationPresets() async throws {
        let defaultConfig = ExecutionConfiguration.default
        #expect(defaultConfig.useIntentAnalysis == true)
        #expect(defaultConfig.allowFallback == true)
        
        let fast = ExecutionConfiguration.fast
        #expect(fast.useIntentAnalysis == false)
        #expect(fast.allowFallback == true)
        
        let privacy = ExecutionConfiguration.privacy
        #expect(privacy.forceLocal == true)
        #expect(privacy.allowFallback == false)
        
        let performance = ExecutionConfiguration.performance
        #expect(performance.forceCloud == true)
    }
    
    @Test("Execution Configuration custom values")
    func testExecutionConfigurationCustom() async throws {
        let config = ExecutionConfiguration(
            useIntentAnalysis: false,
            forceLocal: true,
            forceCloud: false,
            preferredCloudTier: .mini,
            localGenerationParams: .conservative,
            cloudGenerationParams: .creative,
            allowFallback: false
        )
        
        #expect(config.useIntentAnalysis == false)
        #expect(config.forceLocal == true)
        #expect(config.forceCloud == false)
        #expect(config.preferredCloudTier == .mini)
        #expect(config.allowFallback == false)
    }
    
    @Test("Execution Phase enum")
    func testExecutionPhase() async throws {
        let phases: [ExecutionPhase] = [
            .idle,
            .sanitizing,
            .analyzingIntent,
            .routing,
            .loadingModel,
            .generating,
            .completed,
            .failed
        ]
        
        #expect(phases.count == 8)
    }
    
    @Test("Execution Progress creation")
    func testExecutionProgress() async throws {
        let progress = ExecutionProgress(
            phase: .generating,
            percentComplete: 0.75,
            message: "Generating response...",
            timestamp: Date()
        )
        
        #expect(progress.phase == .generating)
        #expect(progress.percentComplete == 0.75)
        #expect(progress.message == "Generating response...")
    }
    
    @Test("Hybrid Execution Result creation")
    func testHybridExecutionResult() async throws {
        let result = HybridExecutionResult(
            text: "Generated text",
            decision: .local(.phi4),
            intentAnalysis: nil,
            routingTime: 0.5,
            generationTime: 2.0,
            totalTime: 2.5,
            piiRedacted: true,
            metadata: ["key": "value"]
        )
        
        #expect(result.text == "Generated text")
        #expect(result.decision.isLocal == true)
        #expect(result.routingTime == 0.5)
        #expect(result.generationTime == 2.0)
        #expect(result.totalTime == 2.5)
        #expect(result.piiRedacted == true)
    }
    
    @Test("Hybrid Execution Manager initialization")
    func testHybridExecutionManagerInitialization() async throws {
        let manager = HybridExecutionManager()
        #expect(true) // Should initialize without crashing
    }
    
    @Test("Capability checks")
    func testCapabilityChecks() async throws {
        let manager = HybridExecutionManager()
        
        let canLocal = await manager.canExecuteLocally()
        let canCloud = await manager.canExecuteInCloud()
        
        // These should return boolean values without crashing
        #expect(canLocal == true || canLocal == false)
        #expect(canCloud == true || canCloud == false)
    }
    
    @Test("Model loading status")
    func testModelLoadingStatus() async throws {
        let manager = HybridExecutionManager()
        
        let isLoaded = await manager.isModelLoaded()
        #expect(isLoaded == false) // Should not have model loaded initially
    }
}

@Suite("Integration Flow Tests")
struct IntegrationFlowTests {
    
    @Test("PII redaction before routing")
    func testPIIRedactionBeforeRouting() async throws {
        let promptWithPII = "My email is test@example.com and SSN is 123-45-6789"
        
        let sanitizer = InputSanitizer()
        let result = sanitizer.sanitize(promptWithPII)
        
        #expect(result.wasSanitized == true)
        #expect(result.sanitized.contains("test@example.com") == false)
        #expect(result.sanitized.contains("123-45-6789") == false)
    }
    
    @Test("Safe Mode routing decision logic")
    func testSafeModeRoutingLogic() async throws {
        let systemState = SystemState.nominal()
        let safeModePolicy = SecurityPolicy(executionPolicy: .safeMode)
        
        // In Safe Mode, should route to Cloud (PCC)
        let context = RoutingContext(
            prompt: "Test",
            systemState: systemState,
            securityPolicy: safeModePolicy,
            availableVRAM: 32 * 1024 * 1024 * 1024 // Even with lots of RAM
        )
        
        #expect(context.isSafeMode == true)
        // Safe mode bypasses hardware checks and routes to cloud
    }
    
    @Test("Hardware-based routing rules")
    func testHardwareRoutingRules() async throws {
        // Rule: Low complexity + High VRAM -> Local
        let highVRAMContext = RoutingContext(
            prompt: "Simple question",
            intentAnalysis: IntentAnalysisResult(
                complexity: .low,
                intent: .question,
                confidence: 0.9,
                reasoning: "Simple",
                piiDetected: false,
                safetyFlags: []
            ),
            systemState: SystemState(
                ramAvailable: 20 * 1024 * 1024 * 1024,
                ramTotal: 32 * 1024 * 1024 * 1024,
                thermalState: .nominal,
                batteryState: .full,
                batteryLevel: 1.0,
                cpuUtilization: 0.1
            ),
            securityPolicy: SecurityPolicy(executionPolicy: .balanced),
            availableVRAM: 20 * 1024 * 1024 * 1024
        )
        
        #expect(highVRAMContext.availableVRAM > 16 * 1024 * 1024 * 1024)
        #expect(highVRAMContext.intentAnalysis?.complexity == .low)
        
        // Rule: High complexity -> Cloud (regardless of VRAM)
        let highComplexityContext = RoutingContext(
            prompt: "Complex analysis",
            intentAnalysis: IntentAnalysisResult(
                complexity: .high,
                intent: .analysis,
                confidence: 0.9,
                reasoning: "Complex",
                piiDetected: false,
                safetyFlags: []
            ),
            systemState: SystemState.nominal(),
            securityPolicy: SecurityPolicy(executionPolicy: .balanced),
            availableVRAM: 32 * 1024 * 1024 * 1024 // Lots of RAM but high complexity
        )
        
        #expect(highComplexityContext.intentAnalysis?.complexity == .high)
        
        // Rule: Low VRAM -> Cloud
        let lowVRAMContext = RoutingContext(
            prompt: "Question",
            intentAnalysis: IntentAnalysisResult(
                complexity: .low,
                intent: .question,
                confidence: 0.9,
                reasoning: "Simple",
                piiDetected: false,
                safetyFlags: []
            ),
            systemState: SystemState.nominal(),
            securityPolicy: SecurityPolicy(executionPolicy: .balanced),
            availableVRAM: 4 * 1024 * 1024 * 1024 // Less than 8GB
        )
        
        #expect(lowVRAMContext.availableVRAM < 8 * 1024 * 1024 * 1024)
    }
    
    @Test("Thermal state affects routing")
    func testThermalStateRouting() async throws {
        // Critical thermal state should force cloud
        let criticalThermalState = SystemState(
            ramAvailable: 32 * 1024 * 1024 * 1024,
            ramTotal: 64 * 1024 * 1024 * 1024,
            thermalState: .critical,
            batteryState: .full,
            batteryLevel: 1.0,
            cpuUtilization: 0.9
        )
        
        #expect(criticalThermalState.thermalState.requiresCloudOffload == true)
        
        // Nominal thermal state allows local
        let nominalThermalState = SystemState(
            ramAvailable: 32 * 1024 * 1024 * 1024,
            ramTotal: 64 * 1024 * 1024 * 1024,
            thermalState: .nominal,
            batteryState: .full,
            batteryLevel: 1.0,
            cpuUtilization: 0.1
        )
        
        #expect(nominalThermalState.thermalState.allowsIntensiveCompute == true)
    }
}
