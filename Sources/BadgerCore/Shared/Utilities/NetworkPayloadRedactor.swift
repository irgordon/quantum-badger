import Foundation

public enum NetworkPayloadRedactor {
    public struct RedactionResult: Sendable {
        public let didRedact: Bool
        public let data: Data
    }
    
    // 🔒 CONFIG: Centralized list of keys to redact
    private static let sensitiveKeys: Set<String> = [
        "password", "pwd", "token", "api_key", "apikey", 
        "secret", "client_secret", "authorization", "bearer",
        "access_token", "refresh_token", "session_id"
    ]

    public static func redactJSONPayload(_ data: Data) async -> RedactionResult {
        // 1. Attempt partial decode to Any
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return RedactionResult(didRedact: false, data: data)
        }
        
        // 2. Recursively sanitize
        let (sanitized, didChange) = recursiveRedact(json)
        
        // 3. Re-encode only if necessary
        if didChange {
            // Using .sortedKeys for consistent audit logs
            if let newData = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys, .prettyPrinted]) {
                return RedactionResult(didRedact: true, data: newData)
            }
        }
        
        return RedactionResult(didRedact: false, data: data)
    }

    // Recursive helper that returns (NewValue, DidChange)
    private static func recursiveRedact(_ value: Any) -> (Any, Bool) {
        var didChange = false
        
        if var dict = value as? [String: Any] {
            var newDict = dict // Work on copy
            for (key, val) in dict {
                // A. Check Key Name
                if sensitiveKeys.contains(key.lowercased()) {
                    newDict[key] = "[REDACTED]"
                    didChange = true
                } else {
                    // B. Recurse into value
                    let (newVal, childChanged) = recursiveRedact(val)
                    if childChanged {
                        newDict[key] = newVal
                        didChange = true
                    }
                }
            }
            return (newDict, didChange)
        } 
        else if let array = value as? [Any] {
            // C. Handle Arrays
            var newArray: [Any] = []
            for item in array {
                let (newItem, childChanged) = recursiveRedact(item)
                if childChanged { didChange = true }
                newArray.append(newItem)
            }
            return (newArray, didChange)
        }
        
        // Leaf values (String, Number, Bool, Null) are returned as-is
        return (value, didChange)
    }
}
