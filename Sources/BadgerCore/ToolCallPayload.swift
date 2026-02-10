import Foundation

public struct ToolCallPayload: Sendable, Codable {
    public let toolName: String
    public let arguments: [String: String] // Simplified for now, or JSON string?
    // User snippet implies parsed structure or raw JSON?
    // ConstrainedJSONScanner.parseToolCall likely returns this.
    // Let's assume arguments is a dict or a JSON string.
    // Given "ConstrainedJSONScanner", it likely extracts structured data.
    // I'll use [String: String] for simplicity or [String: Any] (unsafe for Sendable).
    // Let's use `SharedJSON` or keep it `[String: String]` for arguments if flattened, or just `String` for raw JSON args.
    // I'll stick to a struct that holds the relevant info.
    public let rawArguments: String
    
    public init(toolName: String, rawArguments: String) {
        self.toolName = toolName
        self.rawArguments = rawArguments
    }
}
