import Foundation

struct FilesystemWriteTool: SecureInjectionTool {
    let toolName: String = "filesystem.write"

    func run(
        request: ToolRequest,
        vaultStore: VaultStore,
        secretRedactor: SecretRedactor,
        limits: ToolExecutionLimits
    ) async throws -> ToolResult {
        let contents = request.input["contents"] ?? ""
        if let resolution = resolveBookmarkResolution(from: request, vaultStore: vaultStore, redactor: secretRedactor) {
            if resolution.isStale {
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
            let didStart = resolution.url.startAccessingSecurityScopedResource()
            defer {
                if didStart { resolution.url.stopAccessingSecurityScopedResource() }
            }
            return write(contents: contents, to: resolution.url, toolName: request.toolName, id: request.id)
        }
        let path = resolvePath(from: request, vaultStore: vaultStore, redactor: secretRedactor)
        guard let path, !path.isEmpty else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Missing file path."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        do {
            let url = URL(fileURLWithPath: path)
            return write(contents: contents, to: url, toolName: request.toolName, id: request.id)
        } catch {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Couldn’t write the file."],
                succeeded: false,
                finishedAt: Date()
            )
        }
    }

    private func write(contents: String, to url: URL, toolName: String, id: UUID) -> ToolResult {
        do {
            let data = Data(contents.utf8)
            try data.write(to: url, options: [.atomic])
            return ToolResult(
                id: id,
                toolName: toolName,
                output: ["status": "written", "path": url.path],
                succeeded: true,
                finishedAt: Date()
            )
        } catch {
            return ToolResult(
                id: id,
                toolName: toolName,
                output: ["error": "Couldn’t write the file."],
                succeeded: false,
                finishedAt: Date()
            )
        }
    }

    private func resolveBookmarkResolution(
        from request: ToolRequest,
        vaultStore: VaultStore,
        redactor: SecretRedactor
    ) -> VaultStore.BookmarkResolution? {
        if let refLabel = request.input["pathRef"],
           let references = request.vaultReferences,
           let reference = references.first(where: { $0.label == refLabel }),
           let resolution = vaultStore.bookmarkResolution(for: reference) {
            redactor.register(resolution.url.path)
            return resolution
        }
        return nil
    }

    private func resolvePath(
        from request: ToolRequest,
        vaultStore: VaultStore,
        redactor: SecretRedactor
    ) -> String? {
        if let refLabel = request.input["pathRef"],
           let references = request.vaultReferences,
           let reference = references.first(where: { $0.label == refLabel }),
           let secretPath = vaultStore.secret(for: reference),
           !secretPath.hasPrefix("bookmark:") {
            redactor.register(secretPath)
            return secretPath
        }
        return nil
    }
}
