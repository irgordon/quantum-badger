import Foundation

final class LocalGGUFRuntimeAdapter: ModelRuntime, WarmableModelRuntime, @unchecked Sendable {
    let modelName: String
    private let modelPath: String

    init(model: LocalModel) {
        self.modelName = model.name
        self.modelPath = model.path
    }

    func warmUp() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    func generateResponse(for prompt: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw InferenceError.modelNotFound
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        return "Local GGUF response from \(modelName): \(prompt)"
    }
}
