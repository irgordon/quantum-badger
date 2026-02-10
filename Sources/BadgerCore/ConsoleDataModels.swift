import Foundation

public struct WorkflowPlan: Identifiable, Sendable {
    public let id: UUID
    public let intent: String
    public let steps: [WorkflowStep]
    
    public init(id: UUID = UUID(), intent: String, steps: [WorkflowStep]) {
        self.id = id
        self.intent = intent
        self.steps = steps
    }
}

public struct WorkflowStep: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let tool: String
    public var input: [String: String]
    public let requiresApproval: Bool
    
    public init(id: UUID = UUID(), title: String, tool: String, input: [String: String], requiresApproval: Bool) {
        self.id = id
        self.title = title
        self.tool = tool
        self.input = input
        self.requiresApproval = requiresApproval
    }
}

public struct ToolResult: Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let output: [String: String]
    public let succeeded: Bool
    public let finishedAt: Date
    public let normalizedMessages: [QuantumMessage]? // Optional for now
    
    public init(id: UUID, toolName: String, output: [String: String], succeeded: Bool, finishedAt: Date, normalizedMessages: [QuantumMessage]? = nil) {
        self.id = id
        self.toolName = toolName
        self.output = output
        self.succeeded = succeeded
        self.finishedAt = finishedAt
        self.normalizedMessages = normalizedMessages
    }
}

public struct VaultReference: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let label: String
    // In a real app, this would wrap a security-scoped bookmark
    
    public init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}

public struct ExecutionHint: Sendable {
    public let allowPublicCloud: Bool
    
    public init(allowPublicCloud: Bool) {
        self.allowPublicCloud = allowPublicCloud
    }
}
