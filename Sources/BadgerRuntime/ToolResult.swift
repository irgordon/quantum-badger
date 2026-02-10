import Foundation

/// Represents the raw output from a tool execution.
public struct ToolResult: Sendable {
    public let toolName: String
    public let succeeded: Bool
    public let output: [String: String]
    public let finishedAt: Date
    
    public init(toolName: String, succeeded: Bool, output: [String: String], finishedAt: Date = Date()) {
        self.toolName = toolName
        self.succeeded = succeeded
        self.output = output
        self.finishedAt = finishedAt
    }
}
