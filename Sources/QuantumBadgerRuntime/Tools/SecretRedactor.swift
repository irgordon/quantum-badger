import Foundation
import NaturalLanguage

final class SecretRedactor {
    private var secrets: [String] = []

    func register(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !secrets.contains(trimmed) {
            secrets.append(trimmed)
        }
    }

    func redact(_ text: String) -> String {
        var redacted = text
        for secret in secrets {
            redacted = redacted.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        return redactHighEntropy(in: redacted)
    }

    func redact(output: [String: String]) -> [String: String] {
        output.mapValues { redact($0) }
    }

    private func redactHighEntropy(in text: String) -> String {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }
        var redacted = text
        for token in tokens {
            guard token.count >= 24 else { continue }
            if isHighEntropy(token) || isLikelyEncoded(token) || isLeetspeakLike(token) {
                redacted = redacted.replacingOccurrences(of: token, with: "[REDACTED]")
            }
        }
        return redacted
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            tokens.append(token)
            return true
        }
        return tokens
    }

    private func isHighEntropy(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }
        let entropy = shannonEntropy(trimmed)
        return entropy >= 3.7
    }

    private func isLikelyEncoded(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let isBase64Like = trimmed.unicodeScalars.allSatisfy { base64Chars.contains($0) }
        let isHexLike = trimmed.unicodeScalars.allSatisfy { hexChars.contains($0) }
        return (isBase64Like && trimmed.count >= 32) || (isHexLike && trimmed.count >= 32)
    }

    private func isLeetspeakLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }
        let digits = trimmed.filter { $0.isNumber }.count
        let letters = trimmed.filter { $0.isLetter }.count
        return digits >= 6 && letters >= 6
    }

    private func shannonEntropy(_ value: String) -> Double {
        var counts: [Character: Int] = [:]
        for char in value {
            counts[char, default: 0] += 1
        }
        let length = Double(value.count)
        return counts.values.reduce(0.0) { partial, count in
            let p = Double(count) / length
            return partial - (p * log2(p))
        }
    }
}
