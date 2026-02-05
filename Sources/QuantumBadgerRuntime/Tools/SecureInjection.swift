import Foundation
import LocalAuthentication

protocol SecureInjectionTool {
    var toolName: String { get }
    func run(
        request: ToolRequest,
        vaultStore: VaultStore,
        secretRedactor: SecretRedactor,
        limits: ToolExecutionLimits
    ) async throws -> ToolResult
}

enum SecureToolRegistry {
    static let tools: [String: SecureInjectionTool] = [
        "filesystem.write": FilesystemWriteTool(),
        "db.query": SecureDatabaseQueryTool()
    ]
}
