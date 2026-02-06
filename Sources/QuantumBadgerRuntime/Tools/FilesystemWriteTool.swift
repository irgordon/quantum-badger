import Foundation

struct FilesystemWriteTool: SecureInjectionTool {
    let toolName: String = "filesystem.write"
    private let fileWriter = FileWriterXPCClient()

    func run(
        request: ToolRequest,
        vaultStore: VaultStore,
        secretRedactor: SecretRedactor,
        limits: ToolExecutionLimits
    ) async throws -> ToolResult {
        let contents = request.input["contents"] ?? ""
        guard let bookmarkData = resolveBookmarkData(from: request, vaultStore: vaultStore) else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Missing secure file location."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        do {
            let response = try await fileWriter.writeFile(
                requestId: request.id,
                bookmarkData: bookmarkData,
                contents: contents,
                maxBytes: limits.maxFileBytes
            )
            if response.isStale {
                return ToolResult(
                    id: request.id,
                    toolName: request.toolName,
                    output: [
                        "error": "Saved location needs to be chosen again.",
                        "staleBookmark": "true"
                    ],
                    succeeded: false,
                    finishedAt: Date()
                )
            }
            if let path = response.path {
                secretRedactor.register(path)
            }
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["status": "written", "path": response.path ?? ""],
                succeeded: true,
                finishedAt: Date()
            )
        } catch {
            let message = error is CancellationError ? "File write cancelled." : "Couldn’t write the file."
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": message],
                succeeded: false,
                finishedAt: Date()
            )
        }
    }

    private func resolveBookmarkData(from request: ToolRequest, vaultStore: VaultStore) -> Data? {
        guard let refLabel = request.input["pathRef"],
              let references = request.vaultReferences,
              let reference = references.first(where: { $0.label == refLabel }) else {
            return nil
        }
        return vaultStore.bookmarkData(for: reference)
    }
}
