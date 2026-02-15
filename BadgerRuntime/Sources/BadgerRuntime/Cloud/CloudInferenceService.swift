import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BadgerCore

// MARK: - Cloud Inference Errors

public enum CloudInferenceError: Error, Sendable {
    case noTokenAvailable
    case invalidRequest
    case networkError(Error)
    case apiError(Int, String)
    case decodingError
    case rateLimited
    case serviceUnavailable
    case invalidResponse
    case requestTimeout
    case cancelled
}

// MARK: - Cloud Model Tier

/// Represents the tier of cloud model to use
public enum CloudModelTier: String, Sendable, CaseIterable {
    /// Fast, cost-effective models (Claude Haiku / GPT-4o-mini)
    case mini = "Mini"
    /// Balanced performance models (Claude Sonnet / GPT-4o)
    case normal = "Normal"
    /// Most capable models (Claude Opus / GPT-4o) - available in Normal tier for now
    case premium = "Premium"
    
    /// Default models for each provider at this tier
    public func defaultModel(for provider: CloudProvider) -> String {
        switch (self, provider) {
        case (.mini, .anthropic):
            return "claude-3-5-haiku-20241022"
        case (.mini, .openAI):
            return "gpt-4o-mini"
        case (.mini, .google):
            return "gemini-1.5-flash"
        case (.normal, .anthropic):
            return "claude-3-5-sonnet-20241022"
        case (.normal, .openAI):
            return "gpt-4o"
        case (.normal, .google):
            return "gemini-1.5-pro"
        case (.premium, .anthropic):
            return "claude-3-opus-20240229"
        case (.premium, .openAI):
            return "gpt-4o"
        case (.premium, .google):
            return "gemini-1.5-pro"
        case (_, .applePCC):
            return "apple-llm"
        }
    }
    
    /// Maximum tokens recommended for this tier
    public var maxTokens: Int {
        switch self {
        case .mini:
            return 4096
        case .normal:
            return 4096
        case .premium:
            return 8192
        }
    }
    
    /// Expected latency tier (lower is faster)
    public var latencyTier: Int {
        switch self {
        case .mini:
            return 1
        case .normal:
            return 2
        case .premium:
            return 3
        }
    }
}

// MARK: - Cloud Request Configuration

/// Configuration for a cloud inference request
public struct CloudRequestConfiguration: Sendable {
    /// The provider to use
    public let provider: CloudProvider
    
    /// The model tier
    public let tier: CloudModelTier
    
    /// Specific model override (if nil, uses tier default)
    public let modelOverride: String?
    
    /// Maximum tokens to generate
    public let maxTokens: Int
    
    /// Temperature for sampling
    public let temperature: Float
    
    /// Whether to stream the response
    public let stream: Bool
    
    /// Timeout for the request
    public let timeout: TimeInterval
    
    public init(
        provider: CloudProvider,
        tier: CloudModelTier = .normal,
        modelOverride: String? = nil,
        maxTokens: Int = 1024,
        temperature: Float = 0.7,
        stream: Bool = false,
        timeout: TimeInterval = 60.0
    ) {
        self.provider = provider
        self.tier = tier
        self.modelOverride = modelOverride
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.stream = stream
        self.timeout = timeout
    }
    
    /// Get the effective model name
    public var model: String {
        modelOverride ?? tier.defaultModel(for: provider)
    }
}

// MARK: - Cloud Message

/// A message in a cloud conversation
public struct CloudMessage: Sendable, Codable {
    public let role: Role
    public let content: String
    
    public enum Role: String, Sendable, Codable {
        case system = "system"
        case user = "user"
        case assistant = "assistant"
    }
    
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Cloud Inference Result

/// Result from a cloud inference request
public struct CloudInferenceResult: Sendable {
    /// Generated text
    public let text: String
    
    /// Provider used
    public let provider: CloudProvider
    
    /// Model used
    public let model: String
    
    /// Number of prompt tokens
    public let promptTokens: Int
    
    /// Number of completion tokens
    public let completionTokens: Int
    
    /// Total tokens used
    public var totalTokens: Int { promptTokens + completionTokens }
    
    /// Time taken for the request
    public let requestTime: TimeInterval
    
    /// Whether the response was truncated
    public let wasTruncated: Bool
    
    /// Finish reason (stop, length, etc.)
    public let finishReason: String?
    
