import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Cloud Service Tests")
struct CloudServiceTests {
    
    @Test("Cloud Model Tier defaults")
    func testCloudModelTierDefaults() async throws {
        // Test Anthropic defaults
        #expect(CloudModelTier.mini.defaultModel(for: .anthropic) == "claude-3-5-haiku-20241022")
        #expect(CloudModelTier.normal.defaultModel(for: .anthropic) == "claude-3-5-sonnet-20241022")
        #expect(CloudModelTier.premium.defaultModel(for: .anthropic) == "claude-3-opus-20240229")
        
        // Test OpenAI defaults
        #expect(CloudModelTier.mini.defaultModel(for: .openAI) == "gpt-4o-mini")
        #expect(CloudModelTier.normal.defaultModel(for: .openAI) == "gpt-4o")
        
        // Test Google defaults
        #expect(CloudModelTier.mini.defaultModel(for: .google) == "gemini-1.5-flash")
        #expect(CloudModelTier.normal.defaultModel(for: .google) == "gemini-1.5-pro")
    }
    
    @Test("Cloud Model Tier properties")
    func testCloudModelTierProperties() async throws {
        #expect(CloudModelTier.mini.latencyTier < CloudModelTier.normal.latencyTier)
        #expect(CloudModelTier.mini.maxTokens <= CloudModelTier.normal.maxTokens)
    }
    
    @Test("Cloud Request Configuration")
    func testCloudRequestConfiguration() async throws {
        let config = CloudRequestConfiguration(
            provider: .anthropic,
            tier: .normal,
            maxTokens: 2048,
            temperature: 0.5,
            stream: true
        )
        
        #expect(config.provider == .anthropic)
        #expect(config.tier == .normal)
        #expect(config.model == "claude-3-5-sonnet-20241022")
        #expect(config.maxTokens == 2048)
        #expect(config.temperature == 0.5)
        #expect(config.stream == true)
        
        // Test with model override
        let overrideConfig = CloudRequestConfiguration(
            provider: .openAI,
            tier: .mini,
            modelOverride: "gpt-4-turbo"
        )
        #expect(overrideConfig.model == "gpt-4-turbo")
    }
    
    @Test("Cloud Message creation")
    func testCloudMessage() async throws {
        let userMessage = CloudMessage(role: .user, content: "Hello")
        #expect(userMessage.role == .user)
        #expect(userMessage.content == "Hello")
        
        let systemMessage = CloudMessage(role: .system, content: "You are helpful")
        #expect(systemMessage.role == .system)
        
        let assistantMessage = CloudMessage(role: .assistant, content: "Hi there")
        #expect(assistantMessage.role == .assistant)
    }
    
    @Test("Cloud Inference Result calculations")
    func testCloudInferenceResult() async throws {
        let result = CloudInferenceResult(
            text: "Hello",
            provider: .anthropic,
            model: "claude-3-5-sonnet",
            promptTokens: 100,
            completionTokens: 50,
            requestTime: 1.5,
            wasTruncated: false,
            finishReason: "stop",
            metadata: [:]
        )
        
        #expect(result.totalTokens == 150)
        #expect(result.text == "Hello")
        #expect(result.provider == .anthropic)
    }
    
    @Test("Cloud Inference Service initialization")
    func testCloudServiceInitialization() async throws {
        let service = CloudInferenceService()
        
        // Without tokens, no providers should be available
        let hasProvider = await service.hasAnyProvider()
        #expect(hasProvider == false)
    }
    
    @Test("Cloud Inference Error types")
    func testCloudInferenceErrors() async throws {
        let errors: [CloudInferenceError] = [
            .noTokenAvailable,
            .invalidRequest,
            .networkError(NSError(domain: "test", code: 1)),
            .apiError(429, "Rate limited"),
            .decodingError,
            .rateLimited,
            .serviceUnavailable
        ]
        
        // Just verify they can be created
        #expect(errors.count == 7)
    }
    
    @Test("Generation Parameters presets")
    func testGenerationParametersPresets() async throws {
        let conservative = GenerationParameters.conservative
        #expect(conservative.temperature == 0.3)
        #expect(conservative.maxTokens == 2048)
        
        let creative = GenerationParameters.creative
        #expect(creative.temperature == 0.9)
        
        let balanced = GenerationParameters.balanced
        #expect(balanced.temperature == 0.7)
        #expect(balanced.maxTokens == 1024)
    }
    
    @Test("Cloud Inference Service provider availability without tokens")
    func testProviderAvailability() async throws {
        let service = CloudInferenceService()
        
        let anthropicAvailable = await service.isProviderAvailable(.anthropic)
        let openAIAvailable = await service.isProviderAvailable(.openAI)
        
        #expect(anthropicAvailable == false)
        #expect(openAIAvailable == false)
    }
}
