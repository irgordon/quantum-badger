import Foundation

enum MemoryPIIScanner {
    static func scan(_ content: String) -> PIIResult {
        let ssnPattern = "\\b\\d{3}-\\d{2}-\\d{4}\\b"
        let apiKeyPattern = "(?i)(api[_-]?key|secret|token)[^\\n\\r]{0,16}[:=][^\\s]{8,}"
        let privateKeyPattern = "-----BEGIN (EC|RSA|OPENSSH|PRIVATE) KEY-----"

        let hasSSN = content.range(of: ssnPattern, options: .regularExpression) != nil
        let hasAPIKey = content.range(of: apiKeyPattern, options: .regularExpression) != nil
        let hasPrivateKey = content.contains(privateKeyPattern)

        return PIIResult(containsSensitiveData: hasSSN || hasAPIKey || hasPrivateKey)
    }
}

struct PIIResult {
    let containsSensitiveData: Bool
}