    /// Additional metadata
    public let metadata: [String: String]
}

// MARK: - Usage Information

/// Token usage information
public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

// MARK: - Cloud Inference Service

/// Actor responsible for managing cloud-based inference
public actor CloudInferenceService {
    
    // MARK: - Properties
    
    let keyManager: KeyManager
    let urlSession: URLSession
    let auditService: AuditLogService
    let clock: FunctionClock
    private var activeTasks: [UUID: Task<Data, Error>] = [:]
    
    /// Default request timeout
    public var defaultTimeout: TimeInterval = 60.0
    
    /// Base URLs for each provider
    private let baseURLs: [CloudProvider: String] = [
        .anthropic: "https://api.anthropic.com/v1",
        .openAI: "https://api.openai.com/v1",
        .google: "https://generativelanguage.googleapis.com/v1beta"
    ]
    
    // MARK: - Initialization
    
    public init(
        keyManager: KeyManager = KeyManager(),
        auditService: AuditLogService = AuditLogService(),
        clock: FunctionClock = SystemFunctionClock()
    ) {
        self.keyManager = keyManager
        self.auditService = auditService
        self.clock = clock
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = defaultTimeout
        config.timeoutIntervalForResource = defaultTimeout * 2
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Mini Tier Inference
    
    /// Generate text using a Mini tier model (fast, cost-effective)
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - provider: The cloud provider (default: .anthropic for Haiku)
    /// - Returns: Cloud inference result
    public func generateMini(
        prompt: String,
        provider: CloudProvider = .anthropic
    ) async throws -> CloudInferenceResult {
        let config = CloudRequestConfiguration(
            provider: provider,
            tier: .mini,
            maxTokens: CloudModelTier.mini.maxTokens
        )
        return try await generate(prompt: prompt, configuration: config)
    }
    
    /// Generate text using a Mini tier model with conversation history
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - provider: The cloud provider
    /// - Returns: Cloud inference result
    public func generateMini(
        messages: [CloudMessage],
        provider: CloudProvider = .anthropic
    ) async throws -> CloudInferenceResult {
        let config = CloudRequestConfiguration(
            provider: provider,
            tier: .mini,
            maxTokens: CloudModelTier.mini.maxTokens
        )
        return try await generate(messages: messages, configuration: config)
    }
    
    // MARK: - Normal Tier Inference
    
    /// Generate text using a Normal tier model (balanced performance)
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - provider: The cloud provider (default: .anthropic for Sonnet)
    /// - Returns: Cloud inference result
    public func generateNormal(
        prompt: String,
        provider: CloudProvider = .anthropic
    ) async throws -> CloudInferenceResult {
        let config = CloudRequestConfiguration(
            provider: provider,
            tier: .normal,
            maxTokens: CloudModelTier.normal.maxTokens
        )
        return try await generate(prompt: prompt, configuration: config)
    }
    
    /// Generate text using a Normal tier model with conversation history
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - provider: The cloud provider
    /// - Returns: Cloud inference result
    public func generateNormal(
        messages: [CloudMessage],
        provider: CloudProvider = .anthropic
    ) async throws -> CloudInferenceResult {
        let config = CloudRequestConfiguration(
            provider: provider,
            tier: .normal,
            maxTokens: CloudModelTier.normal.maxTokens
        )
        return try await generate(messages: messages, configuration: config)
    }
    
    // MARK: - Generic Generation
    
    /// Generate text with full configuration control
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - configuration: Request configuration
    /// - Returns: Cloud inference result
    public func generate(
        prompt: String,
        configuration: CloudRequestConfiguration
    ) async throws -> CloudInferenceResult {
        let result = await generateWithSLA(prompt: prompt, configuration: configuration)
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func generateWithSLA(
        prompt: String,
        configuration: CloudRequestConfiguration,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 30_000,
            maxMemoryMb: 512,
            deterministic: false,
            timeoutSeconds: 30,
            version: "v1"
        )
    ) async -> Result<CloudInferenceResult, FunctionError> {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput("Prompt cannot be empty"))
        }
        
        let message = CloudMessage(role: .user, content: prompt)
        return await generateWithSLA(messages: [message], configuration: configuration, sla: sla)
    }
    
