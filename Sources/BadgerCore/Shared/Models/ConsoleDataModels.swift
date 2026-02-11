import Foundation

// MARK: - Enums

public enum WorkflowStepStatus: String, Sendable, Codable, Equatable {
    case pending
    case awaitingApproval
    case running
    case completed
    case failed
    case skipped
}

// MARK: - The Plan (Mutable)

public struct WorkflowPlan: Identifiable, Sendable {
    public let id: UUID
    public let intent: String
    
    /// Changed to 'var' to allow status updates and result attachment.
    public var steps: [WorkflowStep]
    
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    
    public init(
        id: UUID = UUID(),
        intent: String,
        steps: [WorkflowStep],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.intent = intent
        self.steps = steps
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct WorkflowStep: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let tool: String
    
    /// Using the generic payload concept for flexible inputs
    public let input: ToolCallPayload
    
    public let requiresApproval: Bool
    
    /// Mutable state tracking
    public var status: WorkflowStepStatus = .pending
    
    /// The result is attached directly to the step once available
    public var result: ToolResult?
    
    public init(
        id: UUID = UUID(),
        title: String,
        tool: String,
        input: ToolCallPayload,
        requiresApproval: Bool,
        status: WorkflowStepStatus = .pending,
        result: ToolResult? = nil
    ) {
        self.id = id
        self.title = title
        self.tool = tool
        self.input = input
        self.requiresApproval = requiresApproval
        self.status = status
        self.result = result
    }
}

// MARK: - Results

public struct ToolResult: Identifiable, Sendable {
    public let id: UUID
    /// Optional: Link back to the step ID for database normalization
    public let stepId: UUID
    
    public let toolName: String
    
    /// Raw output (JSON string) for flexibility
    public let rawOutput: String
    public let succeeded: Bool
    public let finishedAt: Date
    
    // Placeholder for your messaging type
    public let normalizedMessages: [QuantumMessage]?
    
    public init(
        id: UUID = UUID(),
        stepId: UUID,
        toolName: String,
        rawOutput: String,
        succeeded: Bool,
        finishedAt: Date = Date(),
        normalizedMessages: [QuantumMessage]? = nil
    ) {
        self.id = id
        self.stepId = stepId
        self.toolName = toolName
        self.rawOutput = rawOutput
        self.succeeded = succeeded
        self.finishedAt = finishedAt
        self.normalizedMessages = normalizedMessages
    }
}

// MARK: - Legacy / Helper Models

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
