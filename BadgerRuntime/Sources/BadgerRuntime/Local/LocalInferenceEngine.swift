import Foundation
import MLX
import MLXRandom
import BadgerCore

// MARK: - Local Inference Errors

public enum LocalInferenceError: Error, Sendable {
    case modelNotLoaded
    case modelLoadFailed(String)
    case inferenceFailed(String)
    case insufficientVRAM
    case thermalThrottling
    case invalidModelFormat(String)
    case quantizationFailed
    case tokenizerNotFound
    case generationFailed(String)
}

// MARK: - Model Load Configuration

/// Configuration for loading a local model
public struct ModelLoadConfiguration: Sendable {
    /// The model class to load
    public let modelClass: ModelClass
    
    /// Path to the model directory
    public let modelDirectory: URL
    
    /// Quantization level to use
    public let quantization: QuantizationLevel
    
    /// Whether to use dynamic quantization based on available VRAM
    public let useDynamicQuantization: Bool
    
    /// Maximum sequence length
    public let maxSequenceLength: Int
    
    /// Whether to preload the model into memory
    public let preload: Bool
    
    public init(
        modelClass: ModelClass,
        modelDirectory: URL,
        quantization: QuantizationLevel = .q4,
        useDynamicQuantization: Bool = true,
        maxSequenceLength: Int = 4096,
        preload: Bool = true
    ) {
        self.modelClass = modelClass
        self.modelDirectory = modelDirectory
        self.quantization = quantization
        self.useDynamicQuantization = useDynamicQuantization
        self.maxSequenceLength = maxSequenceLength
        self.preload = preload
    }
}

// MARK: - Generation Parameters

/// Parameters for text generation
public struct GenerationParameters: Sendable {
    /// Maximum number of tokens to generate
    public let maxTokens: Int
    
    /// Temperature for sampling (0.0 = deterministic, 1.0 = creative)
    public let temperature: Float
    
    /// Top-p (nucleus) sampling
    public let topP: Float
    
    /// Repetition penalty
    public let repetitionPenalty: Float
    
    /// Random seed (nil for random)
    public let seed: UInt64?
    
    /// Stop sequences
    public let stopSequences: [String]
    
    public init(
        maxTokens: Int = 1024,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.1,
        seed: UInt64? = nil,
        stopSequences: [String] = []
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
        self.stopSequences = stopSequences
    }
    
    /// Conservative parameters for accurate responses
    public static let conservative = GenerationParameters(
        maxTokens: 2048,
        temperature: 0.3,
        topP: 0.95,
        repetitionPenalty: 1.0
    )
    
    /// Creative parameters for diverse responses
    public static let creative = GenerationParameters(
        maxTokens: 2048,
        temperature: 0.9,
        topP: 0.95,
        repetitionPenalty: 1.1
    )
    
    /// Balanced parameters (default)
    public static let balanced = GenerationParameters()
}

// MARK: - Inference Result

/// Result of a local inference operation
public struct InferenceResult: Sendable {
    /// Generated text
    public let text: String
    
    /// Number of tokens generated
    public let tokensGenerated: Int
    
    /// Time taken for generation
    public let generationTime: TimeInterval
    
    /// Tokens per second
    public let tokensPerSecond: Double
    
    /// Model used for generation
    public let modelUsed: ModelClass
    
    /// Whether generation was truncated due to max tokens
    public let wasTruncated: Bool
    
    /// Additional metadata
    public let metadata: [String: String]
}

// MARK: - Model Info

/// Information about a loaded model
public struct LoadedModelInfo: Sendable {
    public let modelClass: ModelClass
    public let quantization: QuantizationLevel
    public let parameterCount: Int
    public let memoryUsed: UInt64
    public let loadedAt: Date
    public let maxSequenceLength: Int
}

// MARK: - Local Inference Engine

