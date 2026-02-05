import Foundation

public struct PromptRedactionResult {
    public let redactedText: String
    public let hadSensitiveData: Bool
}

public enum PromptRedactor {
    private static let regexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b"),
        try! NSRegularExpression(pattern: "(?i)(api[_-]?key|secret|token)[^\\n\\r]{0,16}[:=][^\\s]{8,}"),
        try! NSRegularExpression(pattern: "-----BEGIN (EC|RSA|OPENSSH|PRIVATE) KEY-----")
    ]

    public static func redact(_ input: String) -> PromptRedactionResult {
        var text = input
        var found = false
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for regex in regexes {
            if regex.firstMatch(in: text, range: range) != nil {
                found = true
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[REDACTED]")
            }
        }

        return PromptRedactionResult(redactedText: text, hadSensitiveData: found)
    }
}
