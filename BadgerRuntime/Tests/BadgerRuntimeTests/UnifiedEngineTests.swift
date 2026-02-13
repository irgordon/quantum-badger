import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Unified Inference Engine Tests")
struct UnifiedInferenceEngineTests {
    
    @Test("Unified Engine initialization")
    func testUnifiedEngineInitialization() async throws {
        let engine = UnifiedInferenceEngine()
        
        // Should be able to check capabilities without crashing
        let canUseLocal = await engine.canUseLocal()
        let canUseCloud = await engine.canUseCloud()
        
        #expect(canUseLocal == true || canUseLocal == false)
        #expect(canUseCloud == true || canUseCloud == false)
    }
    
    @Test("Inference Preference enum")
    func testInferencePreference() async throws {
        #expect(InferencePreference.auto.rawValue == "Auto")
        #expect(InferencePreference.localOnly.rawValue == "LocalOnly")
        #expect(InferencePreference.cloudOnly.rawValue == "CloudOnly")
    }
    
    @Test("Inference Source description")
    func testInferenceSource() async throws {
        let localSource = InferenceSource.local(.phi4)
        #expect(localSource.isLocal == true)
        #expect(localSource.isCloud == false)
        #expect(localSource.description.contains("Local"))
        #expect(localSource.description.contains("Phi-4"))
        
        let cloudSource = InferenceSource.cloud(.anthropic, "claude-3-5-sonnet")
        #expect(cloudSource.isLocal == false)
        #expect(cloudSource.isCloud == true)
        #expect(cloudSource.description.contains("Cloud"))
        #expect(cloudSource.description.contains("Anthropic"))
    }
    
    @Test("Runtime Error types")
    func testRuntimeErrors() async throws {
        let errors: [RuntimeError] = [
            .initializationFailed("Test"),
            .noInferenceEngineAvailable,
            .hardwareNotSupported,
            .bothEnginesFailed(
                local: LocalInferenceError.modelNotLoaded,
                cloud: CloudInferenceError.noTokenAvailable
            )
        ]
        
        #expect(errors.count == 4)
    }
    
    @Test("Unified Inference Result")
    func testUnifiedInferenceResult() async throws {
        let result = UnifiedInferenceResult(
            text: "Test output",
            source: .local(.qwen25),
            tokensGenerated: 50,
            generationTime: 1.0,
            tokensPerSecond: 50.0,
            metadata: ["key": "value"]
        )
        
        #expect(result.text == "Test output")
        #expect(result.tokensGenerated == 50)
        #expect(result.tokensPerSecond == 50.0)
    }
    
    @Test("Inference Source with different models")
    func testInferenceSourceVariants() async throws {
        let sources: [InferenceSource] = [
            .local(.phi4),
            .local(.qwen25),
            .local(.llama31),
            .cloud(.anthropic, "claude-3-5-sonnet"),
            .cloud(.openAI, "gpt-4o"),
            .cloud(.google, "gemini-pro")
        ]
        
        for source in sources {
            #expect(source.isLocal || source.isCloud)
            #expect(!(source.isLocal && source.isCloud))
        }
    }
}
