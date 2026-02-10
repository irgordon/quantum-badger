import Foundation

@preconcurrency import MLX
@preconcurrency import MLXLLM

// Stubbing MLX types if they are not available during this compilation phase
// But we assume the environment has them or we use #if canImport
// The user code uses #if canImport. I will do the same.

#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif

public struct ModelConfiguration: Sendable {
    public let modelPath: String
    public init(modelPath: String) {
        self.modelPath = modelPath
    }
}

public struct ModelContainer: Sendable {
    // If MLX is not imported, these types won't exist.
    // We'll use Any or a mock type if needed.
    // But since the user code uses `container.model` and `container.tokenizer` in `MLXLMCommon.generate`,
    // they must be the actual MLX types.
    
    #if canImport(MLXLLM)
    public let model: LLMModel
    public let tokenizer: Tokenizer
    #else
    public let model: Any
    public let tokenizer: Any
    #endif
}

public actor LLMModelFactory {
    public static let shared = LLMModelFactory()
    
    private init() {}
    
    public func loadContainer(configuration: ModelConfiguration) async throws -> ModelContainer {
        // Stub implementation. Real one loads from disk.
        #if canImport(MLXLLM)
        // Ensure this compiles even if MLX absent using ifdef
        // In simulation, we throw or return dummy.
        // Since we likely don't have MLX in this environment, we'll throw.
        throw NSError(domain: "LLMModelFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLX not available"])
        #else
        // Simulating load for non-MLX environment
        return ModelContainer(model: "SimulatedModel", tokenizer: "SimulatedTokenizer")
        #endif
    }
}
