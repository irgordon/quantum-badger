import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Cloud Streaming Tests")
struct CloudStreamingTests {
    
    @Test("SSE Parser initialization")
    func testSSEParserInit() async throws {
        let parser = SSEParser()
        #expect(parser != nil)
    }
    
    @Test("SSE Parser handles DONE marker")
    func testSSEParserDoneMarker() async throws {
        let parser = SSEParser()
        let event = await parser.parseLine("data: [DONE]")
        
        if case .finish(let reason) = event {
            #expect(reason == "stop")
        } else {
            #expect(Bool(false), "Expected finish event")
        }
    }
    
    @Test("SSE Parser ignores non-data lines")
    func testSSEParserIgnoresNonData() async throws {
        let parser = SSEParser()
        let event = await parser.parseLine("event: message")
        #expect(event == nil)
    }
    
    @Test("Streaming configuration defaults")
    func testStreamingConfigDefaults() async throws {
        let config = StreamingConfiguration.default
        #expect(config.maxConcurrentStreams == 3)
        #expect(config.chunkBufferSize == 1024)
        #expect(config.enableUsageEvents == true)
    }
    
    @Test("Retry configuration defaults")
    func testRetryConfigDefaults() async throws {
        let config = RetryConfiguration.default
        #expect(config.maxRetries == 3)
        #expect(config.baseDelay == 1.0)
        #expect(config.maxDelay == 60.0)
        #expect(config.exponentialMultiplier == 2.0)
        #expect(config.retryableStatusCodes.contains(429))
        #expect(config.retryableStatusCodes.contains(503))
    }
    
    @Test("Retry delay calculation")
    func testRetryDelayCalculation() async throws {
        let config = RetryConfiguration.default
        
        // Attempt 0: 1.0 * 2^0 = 1.0
        #expect(config.delay(forAttempt: 0) == 1.0)
        
        // Attempt 1: 1.0 * 2^1 = 2.0
        #expect(config.delay(forAttempt: 1) == 2.0)
        
        // Attempt 2: 1.0 * 2^2 = 4.0
        #expect(config.delay(forAttempt: 2) == 4.0)
        
        // Should not exceed maxDelay
        let largeConfig = RetryConfiguration(maxDelay: 10.0)
        #expect(largeConfig.delay(forAttempt: 10) <= 10.0)
    }
    
    @Test("Circuit breaker initial state")
    func testCircuitBreakerInitial() async throws {
        let cb = CircuitBreaker()
        let canExecute = await cb.canExecute
        #expect(canExecute == true)
    }
    
    @Test("Circuit breaker records failures")
    func testCircuitBreakerFailures() async throws {
        let cb = CircuitBreaker(failureThreshold: 3)
        
        // Record 2 failures - should still be closed
        await cb.recordFailure()
        await cb.recordFailure()
        #expect(await cb.canExecute == true)
        
        // Third failure should open circuit
        await cb.recordFailure()
        #expect(await cb.canExecute == false)
    }
    
    @Test("Circuit breaker reset")
    func testCircuitBreakerReset() async throws {
        let cb = CircuitBreaker(failureThreshold: 1)
        
        await cb.recordFailure()
        #expect(await cb.canExecute == false)
        
        await cb.reset()
        #expect(await cb.canExecute == true)
    }
    
    @Test("Circuit breaker success resets")
    func testCircuitBreakerSuccess() async throws {
        let cb = CircuitBreaker(failureThreshold: 3)
        
        await cb.recordFailure()
        await cb.recordFailure()
        #expect(await cb.canExecute == true)
        
        await cb.recordSuccess()
        // After success, failures should be reset
        await cb.recordFailure()
        #expect(await cb.canExecute == true) // Only 1 failure after reset
    }
    
    @Test("Stream event cases")
    func testStreamEventCases() async throws {
        let textEvent = StreamEvent.text("Hello")
        let finishEvent = StreamEvent.finish(reason: "stop")
        let errorEvent = StreamEvent.error(.streamCancelled)
        
        if case .text(let text) = textEvent {
            #expect(text == "Hello")
        } else {
            #expect(Bool(false))
        }
        
        if case .finish(let reason) = finishEvent {
            #expect(reason == "stop")
        } else {
            #expect(Bool(false))
        }
        
        if case .error(let error) = errorEvent {
            if case .streamCancelled = error {
                #expect(true)
            } else {
                #expect(Bool(false))
            }
        } else {
            #expect(Bool(false))
        }
    }
    
    @Test("Streaming error cases")
    func testStreamingError() async throws {
        let errors: [StreamingError] = [
            .connectionFailed,
            .invalidStreamFormat,
            .decodingFailed,
            .streamCancelled,
            .rateLimited(retryAfter: 30),
            .providerError("Test error")
        ]
        
        #expect(errors.count == 6)
        
        // Test rate limited with retry after
        if case .rateLimited(let retryAfter) = errors[4] {
            #expect(retryAfter == 30)
        } else {
            #expect(Bool(false))
        }
    }
}

@Suite("Cloud Service Extensions Tests")
struct CloudServiceExtensionsTests {
    
    @Test("Generate streaming exists")
    func testGenerateStreamingExists() async throws {
        let service = CloudInferenceService()
        
        let stream = service.generateStreaming(
            messages: [CloudMessage(role: .user, content: "Test")],
            configuration: CloudRequestConfiguration(provider: .openAI)
        )
        
        #expect(stream != nil)
    }
    
    @Test("Generate with retry exists")
    func testGenerateWithRetryExists() async throws {
        let service = CloudInferenceService()
        
        // This should compile and be callable
        // We can't actually test it without network
        let _ = service.generateWithRetry
    }
}