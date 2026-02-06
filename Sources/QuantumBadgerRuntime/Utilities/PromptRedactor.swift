import Foundation

public struct PromptRedactionResult {
    public let redactedText: String
    public let hadSensitiveData: Bool
}

public enum PromptRedactor {
    private static let regexes: [NSRegularExpression] = {
        let patterns = [
            "\\b\\d{3}-\\d{2}-\\d{4}\\b",
            "(?i)(api[_-]?key|secret|token)[^\\n\\r]{0,16}[:=][^\\s]{8,}",
            "-----BEGIN (EC|RSA|OPENSSH|PRIVATE) KEY-----"
        ]
        return patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern)
        }
    }()

    public static func redact(_ input: String) -> PromptRedactionResult {
        var text = input
        var found = false
        for regex in regexes {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                found = true
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[REDACTED]")
            }
        }

        return PromptRedactionResult(redactedText: text, hadSensitiveData: found)
    }
}
