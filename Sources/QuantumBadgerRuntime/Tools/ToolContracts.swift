import Foundation

struct ToolCapability: Hashable, Codable {
    var name: String
    var riskLevel: RiskLevel
}

enum RiskLevel: String, Codable {
    case low
    case medium
    case high
}

struct ToolContract: Codable {
    var name: String
    var capabilities: [ToolCapability]
    var requiredPermissions: [String]
    var scopes: [String]
    var inputSchema: String
    var outputSchema: String
    var cost: Int
    var riskLevel: RiskLevel
    var limits: ToolExecutionLimits
    var requiresSecureInjection: Bool
}

struct ToolExecutionLimits: Codable {
    var timeoutSeconds: Double
    var maxOutputBytes: Int
    var maxFileBytes: Int
    var maxMatches: Int
    var maxQueryTokens: Int

    static let `default` = ToolExecutionLimits(
        timeoutSeconds: 10,
        maxOutputBytes: 200_000,
        maxFileBytes: 2_000_000,
        maxMatches: 100,
        maxQueryTokens: 512
    )
}

enum ToolCatalog {
    static let contracts: [String: ToolContract] = [
        "local.search": ToolContract(
            name: "local.search",
            capabilities: [ToolCapability(name: "filesystem.read", riskLevel: .medium)],
            requiredPermissions: [],
            scopes: ["files.read", "bookmarks.only"],
            inputSchema: "query: string",
            outputSchema: "matches: [LocalSearchMatch]",
            cost: 2,
            riskLevel: .medium,
            limits: ToolExecutionLimits(
                timeoutSeconds: 4,
                maxOutputBytes: 200_000,
                maxFileBytes: 2_000_000,
                maxMatches: 100,
                maxQueryTokens: 0
            ),
            requiresSecureInjection: false
        ),
        "filesystem.write": ToolContract(
            name: "filesystem.write",
            capabilities: [ToolCapability(name: "filesystem.write", riskLevel: .high)],
            requiredPermissions: ["filesystem.write"],
            scopes: ["files.write", "user.selected"],
            inputSchema: "path: string | pathRef: string, contents: string",
            outputSchema: "status: string",
            cost: 5,
            riskLevel: .high,
            limits: .default,
            requiresSecureInjection: true
        ),
        "analysis": ToolContract(
            name: "analysis",
            capabilities: [],
            requiredPermissions: [],
            scopes: [],
            inputSchema: "intent: string",
            outputSchema: "summary: string",
            cost: 1,
            riskLevel: .low,
            limits: .default,
            requiresSecureInjection: false
        ),
        "draft": ToolContract(
            name: "draft",
            capabilities: [],
            requiredPermissions: [],
            scopes: [],
            inputSchema: "summary: string",
            outputSchema: "draft: string",
            cost: 1,
            riskLevel: .low,
            limits: .default,
            requiresSecureInjection: false
        ),
        "untrusted.parse": ToolContract(
            name: "untrusted.parse",
            capabilities: [ToolCapability(name: "untrusted.parse", riskLevel: .high)],
            requiredPermissions: [],
            scopes: ["untrusted.parse"],
            inputSchema: "payload: string",
            outputSchema: "result: string",
            cost: 3,
            riskLevel: .high,
            limits: ToolExecutionLimits(
                timeoutSeconds: 3,
                maxOutputBytes: 50_000,
                maxFileBytes: 0,
                maxMatches: 0,
                maxQueryTokens: 0
            ),
            requiresSecureInjection: false
        ),
        "db.query": ToolContract(
            name: "db.query",
            capabilities: [ToolCapability(name: "database.read", riskLevel: .high)],
            requiredPermissions: [],
            scopes: ["database.read", "vault.references"],
            inputSchema: "connectionRef: string, query: string",
            outputSchema: "columns: [string], rows: [[string]]",
            cost: 4,
            riskLevel: .high,
            limits: ToolExecutionLimits(
                timeoutSeconds: 5,
                maxOutputBytes: 200_000,
                maxFileBytes: 20_000_000,
                maxMatches: 0,
                maxQueryTokens: 512
            ),
            requiresSecureInjection: true
        ),
        "message.send": ToolContract(
            name: "message.send",
            capabilities: [ToolCapability(name: "messaging.send", riskLevel: .high)],
            requiredPermissions: [],
            scopes: ["trusted.contacts", "user.approval"],
            inputSchema: "recipient: string, body: string, conversationKey?: string",
            outputSchema: "status: string",
            cost: 5,
            riskLevel: .high,
            limits: ToolExecutionLimits(
                timeoutSeconds: 6,
                maxOutputBytes: 10_000,
                maxFileBytes: 0,
                maxMatches: 0,
                maxQueryTokens: 0
            ),
            requiresSecureInjection: false
        ),
        "web.scout": ToolContract(
            name: "web.scout",
            capabilities: [ToolCapability(name: "web.fetch", riskLevel: .medium)],
            requiredPermissions: [],
            scopes: ["web.allowlist", "content.filters"],
            inputSchema: "query: string",
            outputSchema: "result: string",
            cost: 3,
            riskLevel: .medium,
            limits: ToolExecutionLimits(
                timeoutSeconds: 8,
                maxOutputBytes: 1_000_000,
                maxFileBytes: 0,
                maxMatches: 0,
                maxQueryTokens: 0
            ),
            requiresSecureInjection: false
        )
    ]

    static func contract(for toolName: String) -> ToolContract? {
        contracts[toolName]
    }
}

struct ToolRequest: Codable {
    var id: UUID
    var toolName: String
    var input: [String: String]
    var vaultReferences: [VaultReference]?
    var requestedAt: Date
}

struct ToolResult: Codable {
    var id: UUID
    var toolName: String
    var output: [String: String]
    var succeeded: Bool
    var finishedAt: Date
    var normalizedMessages: [QuantumMessage]? = nil
}
