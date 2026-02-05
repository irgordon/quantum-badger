import Foundation

public struct PromptRedactionResult {
    public let redactedText: String
    public let hadSensitiveData: Bool
}

public enum PromptRedactor {
    public static func redact(_ input: String) -> PromptRedactionResult {
        var text = input
        var found = false

        let patterns = [
            "\\b\\d{3}-\\d{2}-\\d{4}\\b",
            "(?i)(api[_-]?key|secret|token)[^\\n\\r]{0,16}[:=][^\\s]{8,}",
            "-----BEGIN (EC|RSA|OPENSSH|PRIVATE) KEY-----"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    found = true
                    text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[REDACTED]")
                }
            }
        }

        return PromptRedactionResult(redactedText: text, hadSensitiveData: found)
    }
}
