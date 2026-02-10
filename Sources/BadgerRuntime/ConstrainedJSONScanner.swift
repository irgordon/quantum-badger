import Foundation
import BadgerCore

public enum ConstrainedJSONScanner {
    /// Attempts to parse a tool call from a string fragment.
    /// Expected format: {"tool": "name", "args": {...}} or similar.
    public static func parseToolCall(from text: String) -> ToolCallPayload? {
        // Simplified scanner that looks for valid JSON tool call structure.
        // In a real implementation, this would use a robust state machine.
        // Here we regex for a simplified pattern or try to decode.
        
        guard let data = text.data(using: .utf8) else { return nil }
        
        // Try decoding as a known structure
        struct Candidate: Decodable {
            let tool: String
            let args: String // Or AnyCodable?
            // Or maybe "toolCall": { name, args }
            // User snippet checks for "toolCall" or "tool_call".
        }
        
        // Regex approach for robustness against partial tokens
        // Pattern: "toolCall"\s*:\s*{\s*"name"\s*:\s*"(\w+)"\s*,\s*"arguments"\s*:\s*({.*?})\s*}
        // This is tricky.
        
        // For this mock/stub, we'll try to find a valid JSON object
        // that has "tool" and "args" keys.
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = json["tool"] as? String, let args = json["args"] {
                // serialized args
                let argsString = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return ToolCallPayload(toolName: name, rawArguments: argsString)
            }
            if let toolCall = json["toolCall"] as? [String: Any],
               let name = toolCall["name"] as? String,
               let args = toolCall["arguments"] {
                 let argsString = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                 return ToolCallPayload(toolName: name, rawArguments: argsString)
            }
        }
        
        return nil
    }
}
