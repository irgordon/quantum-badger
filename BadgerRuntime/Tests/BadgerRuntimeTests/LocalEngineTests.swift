import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Local Engine Tests")
struct LocalEngineTests {
    
    @Test("Local Inference Engine initialization")
    func testEngineInitialization() async throws {
        let engine = LocalInferenceEngine()
        let isLoaded = await engine.isModelLoaded()
        #expect(isLoaded == false)
    }
    
    @Test("Model Load Configuration")
    func testModelLoadConfiguration() async throws {
        let tempURL = URL(fileURLWithPath: "/tmp/test-model")
        
        let config = ModelLoadConfiguration(
            modelClass: .phi4,
            modelDirectory: tempURL,
            quantization: .q4,
            useDynamicQuantization: true,
            maxSequenceLength: 8192,
            preload: true
        )
        
        #expect(config.modelClass == .phi4)
        #expect(config.quantization == .q4)
        #expect(config.useDynamicQuantization == true)
        #expect(config.maxSequenceLength == 8192)
        #expect(config.preload == true)
    }
    
    @Test("Generation Parameters customization")
    func testGenerationParameters() async throws {
        let params = GenerationParameters(
            maxTokens: 512,
            temperature: 0.8,
            topP: 0.95,
            repetitionPenalty: 1.2,
            seed: 42,
            stopSequences: ["END", "STOP"]
        )
        
        #expect(params.maxTokens == 512)
        #expect(params.temperature == 0.8)
        #expect(params.topP == 0.95)
        #expect(params.repetitionPenalty == 1.2)
        #expect(params.seed == 42)
        #expect(params.stopSequences == ["END", "STOP"])
    }
    
    @Test("Model info struct")
    func testModelInfo() async throws {
        let info = LoadedModelInfo(
            modelClass: .qwen25,
            quantization: .q8,
            parameterCount: 7,
            memoryUsed: 8 * 1024 * 1024 * 1024,
            loadedAt: Date(),
            maxSequenceLength: 4096
        )
        
        #expect(info.modelClass == .qwen25)
        #expect(info.quantization == .q8)
        #expect(info.parameterCount == 7)
        #expect(info.maxSequenceLength == 4096)
    }
    
    @Test("Local Inference Error types")
    func testLocalInferenceErrors() async throws {
        let errors: [LocalInferenceError] = [
            .modelNotLoaded,
            .modelLoadFailed("Test"),
            .inferenceFailed("Test"),
            .insufficientVRAM,
            .thermalThrottling,
            .invalidModelFormat("Test"),
            .quantizationFailed,
            .tokenizerNotFound,
            .generationFailed("Test")
        ]
        
        #expect(errors.count == 9)
    }
    
    @Test("Inference Result struct")
    func testInferenceResult() async throws {
        let result = InferenceResult(
            text: "Generated text",
            tokensGenerated: 100,
            generationTime: 2.5,
            tokensPerSecond: 40.0,
            modelUsed: .phi4,
            wasTruncated: false,
            metadata: ["quantization": "Q4"]
        )
        
        #expect(result.text == "Generated text")
        #expect(result.tokensGenerated == 100)
        #expect(result.tokensPerSecond == 40.0)
        #expect(result.modelUsed == .phi4)
        #expect(result.wasTruncated == false)
    }
    
    @Test("List available models in non-existent directory")
    func testListAvailableModelsEmpty() async throws {
        let engine = LocalInferenceEngine()
        let models = await engine.listAvailableModels(in: URL(fileURLWithPath: "/nonexistent"))
        #expect(models.isEmpty == true)
    }
    
    @Test("Memory estimation for different models")
    func testMemoryEstimation() async throws {
        let engine = LocalInferenceEngine()
        
        // Small model
        let smallMemory = await engine.estimateMemoryRequired(
            modelClass: .qwen25,  // 7B
            quantization: .q4
        )
        #expect(smallMemory > 0)
        
        // Large model
        let largeMemory = await engine.estimateMemoryRequired(
            modelClass: .phi4,  // 14B
            quantization: .q8
        )
        #expect(largeMemory > smallMemory)
    }
    
    @Test("Model class properties verification")
    func testModelClassProperties() async throws {
        #expect(ModelClass.phi4.parameterSize == 14)
        #expect(ModelClass.qwen25.parameterSize == 7)
        #expect(ModelClass.llama31.parameterSize == 8)
        
        #expect(ModelClass.phi4.isMLXOptimized == true)
        #expect(ModelClass.qwen25.isMLXOptimized == true)
        
        #expect(ModelClass.phi4.recommendedVRAM > ModelClass.qwen25.recommendedVRAM)
    }
}
