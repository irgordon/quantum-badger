import Foundation

public struct ToolCallPayload: Sendable, Codable {
    public let toolName: String
    
    /// The arguments formatted as a JSON string.
    /// Kept as a string to ensure `Sendable` compliance and decoupling.
    public let rawArguments: String
    
    public init(toolName: String, rawArguments: String) {
        self.toolName = toolName
        self.rawArguments = rawArguments
    }
    
    /// Specific helper to decode the arguments into a concrete type.
    public func arguments<T: Decodable>(as type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        guard let data = rawArguments.data(using: .utf8) else {
            throw ToolCallError.invalidStringData
        }
        return try decoder.decode(T.self, from: data)
    }
}

// Simple error handling for the helper
public enum ToolCallError: Error {
    case invalidStringData
}
