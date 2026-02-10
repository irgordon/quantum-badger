import Foundation
import BadgerCore

#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif

@MainActor
public final class LocalMLXInference {
    public static let shared = LocalMLXInference()

    private var modelContainer: ModelContainer?
    private let generationState = MLXGenerationState()

    private init() {}

    public func warmUp(modelPath: String) async {
        do {
            _ = try await loadModel(configuration: ModelConfiguration(modelPath: modelPath))
        } catch {
            return
        }
    }

    public func generate(
        prompt: String,
        config: ModelConfiguration,
        kind: TaskKind = .chat
    ) async throws -> AsyncStream<QuantumMessage> {
        let container = try await loadModel(configuration: config)
        await generationState.reset()

        return try await NPUAffinityManager.shared.executeWithAffinity(kind: kind) {
            AsyncStream { continuation in
                let task = Task(priority: kind == .chat ? .userInitiated : .utility) {
                    var tokenBuffer = ""
                    var lastFlushTask: Task<Void, Never>?
                    do {
                        #if canImport(MLXLMCommon)
                        // Using MLX if avail
                        let _ = try await MLXLMCommon.generate(
                            input: prompt,
                            parameters: GenerateParameters(temperature: 0.7),
                            model: container.model,
                            tokenizer: container.tokenizer
                        ) { tokens in
                            tokenBuffer += tokens

                            if tokenBuffer.contains(" ") || tokenBuffer.count > 20 {
                                let buffer = tokenBuffer
                                tokenBuffer = ""
                                let nextFlush = Task {
                                    if let lastFlushTask {
                                        _ = await lastFlushTask.value
                                    }
                                    if Task.isCancelled { return }
                                    let secureMsg = await IntentResultNormalizer.normalize(
                                        rawText: buffer,
                                        kind: .text,
                                        source: .system, // Or .assistant?
                                        toolName: "LocalMLX",
                                        createdAt: Date()
                                    ).message
                                    continuation.yield(secureMsg)
                                }
                                lastFlushTask = nextFlush
                            }

                            if Task.isCancelled {
                                return .stop
                            }

                            return .active
                        }
                        #else
                        // Simulation for compilation without MLX
                        // Simulate token streaming
                        let words = "This is a simulated response from the NPU.".components(separatedBy: " ")
                        for word in words {
                            try await Task.sleep(nanoseconds: 100_000_000)
                            let msg = await IntentResultNormalizer.normalize(
                                rawText: word + " ",
                                kind: .text,
                                source: .assistant,
                                toolName: "LocalMLX",
                                createdAt: Date()
                            ).message
                            continuation.yield(msg)
                        }
                        #endif

                        if let lastFlushTask {
                            _ = await lastFlushTask.value
                        }

                        if Task.isCancelled {
                            continuation.finish()
                            await generationState.clear()
                            return
                        }

                        if !tokenBuffer.isEmpty {
                            let finalMsg = await IntentResultNormalizer.normalize(
                                rawText: tokenBuffer,
                                kind: .text,
                                source: .system,
                                toolName: "LocalMLX",
                                createdAt: Date()
                            ).message
                            continuation.yield(finalMsg)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    await generationState.clear()
                }
                Task { await generationState.setTask(task) }
            }
        }
    }

    public func cancelGeneration() {
        Task { await generationState.cancel() }
    }

    public func purgeContext() async {
        await generationState.cancel()
        modelContainer = nil
    }

    private func loadModel(configuration: ModelConfiguration) async throws -> ModelContainer {
        if let container = modelContainer {
            return container
        }
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        modelContainer = container
        return container
    }
}

public actor MLXGenerationState {
    private var currentTask: Task<Void, Never>?
    
    public init() {}

    public func setTask(_ task: Task<Void, Never>) {
        currentTask = task
    }

    public func reset() {
        currentTask = nil
    }

    public func cancel() {
        currentTask?.cancel()
    }

    public func clear() {
        currentTask = nil
    }
}
