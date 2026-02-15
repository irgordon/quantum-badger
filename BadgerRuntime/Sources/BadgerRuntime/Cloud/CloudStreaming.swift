import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BadgerCore

// MARK: - Streaming Errors

public enum StreamingError: Error, Sendable {
    case connectionFailed
    case invalidStreamFormat
    case decodingFailed
    case streamCancelled
    case rateLimited(retryAfter: TimeInterval?)
    case providerError(String)
}

// MARK: - Stream Event

public enum StreamEvent: Sendable {
    case text(String)
    case toolUse(name: String, input: [String: String])
    case usage(promptTokens: Int, completionTokens: Int)
    case finish(reason: String)
    case error(StreamingError)
}

// MARK: - SSE Parser

/// Server-Sent Events parser for streaming responses
/// Changed from 'actor' to 'struct' because parsing is stateless and purely functional.
struct SSEParser: Sendable {
    
    func parseLine(_ line: String) -> StreamEvent? {
        // SSE format: "data: {json}\n\n"
        guard line.hasPrefix("data: ") else {
            return nil
        }
        
        let jsonString = String(line.dropFirst(6))
        
        // Handle [DONE] marker
        if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
            return .finish(reason: "stop")
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        // Try to parse as generic stream chunk
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return .error(.providerError(message))
                }
                
                return nil
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    func parseAnthropicChunk(data: Data) -> StreamEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Parse content block delta
        if let type = json["type"] as? String {
            switch type {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    return .text(text)
                }
                
            case "message_stop":
                return .finish(reason: "stop")
                
            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String {
                    return .finish(reason: stopReason)
                }
                
            default:
                break
            }
        }
        
        return nil
    }
    
    func parseOpenAIChunk(data: Data) -> StreamEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Parse choices
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first {
            
            // Check for finish reason
            if let finishReason = first["finish_reason"] as? String {
                return .finish(reason: finishReason)
            }
            
            // Parse delta
            if let delta = first["delta"] as? [String: Any] {
                if let content = delta["content"] as? String {
                    return .text(content)
                }
                
                // Tool calls
                if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                   let firstTool = toolCalls.first,
                   let function = firstTool["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    return .toolUse(name: name, input: [:])
                }
            }
        }
        
        // Parse usage if available
        if let usage = json["usage"] as? [String: Int],
           let promptTokens = usage["prompt_tokens"],
           let completionTokens = usage["completion_tokens"] {
            return .usage(promptTokens: promptTokens, completionTokens: completionTokens)
        }
        
        return nil
    }
    
    func parseGoogleChunk(data: Data) -> StreamEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Parse candidates
        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first {
            
            // Check finish reason
            if let finishReason = first["finishReason"] as? String {
                return .finish(reason: finishReason)
            }
            
            // Parse content
            if let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return .text(text)
            }
        }
        
        return nil
    }
}

// MARK: - Streaming Configuration

public struct StreamingConfiguration: Sendable {
    public let maxConcurrentStreams: Int
    public let chunkBufferSize: Int
    public let enableUsageEvents: Bool
    
    public init(
        maxConcurrentStreams: Int = 3,
        chunkBufferSize: Int = 1024,
        enableUsageEvents: Bool = true
    ) {
        self.maxConcurrentStreams = maxConcurrentStreams
        self.chunkBufferSize = chunkBufferSize
        self.enableUsageEvents = enableUsageEvents
    }
    
    public static let `default` = StreamingConfiguration()
}

// MARK: - Retry Configuration

public struct RetryConfiguration: Sendable {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let exponentialMultiplier: Double
    public let retryableStatusCodes: Set<Int>
    
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        exponentialMultiplier: Double = 2.0,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.exponentialMultiplier = exponentialMultiplier
        self.retryableStatusCodes = retryableStatusCodes
    }
    
    public static let `default` = RetryConfiguration()
    
    /// Calculate delay for a specific retry attempt
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(exponentialMultiplier, Double(attempt))
        return min(delay, maxDelay)
    }
}

// MARK: - Circuit Breaker

public enum CircuitBreakerState: Sendable {
    case closed      // Normal operation
    case open        // Failing, rejecting requests
    case halfOpen    // Testing if recovered
}

public actor CircuitBreaker {
    private var state: CircuitBreakerState = .closed
    private var failureCount: Int = 0
    private var lastFailureTime: Date?
    
    private let failureThreshold: Int
    private let timeout: TimeInterval
    
    public init(failureThreshold: Int = 5, timeout: TimeInterval = 60.0) {
        self.failureThreshold = failureThreshold
        self.timeout = timeout
    }
    
    var canExecute: Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= timeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
    
    func recordSuccess() {
        failureCount = 0
        state = .closed
    }
    
    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
    
    func reset() {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
    }
}

