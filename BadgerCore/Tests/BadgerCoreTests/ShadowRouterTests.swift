import Foundation
import Testing
@testable import BadgerCore

@Suite("Shadow Router Tests")
struct ShadowRouterTests {
    
    @Test("Prompt complexity assessment - low")
    func testLowComplexity() async throws {
        let prompt = "Hi"
        let complexity = PromptComplexity.assess(prompt: prompt)
        #expect(complexity == .low)
    }
    
    @Test("Prompt complexity assessment - medium")
    func testMediumComplexity() async throws {
        let prompt = """
        I need you to explain how functions work in Swift programming language. 
        Please provide a basic analysis including error handling patterns 
        and a simple code example. Also compare two different approaches.
        
        ```
        func example() { }
        ```
        """
        let complexity = PromptComplexity.assess(prompt: prompt)
        #expect(complexity == .medium)
    }
    
    @Test("Prompt complexity assessment - high")
    func testHighComplexity() async throws {
        // Build a prompt that definitely scores as high complexity
        // We need: wordCount > 500 OR (wordCount > 100 AND lineCount > 50 AND has code block AND multiple complexity indicators)
        var prompt = """
        I need you to analyze this complex algorithm and provide a detailed comprehensive explanation of its 
        time and space complexity characteristics. Also, can you design an optimized implementation version that handles all edge 
        cases and implements comprehensive error handling patterns? Please include detailed documentation 
        and explain the trade-offs involved in the design. I want you to evaluate all performance characteristics 
        and recommend the best approach for large-scale data processing systems with proper architecture design.
        
        ```swift
        func processData(_ items: [Int]) async throws -> [Int] {
            // Process with complex logic
            return try await items.asyncMap { item in
                let processed = try await transform(item)
                return processed > 10 ? processed : nil
            }.compactMap { $0 }
        }
        
        func transform(_ value: Int) async throws -> Int {
            // Simulate complex transformation
            try await Task.sleep(nanoseconds: 100)
            return value * 2
        }
        ```
        
        Additionally, provide a complete implementation with comprehensive unit tests and benchmarking code.
        This is a critical system component that needs thorough analysis and detailed justification for 
        every single design decision made. Please synthesize multiple different approaches and critique each one
        with detailed pros and cons analysis. Consider thread safety, memory usage, scalability, and maintainability.
        
        Explain how you would optimize this for production use with millions of records.
        Discuss the algorithmic complexity and provide Big O notation analysis.
        Recommend architectural patterns and design principles that should be applied.
        Evaluate against SOLID principles and functional programming concepts.
        
        Finally, create a comparative analysis with at least three different implementation strategies,
        explaining when each would be most appropriate. Include code examples for each approach.
        """
        
        // Ensure we have enough content to trigger high complexity
        while prompt.split(separator: " ").count < 300 {
            prompt += " Additional detailed analysis and comprehensive explanation required for proper evaluation."
        }
        
        let complexity = PromptComplexity.assess(prompt: prompt)
        #expect(complexity == .high)
    }
    
    @Test("Model class properties")
    func testModelClassProperties() async throws {
        #expect(ModelClass.phi4.parameterSize == 14)
        #expect(ModelClass.qwen25.parameterSize == 7)
        #expect(ModelClass.llama31.parameterSize == 8)
        
        #expect(ModelClass.allCases.allSatisfy { $0.isMLXOptimized })
        
        #expect(ModelClass.phi4.recommendedVRAM == 8.0)
        #expect(ModelClass.qwen25.recommendedVRAM == 4.0)
    }
    
    @Test("Cloud provider properties")
    func testCloudProviderProperties() async throws {
        #expect(CloudProvider.applePCC.supportsPCC == true)
        #expect(CloudProvider.openAI.supportsPCC == false)
        
        #expect(CloudProvider.applePCC.isSovereign == true)
        #expect(CloudProvider.anthropic.isSovereign == false)
        
        #expect(CloudProvider.openAI.defaultModel == "gpt-4o")
        #expect(CloudProvider.anthropic.defaultModel == "claude-3-5-sonnet-20241022")
    }
    
