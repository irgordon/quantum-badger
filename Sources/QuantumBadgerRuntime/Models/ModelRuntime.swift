import Foundation

enum InferenceError: Error {
    case modelNotFound
    case contextOverflow
    case timeout
    case runtimeError(String)
}

/// The blueprint for any model connection (Local or Cloud)
protocol ModelRuntime: Sendable {
    var modelName: String { get }
    func generateResponse(for prompt: String) async throws -> String
    func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error>
    func cancelGeneration()
}

extension ModelRuntime {
    func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateResponse(for: prompt)
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancelGeneration() {
        // Default: no-op for non-cancellable runtimes.
    }
}

/// A "Stub" adapter for proving the flow without a large model file
final class LocalStubAdapter: ModelRuntime, @unchecked Sendable {
    let modelName = "Badger-Alpha-Stub"
    private let streamState = StubStreamState()

    func generateResponse(for prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return "Stub response to: '\(prompt)'. The local inference pipeline is functional."
    }

    func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await streamState.setContinuation(continuation)
                let parts = [
                    "Stub response to: '",
                    prompt,
                    "'. The local inference pipeline ",
                    "is functional."
                ]
                for part in parts {
                    if await streamState.isCancelled() {
                        continuation.finish()
                        await streamState.clear()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continuation.yield(part)
                }
                continuation.finish()
                await streamState.clear()
            }
        }
    }

    func cancelGeneration() {
        Task { await streamState.cancel() }
    }
}

actor StubStreamState {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var cancelled: Bool = false

    func setContinuation(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
        cancelled = false
    }

    func cancel() {
        cancelled = true
        continuation?.finish()
    }

    func isCancelled() -> Bool {
        cancelled
    }

    func clear() {
        continuation = nil
        cancelled = false
    }
}
