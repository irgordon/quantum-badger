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
}

/// A "Stub" adapter for proving the flow without a large model file
final class LocalStubAdapter: ModelRuntime, @unchecked Sendable {
    let modelName = "Badger-Alpha-Stub"

    func generateResponse(for prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return "Stub response to: '\(prompt)'. The local inference pipeline is functional."
    }
}