    /// Generate text with conversation history
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - configuration: Request configuration
    /// - Returns: Cloud inference result
    public func generate(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration
    ) async throws -> CloudInferenceResult {
        let result = await generateWithSLA(messages: messages, configuration: configuration)
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func generateWithSLA(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 30_000,
            maxMemoryMb: 512,
            deterministic: false,
            timeoutSeconds: 30,
            version: "v1"
        )
    ) async -> Result<CloudInferenceResult, FunctionError> {
        guard !messages.isEmpty else {
            return .failure(.invalidInput("Messages cannot be empty"))
        }
        
        if sla.deterministic && configuration.temperature > 0 {
            return .failure(.deterministicViolation("Deterministic SLA requires temperature == 0"))
        }
        
        return await SLARuntimeGuard.run(
            functionName: "CloudInferenceService.generateWithSLA",
            inputMaterial: "\(configuration.provider.rawValue)#\(configuration.model)#\(messages.count)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.generateMessagesCore(messages: messages, configuration: configuration)
            },
            outputMaterial: { result in
                "\(result.provider.rawValue)#\(result.model)#\(result.totalTokens)#\(result.finishReason ?? "none")"
            }
        )
    }
    
    private func generateMessagesCore(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration
    ) async throws -> CloudInferenceResult {
        // Fetch token at request time from KeyManager
        let token: String
        do {
            token = try await keyManager.retrieveToken(for: configuration.provider)
        } catch {
            throw CloudInferenceError.noTokenAvailable
        }
        
        // Sanitize messages
        let sanitizer = InputSanitizer()
        let sanitizedMessages = messages.map { message in
            CloudMessage(
                role: message.role,
                content: sanitizer.sanitize(message.content).sanitized
            )
        }
        
        let requestId = UUID()
        let startTime = Date()
        
        do {
            let task = Task<Data, Error> {
                defer { Task { self.removeTask(requestId) } }
                
                let request = try self.buildRequest(
                    messages: sanitizedMessages,
                    configuration: configuration,
                    token: token
                )
                
                let (data, response) = try await self.urlSession.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CloudInferenceError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 429:
                    throw CloudInferenceError.rateLimited
                case 503:
                    throw CloudInferenceError.serviceUnavailable
                default:
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw CloudInferenceError.apiError(httpResponse.statusCode, errorBody)
                }
            }
            
            self.addTask(task, id: requestId)
            let data = try await task.value
            
            let requestTime = Date().timeIntervalSince(startTime)
            
            return try self.parseResponse(
                data: data,
                provider: configuration.provider,
                requestTime: requestTime
            )
            
        } catch is CancellationError {
            throw CloudInferenceError.cancelled
        } catch let error as CloudInferenceError {
            throw error
        } catch {
            throw CloudInferenceError.networkError(error)
        }
    }
    
    private func mapFunctionError(_ error: FunctionError) -> CloudInferenceError {
        switch error {
        case .invalidInput:
            return .invalidRequest
        case .timeoutExceeded:
            return .requestTimeout
        case .cancellationRequested:
            return .cancelled
        case .memoryBudgetExceeded:
            return .serviceUnavailable
        case .deterministicViolation(let message):
            return .apiError(400, message)
        case .executionFailed(let message):
            return .apiError(500, message)
        }
    }
    
    /// Stream generation for real-time responses
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - configuration: Request configuration
    /// - Returns: Async stream of text chunks
    public func generateStreaming(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For non-streaming providers, fall back to regular generation
                    let result = try await self.generate(
                        messages: messages,
                        configuration: configuration
                    )
                    continuation.yield(result.text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Provider Availability
    
    /// Check if a provider is available (has token configured)
    public func isProviderAvailable(_ provider: CloudProvider) async -> Bool {
        await keyManager.hasToken(for: provider)
    }
    
    /// Get list of available providers
    public func getAvailableProviders() async -> [CloudProvider] {
        await keyManager.listStoredProviders()
    }
    
    /// Get the first available provider, preferring the specified one
    public func getPreferredProvider(preferred: CloudProvider = .anthropic) async -> CloudProvider? {
        let available = await getAvailableProviders()
        
        if available.contains(preferred) {
            return preferred
        }
        
        // Priority order
        let priority: [CloudProvider] = [.anthropic, .openAI, .google]
        return priority.first { available.contains($0) }
    }
    
    // MARK: - Task Management
    
    /// Cancel an active request
    public func cancelRequest(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }
    
    /// Cancel all active requests
    public func cancelAllRequests() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
    
    private func addTask(_ task: Task<Data, Error>, id: UUID) {
        activeTasks[id] = task
    }
    
    private func removeTask(_ id: UUID) {
        activeTasks.removeValue(forKey: id)
    }
    
    // MARK: - Request Building
    
    func buildRequest(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        token: String
    ) throws -> URLRequest {
        switch configuration.provider {
        case .anthropic:
            return try buildAnthropicRequest(
                messages: messages,
                configuration: configuration,
                token: token
            )
        case .openAI:
            return try buildOpenAIRequest(
                messages: messages,
                configuration: configuration,
                token: token
            )
        case .google:
            return try buildGoogleRequest(
                messages: messages,
                configuration: configuration,
                token: token
            )
        case .applePCC:
            throw CloudInferenceError.serviceUnavailable
        }
    }
    
    private func buildAnthropicRequest(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        token: String
    ) throws -> URLRequest {
        guard let baseURL = baseURLs[.anthropic],
              let url = URL(string: "\(baseURL)/messages") else {
            throw CloudInferenceError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Separate system message if present
        let systemMessage = messages.first { $0.role == .system }?.content
        let chatMessages = messages.filter { $0.role != .system }
        
        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "messages": chatMessages.map { [
                "role": $0.role.rawValue,
                "content": $0.content
            ]},
            "system": systemMessage as Any
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func buildOpenAIRequest(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        token: String
    ) throws -> URLRequest {
        guard let baseURL = baseURLs[.openAI],
              let url = URL(string: "\(baseURL)/chat/completions") else {
            throw CloudInferenceError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map { [
                "role": $0.role.rawValue,
                "content": $0.content
            ]},
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func buildGoogleRequest(
        messages: [CloudMessage],
        configuration: CloudRequestConfiguration,
        token: String
    ) throws -> URLRequest {
        // SECURITY: Use header-based API key instead of query parameter
        // to prevent key exposure in URL logs
        guard let baseURL = baseURLs[.google],
              let url = URL(string: "\(baseURL)/models/\(configuration.model):generateContent") else {
            throw CloudInferenceError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
        
        // Convert messages to Google format
        let contents = messages.filter { $0.role != .system }.map { message in
            [
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": message.content]]
            ]
        }
        
        let systemMessage = messages.first { $0.role == .system }?.content
        
        var body: [String: Any] = [
            "contents": contents
        ]
        
        if let systemInstruction = systemMessage {
            body["systemInstruction"] = [
                "parts": [["text": systemInstruction]]
            ]
        }
        
        body["generationConfig"] = [
            "maxOutputTokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    // MARK: - Response Parsing
    
    private func parseResponse(
        data: Data,
        provider: CloudProvider,
        requestTime: TimeInterval
    ) throws -> CloudInferenceResult {
        switch provider {
        case .anthropic:
            return try parseAnthropicResponse(data: data, requestTime: requestTime)
        case .openAI:
            return try parseOpenAIResponse(data: data, requestTime: requestTime)
        case .google:
            return try parseGoogleResponse(data: data, requestTime: requestTime)
        case .applePCC:
            throw CloudInferenceError.serviceUnavailable
        }
    }
    
    private func parseAnthropicResponse(
        data: Data,
        requestTime: TimeInterval
    ) throws -> CloudInferenceResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudInferenceError.decodingError
        }
        
        let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        let model = json["model"] as? String ?? "unknown"
        let usage = json["usage"] as? [String: Int] ?? [:]
        let stopReason = json["stop_reason"] as? String
        
        return CloudInferenceResult(
            text: content,
            provider: .anthropic,
            model: model,
            promptTokens: usage["input_tokens"] ?? 0,
            completionTokens: usage["output_tokens"] ?? 0,
            requestTime: requestTime,
            wasTruncated: stopReason == "max_tokens",
            finishReason: stopReason,
            metadata: [:]
        )
    }
    
    private func parseOpenAIResponse(
        data: Data,
        requestTime: TimeInterval
    ) throws -> CloudInferenceResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudInferenceError.decodingError
        }
        
        let choices = json["choices"] as? [[String: Any]] ?? []
        let message = choices.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let finishReason = choices.first?["finish_reason"] as? String
        
        let model = json["model"] as? String ?? "unknown"
        let usage = json["usage"] as? [String: Int] ?? [:]
        
        return CloudInferenceResult(
            text: content,
            provider: .openAI,
            model: model,
            promptTokens: usage["prompt_tokens"] ?? 0,
            completionTokens: usage["completion_tokens"] ?? 0,
            requestTime: requestTime,
            wasTruncated: finishReason == "length",
            finishReason: finishReason,
            metadata: [:]
        )
    }
    
    private func parseGoogleResponse(
        data: Data,
        requestTime: TimeInterval
    ) throws -> CloudInferenceResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudInferenceError.decodingError
        }
        
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let content = candidates.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let text = parts.first?["text"] as? String ?? ""
        let finishReason = candidates.first?["finishReason"] as? String
        
        let usage = json["usageMetadata"] as? [String: Int] ?? [:]
        let model = json["modelVersion"] as? String ?? "unknown"
        
        return CloudInferenceResult(
            text: text,
            provider: .google,
            model: model,
            promptTokens: usage["promptTokenCount"] ?? 0,
            completionTokens: usage["candidatesTokenCount"] ?? 0,
            requestTime: requestTime,
            wasTruncated: finishReason == "MAX_TOKENS",
            finishReason: finishReason,
            metadata: [:]
        )
    }
}

// MARK: - Convenience Extensions

extension CloudInferenceService {
    /// Quick generate with default settings (Normal tier)
    public func quickGenerate(
        prompt: String,
        provider: CloudProvider = .anthropic
    ) async throws -> String {
        let result = try await generateNormal(prompt: prompt, provider: provider)
        return result.text
    }
    
    /// Check if any cloud provider is available
    public func hasAnyProvider() async -> Bool {
        let available = await getAvailableProviders()
        return !available.isEmpty
    }
}
