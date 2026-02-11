import Foundation
import BadgerCore

public actor OutboundPrivacyFilter {
    public static let shared = OutboundPrivacyFilter()
    public static var auditLog: AuditLog?

    private static let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b"#
    private static let cardCandidatePattern = #"\b(?:\d[ -]?){13,19}\b"#
    private static let localPathPattern = #"/(Users|Volumes|Library)/[a-zA-Z0-9._/-]+"#
    private static let credentialAssignmentPattern = #"(?i)(?:api[_-]?key|secret|token|password|pwd)[^\n\r]{0,20}[:=]\s*["']?[^\s"']{8,}"#
    private static let providerKeyPattern = #"(?i)\b(?:sk-[a-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})\b"#

    private let ssnRegex: NSRegularExpression?
    private let cardCandidateRegex: NSRegularExpression?
    private let localPathRegex: NSRegularExpression?
    private let credentialAssignmentRegex: NSRegularExpression?
    private let providerKeyRegex: NSRegularExpression?

    public init() {
        self.ssnRegex = try? NSRegularExpression(pattern: Self.ssnPattern)
        self.cardCandidateRegex = try? NSRegularExpression(pattern: Self.cardCandidatePattern)
        self.localPathRegex = try? NSRegularExpression(pattern: Self.localPathPattern)
        self.credentialAssignmentRegex = try? NSRegularExpression(pattern: Self.credentialAssignmentPattern)
        self.providerKeyRegex = try? NSRegularExpression(pattern: Self.providerKeyPattern)
    }

    public enum OutboundPrivacyFilterError: Error {
        case blockedByPolicy
    }

    public func filter(_ content: String) async throws -> String {
        let range = NSRange(location: 0, length: content.utf16.count)

        if ssnRegex?.firstMatch(in: content, options: [], range: range) != nil {
            try await block(reason: "Outbound SSN pattern blocked")
        }

        if localPathRegex?.firstMatch(in: content, options: [], range: range) != nil {
            try await block(reason: "Outbound local path pattern blocked")
        }

        if credentialAssignmentRegex?.firstMatch(in: content, options: [], range: range) != nil {
            try await block(reason: "Outbound credential assignment blocked")
        }

        if providerKeyRegex?.firstMatch(in: content, options: [], range: range) != nil {
            try await block(reason: "Outbound provider key pattern blocked")
        }

        if containsValidCardNumber(in: content, searchRange: range) {
            try await block(reason: "Outbound card-like value blocked")
        }

        return content
    }

    private func block(reason: String) async throws -> Never {
        await Self.auditLog?.record(event: .securityViolationDetected(reason))
        throw OutboundPrivacyFilterError.blockedByPolicy
    }

    private func containsValidCardNumber(in content: String, searchRange: NSRange) -> Bool {
        guard let cardCandidateRegex else { return false }
        let matches = cardCandidateRegex.matches(in: content, options: [], range: searchRange)
        guard !matches.isEmpty else { return false }

        for match in matches {
            guard let range = Range(match.range, in: content) else { continue }
            let candidate = String(content[range])
            let digits = candidate.filter { $0.isNumber }
            if digits.count >= 13, digits.count <= 19, passesLuhn(digits) {
                return true
            }
        }
        return false
    }

    private func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed().map { Int(String($0)) ?? 0 }
        for (index, value) in reversed.enumerated() {
            if index % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum > 0 && sum % 10 == 0
    }
}