// MARK: - Token Refresh Handler

public protocol TokenRefreshHandler: Sendable {
    func refreshToken(for provider: CloudProvider) async throws -> String
}

// MARK: - Cloud Inference Service Extensions

extension CloudInferenceService {
    
    /// Generate streaming response with full SSE support
    public func generateStreaming(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        streamingConfig: StreamingConfiguration = .default
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Get token
                    let token: String
                    do {
                        token = try await keyManager.retrieveToken(for: configuration.provider)
                    } catch {
                        continuation.finish(throwing: CloudInferenceError.noTokenAvailable)
                        return
                    }
                    
                    // Build request with streaming headers
                    let request = try buildStreamingRequest(
                        messages: messages,
                        configuration: configuration,
                        token: token
                    )
                    
                    // Perform streaming request
                    let (stream, response) = try await urlSession.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: CloudInferenceError.invalidResponse)
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        if httpResponse.statusCode == 429 {
                            let retryAfter = httpResponse.allHeaderFields["Retry-After"] as? String
                            let delay = retryAfter.flatMap { TimeInterval($0) }
                            continuation.yield(.error(.rateLimited(retryAfter: delay)))
                        }
                        continuation.finish(throwing: CloudInferenceError.apiError(
                            httpResponse.statusCode,
                            "Streaming failed"
                        ))
                        return
                    }
                    
                    // Parse SSE stream
                    let parser = SSEParser()
                    var buffer = Data()
                    
                    for try await byte in stream {
                        buffer.append(byte)
                        
                        // Check for line ending
                        if byte == 10 { // \n
                            if let line = String(data: buffer, encoding: .utf8) {
                                if let event = parseSSELine(line, parser: parser, provider: configuration.provider) {
                                    continuation.yield(event)
                                    
                                    if case .finish = event {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                            buffer.removeAll()
                        }
                    }
                    
                    continuation.finish()
                    
                } catch is CancellationError {
                    continuation.finish(throwing: StreamingError.streamCancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private func parseSSELine(_ line: String, parser: SSEParser, provider: CloudProvider) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        guard trimmed.hasPrefix("data: ") else {
            return nil
        }
        
        let jsonString = String(trimmed.dropFirst(6))
        
        if jsonString == "[DONE]" {
            return .finish(reason: "stop")
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        // Provider-specific parsing
        switch provider {
        case .anthropic:
            return parser.parseAnthropicChunk(data: data)
        case .openAI:
            return parser.parseOpenAIChunk(data: data)
        case .google:
            return parser.parseGoogleChunk(data: data)
        case .applePCC:
            return nil
        }
    }
    
    private func buildStreamingRequest(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        token: String
    ) throws -> URLRequest {
        var request = try buildRequest(
            messages: messages,
            configuration: configuration,
            token: token
        )
        
        // Add streaming-specific headers
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        // Modify body to enable streaming
        if let bodyData = request.httpBody,
           var body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            body["stream"] = true
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
    
    /// Execute with automatic retry and circuit breaker
    public func generateWithRetry(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        retryConfig: RetryConfiguration = .default,
        circuitBreaker: CircuitBreaker? = nil
    ) async throws -> CloudInferenceResult {
        
        // Check circuit breaker
        if let cb = circuitBreaker {
            guard await cb.canExecute else {
                throw CloudInferenceError.serviceUnavailable
            }
        }
        
        var lastError: Error?
        
        for attempt in 0..<retryConfig.maxRetries {
            do {
                let result = try await generate(
                    messages: messages,
                    configuration: configuration
                )
                
                // Record success
                if let cb = circuitBreaker {
                    await cb.recordSuccess()
                }
                
                return result
                
            } catch let error as CloudInferenceError {
                lastError = error
                
                // Check if retryable
                switch error {
                case .rateLimited:
                    // Wait with exponential backoff
                    let delay = retryConfig.delay(forAttempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                case .apiError(let code, _):
                    if retryConfig.retryableStatusCodes.contains(code) {
                        let delay = retryConfig.delay(forAttempt: attempt)
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } else {
                        throw error // Not retryable
                    }
                    
                case .networkError:
                    let delay = retryConfig.delay(forAttempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                default:
                    throw error // Not retryable
                }
                
            } catch {
                lastError = error
                throw error
            }
        }
        
        // Record failure in circuit breaker
        if let cb = circuitBreaker {
            await cb.recordFailure()
        }
        
        throw lastError ?? CloudInferenceError.serviceUnavailable
    }
}
