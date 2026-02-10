import Foundation
import BadgerCore

/// Bridges LocalMLXInference to LocalMLXRuntimeAdapter.
public final class LocalMLXAdapter: LocalMLXRuntimeAdapter {
    private let config: ModelConfiguration
    
    public init(config: ModelConfiguration) {
        self.config = config
    }
    
    public func streamResponse(for prompt: String, kind: TaskKind) -> AsyncThrowingStream<QuantumMessage, Error> {
        // LocalMLXInference.generate returns AsyncStream (non-throwing) but the func is throws.
        // So it returns AsyncStream, but the call awaits throws.
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await LocalMLXInference.shared.generate(prompt: prompt, config: config, kind: kind)
                    for await message in stream {
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func cancelGeneration() {
        LocalMLXInference.shared.cancelGeneration()
    }
}

// Conformance to WarmableModelRuntime
extension LocalMLXAdapter: WarmableModelRuntime {
    public func warmUp() async {
        await LocalMLXInference.shared.warmUp(modelPath: config.modelPath)
    }
}
