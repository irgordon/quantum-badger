import Foundation

public struct PromptRedactionResult {
    public let redactedText: String
    public let hadSensitiveData: Bool
}

public enum PromptRedactor {
    // Performance: compile a single alternation regex once, and run one pass replacement.
    private static let redactionRegex: NSRegularExpression? = {
        let pattern = "(?:\\b\\d{3}-\\d{2}-\\d{4}\\b|(?i:(?:api[_-]?key|secret|token)[^\\n\\r]{0,16}[:=][^\\s]{8,})|-----BEGIN (?:EC|RSA|OPENSSH|PRIVATE) KEY-----)"
        return try? NSRegularExpression(pattern: pattern)
    }()

    public static func redact(_ input: String) -> PromptRedactionResult {
        guard let regex = redactionRegex else {
            return PromptRedactionResult(redactedText: input, hadSensitiveData: false)
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let redacted = regex.stringByReplacingMatches(in: input, range: range, withTemplate: "[REDACTED]")
        return PromptRedactionResult(redactedText: redacted, hadSensitiveData: redacted != input)
    }
}