/// Actor responsible for managing local MLX-based inference
public actor LocalInferenceEngine {
    
    // MARK: - Properties
    
    private var currentModel: (container: MLXModelContainer, info: LoadedModelInfo)?
    private var vramMonitor: VRAMMonitor
    private var thermalGuard: ThermalGuard
    private var isGenerating = false
    
    /// Default generation parameters
    public var defaultParameters: GenerationParameters = .balanced
    
    // MARK: - Initialization
    
    public init(
        vramMonitor: VRAMMonitor = VRAMMonitor(),
        thermalGuard: ThermalGuard = ThermalGuard()
    ) {
        self.vramMonitor = vramMonitor
        self.thermalGuard = thermalGuard
    }
    
    // MARK: - Model Loading
    
    /// Load a model from a directory
    /// - Parameter configuration: Model load configuration
    public func loadModel(configuration: ModelLoadConfiguration) async throws {
        // Check thermal state first
        let thermalStatus = await thermalGuard.getCurrentStatus()
        guard !thermalStatus.shouldSuspend else {
            throw LocalInferenceError.thermalThrottling
        }
        
        // Determine quantization
        let quantization: QuantizationLevel
        if configuration.useDynamicQuantization {
            quantization = try await vramMonitor.getRecommendedQuantization()
        } else {
            quantization = configuration.quantization
        }
        
        // Check if model can fit
        let requiredMemory = vramMonitor.estimateModelMemory(
            parameterCountBillions: Double(configuration.modelClass.parameterSize),
            quantization: quantization
        )
        
        guard await vramMonitor.canFitModel(requiredBytes: requiredMemory) else {
            throw LocalInferenceError.insufficientVRAM
        }
        
        // Unload current model if any
        if currentModel != nil {
            await unloadModel()
        }
        
        // Load the model using MLX
        do {
            let container = try await loadMLXModel(
                from: configuration.modelDirectory,
                modelClass: configuration.modelClass,
                quantization: quantization,
                maxSequenceLength: configuration.maxSequenceLength
            )
            
            let info = LoadedModelInfo(
                modelClass: configuration.modelClass,
                quantization: quantization,
                parameterCount: configuration.modelClass.parameterSize,
                memoryUsed: requiredMemory,
                loadedAt: Date(),
                maxSequenceLength: configuration.maxSequenceLength
            )
            
            currentModel = (container: container, info: info)
            
        } catch {
            throw LocalInferenceError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Load a model from mlx-community format directory
    /// - Parameters:
    ///   - directory: URL to the model directory containing config.json and weights
    ///   - modelClass: The class of model being loaded
    public func loadModel(directory: URL, modelClass: ModelClass) async throws {
        let config = ModelLoadConfiguration(
            modelClass: modelClass,
            modelDirectory: directory,
            useDynamicQuantization: true
        )
        try await loadModel(configuration: config)
    }
    
    /// Unload the current model to free memory
    public func unloadModel() async {
        currentModel = nil
        // In real MLX, we might need to manually clear cache
        // MLX.eval(MLX.clearCache())
    }
    
    /// Check if a model is currently loaded
    public func isModelLoaded() -> Bool {
        currentModel != nil
    }
    
    /// Get information about the currently loaded model
    public func getLoadedModelInfo() -> LoadedModelInfo? {
        currentModel?.info
    }
    
    // MARK: - Inference
    
    /// Generate text from a prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - parameters: Generation parameters (uses default if nil)
    /// - Returns: Inference result with generated text and metadata
    public func generate(
        prompt: String,
        parameters: GenerationParameters? = nil
    ) async throws -> InferenceResult {
        guard let (container, info) = currentModel else {
            throw LocalInferenceError.modelNotLoaded
        }
        
        // Check thermal state
        let thermalStatus = await thermalGuard.getCurrentStatus()
        guard !thermalStatus.shouldSuspend else {
            throw LocalInferenceError.thermalThrottling
        }
        
        let genParams = parameters ?? defaultParameters
        
        // Sanitize input
        let sanitizedPrompt = InputSanitizer().sanitize(prompt).sanitized
        
        let startTime = Date()
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            // Use MLX for generation
            let result = try await generateWithMLX(
                container: container,
                prompt: sanitizedPrompt,
                parameters: genParams,
                modelInfo: info
            )
            
            let generationTime = Date().timeIntervalSince(startTime)
            let tokensPerSecond = Double(result.tokensGenerated) / generationTime
            
            return InferenceResult(
                text: result.text,
                tokensGenerated: result.tokensGenerated,
                generationTime: generationTime,
                tokensPerSecond: tokensPerSecond,
                modelUsed: info.modelClass,
                wasTruncated: result.wasTruncated,
                metadata: [
                    "quantization": info.quantization.rawValue,
                    "temperature": String(genParams.temperature),
                    "maxTokens": String(genParams.maxTokens)
                ]
            )
            
        } catch {
            throw LocalInferenceError.generationFailed(error.localizedDescription)
        }
    }
    
    /// Stream generated tokens as they are produced.
    /// Note: True MLX streaming requires a callback architecture.
    /// This implementation wraps the simulated generator for UI feedback.
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - parameters: Generation parameters
    /// - Returns: Async stream of generated text chunks
    public func generateStreaming(
        prompt: String,
        parameters: GenerationParameters? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let (container, _) = currentModel else {
                        continuation.finish(throwing: LocalInferenceError.modelNotLoaded)
                        return
                    }
                    
                    let sanitized = InputSanitizer().sanitize(prompt).sanitized
                    let params = parameters ?? defaultParameters
                    
                    // Check thermal state
                    let thermalStatus = await thermalGuard.getCurrentStatus()
                    guard !thermalStatus.shouldSuspend else {
                        continuation.finish(throwing: LocalInferenceError.thermalThrottling)
                        return
                    }
                    
                    // Call the container's streaming method
                    let stream = await container.generateStream(prompt: sanitized, parameters: params)
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Model Management
    
    /// List available models in a directory
    /// - Parameter directory: Parent directory containing model subdirectories
    /// - Returns: Array of available model directories
    public func listAvailableModels(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        
        return contents.filter { url in
            // Check for model configuration file
            let configPath = url.appendingPathComponent("config.json")
            return fileManager.fileExists(atPath: configPath.path)
        }
    }
    
    /// Get recommended model for current system
    public func getRecommendedModel() async -> ModelClass {
        await vramMonitor.recommendModelClass()
    }
    
    /// Estimate memory required for a model
    public func estimateMemoryRequired(
        modelClass: ModelClass,
        quantization: QuantizationLevel
    ) -> UInt64 {
        vramMonitor.estimateModelMemory(
            parameterCountBillions: Double(modelClass.parameterSize),
            quantization: quantization
        )
    }
    
    // MARK: - Private MLX Integration
    
    private func loadMLXModel(
        from directory: URL,
        modelClass: ModelClass,
        quantization: QuantizationLevel,
        maxSequenceLength: Int
    ) async throws -> MLXModelContainer {
        // This bridges to the MLX wrapper
        // Real implementation would use MLXLLM's model loading
        
        let configPath = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw LocalInferenceError.invalidModelFormat("config.json not found")
        }
        
        let config = ModelLoadConfiguration(
            modelClass: modelClass,
            modelDirectory: directory,
            quantization: quantization,
            maxSequenceLength: maxSequenceLength
        )
        
        let container = try await MLXModelContainer.load(from: directory, config: config)
        return container
    }
    
    private func generateWithMLX(
        container: MLXModelContainer,
        prompt: String,
        parameters: GenerationParameters,
        modelInfo: LoadedModelInfo
    ) async throws -> (text: String, tokensGenerated: Int, wasTruncated: Bool) {
        // Bridge to MLX generation via the container
        // Real implementation would use MLXLLM's generate function
        
        // Set seed if provided
        if let seed = parameters.seed {
            MLXRandom.seed(seed)
        }
        
        return try await container.generate(prompt: prompt, parameters: parameters)
    }
}

// MARK: - MLX Model Wrapper (Bridge)

/// A wrapper around the actual MLX Model types to separate
/// our actor logic from the specific MLX implementation details.
/// This avoids "Sendable" warnings on raw MLX pointers and type conflicts.
internal actor MLXModelContainer {
    
    // In a real app, this would hold:
    // let model: LLMModel
    // let tokenizer: Tokenizer
    
    private init() {}
    
    static func load(from url: URL, config: ModelLoadConfiguration) async throws -> MLXModelContainer {
        // Logic to verify config.json and load weights using MLX
        // This is a placeholder for the actual MLX integration
        return MLXModelContainer()
    }
    
    func generate(prompt: String, parameters: GenerationParameters) async throws -> (text: String, tokensGenerated: Int, wasTruncated: Bool) {
        // Bridge to MLX
        // MLXRandom.seed(parameters.seed ?? 1234)
        return ("Simulated response from MLX for: \(prompt.prefix(20))...", 42, false)
    }
    
    func generateStream(prompt: String, parameters: GenerationParameters) -> AsyncThrowingStream<String, Error> {
        // Bridge to MLX streaming generator
        return AsyncThrowingStream { continuation in
            Task {
                // Simulate tokens for the build verification
                let words = prompt.split(separator: " ")
                for word in words {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms per token
                    continuation.yield(String(word) + " ")
                }
                continuation.finish()
            }
        }
    }
}