    @Test("Router decision properties")
    func testRouterDecisionProperties() async throws {
        let localDecision = RouterDecision.local(.phi4)
        let cloudDecision = RouterDecision.cloud(.anthropic, "claude-3-5-sonnet")
        
        #expect(localDecision.isLocal == true)
        #expect(localDecision.isCloud == false)
        #expect(cloudDecision.isLocal == false)
        #expect(cloudDecision.isCloud == true)
        
        #expect(localDecision.targetModel == "Phi-4")
        #expect(cloudDecision.targetModel == "claude-3-5-sonnet")
        
        #expect(localDecision.provider == "Local")
        #expect(cloudDecision.provider == "Anthropic")
        
        #expect(localDecision.isPrivacyPreserving == true)
        #expect(cloudDecision.isPrivacyPreserving == false)
        
        let pccDecision = RouterDecision.cloud(.applePCC, "apple-llm")
        #expect(pccDecision.usesPCC == true)
        #expect(pccDecision.isPrivacyPreserving == true)
    }
    
    @Test("System state nominal conditions")
    func testSystemStateNominal() async throws {
        let state = SystemState.nominal()
        
        #expect(state.hasSufficientRAM == true)
        #expect(state.hasSufficientGPU == true)
        #expect(state.thermalState.allowsIntensiveCompute == true)
        #expect(state.shouldEnterSafeMode == false)
        #expect(state.isLocalInferenceRecommended == true)
        #expect(state.shouldConstrainDueToBattery == false)
    }
    
    @Test("System state stressed conditions")
    func testSystemStateStressed() async throws {
        let state = SystemState.stressed()
        
        #expect(state.hasSufficientRAM == false)
        #expect(state.shouldEnterSafeMode == true)
        #expect(state.isLocalInferenceRecommended == false)
        #expect(state.thermalState.requiresCloudOffload == true)
        #expect(state.isXcodeBuilding == true)
        #expect(state.isRenderingVideo == true)
    }
    
    @Test("System state battery conditions")
    func testSystemStateBattery() async throws {
        let lowBattery = SystemState(
            ramAvailable: 16 * 1024 * 1024 * 1024,
            ramTotal: 32 * 1024 * 1024 * 1024,
            thermalState: .nominal,
            batteryState: .unplugged,
            batteryLevel: 0.1,
            cpuUtilization: 0.3
        )
        
        #expect(lowBattery.shouldConstrainDueToBattery == true)
        #expect(lowBattery.shouldEnterSafeMode == true)
        
        let charging = SystemState(
            ramAvailable: 16 * 1024 * 1024 * 1024,
            ramTotal: 32 * 1024 * 1024 * 1024,
            thermalState: .nominal,
            batteryState: .charging,
            batteryLevel: 0.1,
            cpuUtilization: 0.3
        )
        
        #expect(charging.shouldConstrainDueToBattery == false)
    }
    
    @Test("Thermal state progression")
    func testThermalStateProgression() async throws {
        #expect(SystemState.ThermalState.nominal.allowsIntensiveCompute == true)
        #expect(SystemState.ThermalState.fair.allowsIntensiveCompute == true)
        #expect(SystemState.ThermalState.serious.allowsIntensiveCompute == false)
        #expect(SystemState.ThermalState.critical.allowsIntensiveCompute == false)
        
        #expect(SystemState.ThermalState.nominal.priorityLevel < SystemState.ThermalState.critical.priorityLevel)
    }
    
    @Test("Router configuration defaults")
    func testRouterConfiguration() async throws {
        let config = RouterConfiguration()
        
        #expect(config.localQualityThreshold == 7)
        #expect(config.preferSovereign == true)
        #expect(config.safeModeEnabled == false)
        #expect(config.preferredCloudProvider == .anthropic)
        #expect(config.preferredLocalModel == .phi4)
        #expect(config.minimumRAMForLocal == 4.0)
        #expect(config.offloadOnLowBattery == true)
    }
    
    @Test("Complexity minimum quality scores")
    func testComplexityQualityScores() async throws {
        #expect(PromptComplexity.low.minimumLocalQualityScore == 5)
        #expect(PromptComplexity.medium.minimumLocalQualityScore == 7)
        #expect(PromptComplexity.high.minimumLocalQualityScore == 9)
        
        #expect(PromptComplexity.low.requiresReasoning == false)
        #expect(PromptComplexity.medium.requiresReasoning == true)
        #expect(PromptComplexity.high.requiresReasoning == true)
    }
}
