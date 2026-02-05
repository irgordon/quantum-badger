import Foundation

final class CloudRuntimeAdapter: ModelRuntime, WarmableModelRuntime, @unchecked Sendable {
    let modelName: String
    private let apiKey: String?

    init(model: LocalModel, apiKey: String?) {
        self.modelName = model.name
        self.apiKey = apiKey
    }

    func warmUp() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    func generateResponse(for prompt: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw InferenceError.runtimeError("Missing API key.")
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        return "Cloud response from \(modelName): \(prompt)"
    }
}
