import Foundation

/// Pure‑Swift similarity utilities for Semantic Delta Analysis.
public struct SimilarityUtils: Sendable {

    private init() {}

    // MARK: - Cosine Similarity

    /// Compute cosine similarity between two text strings using
    /// normalised bag‑of‑words term‑frequency vectors.
    ///
    /// - Note: Optimized for short text segments (intents).
    /// - Returns: A value in `[0, 1]` where 1 means identical term distributions.
    public static func cosineSimilarity(_ a: String, _ b: String) -> Double {
        let vecA = termFrequencyVector(a)
        let vecB = termFrequencyVector(b)

        guard !vecA.isEmpty, !vecB.isEmpty else { return 0.0 }

        // 1. Compute Dot Product (Sparse)
        // Iterate over the smaller vector for efficiency
        let (small, large) = vecA.count < vecB.count ? (vecA, vecB) : (vecB, vecA)
        
        var dotProduct: Double = 0.0
        for (term, freqA) in small {
            if let freqB = large[term] {
                dotProduct += freqA * freqB
            }
        }

        // 2. Compute Magnitudes
        // ||A|| = sqrt(sum(a_i^2))
        let magA = vecA.values.reduce(0) { $0 + ($1 * $1) }.squareRoot()
        let magB = vecB.values.reduce(0) { $0 + ($1 * $1) }.squareRoot()

        let denominator = magA * magB
        guard denominator > 0 else { return 0.0 }
        
        return dotProduct / denominator
    }

    // MARK: - Token Persistence

    /// Compute token persistence ratio between two texts.
    public static func tokenPersistence(
        newIntent: String,
        currentPlanIntent: String
    ) -> Double {
        let currentTokens = significantTokens(currentPlanIntent)
        guard !currentTokens.isEmpty else { return 0.0 }

        // Use Set for O(1) lookup
        let newTokensSet = Set(significantTokens(newIntent))
        
        // Count how many original tokens survived
        let preservedCount = currentTokens.filter { newTokensSet.contains($0) }.count
        
        return Double(preservedCount) / Double(currentTokens.count)
    }

    // MARK: - Linguistic Modifier Detection

    private static let refinementModifiers: Set<String> = [
        "actually", "instead", "also", "additionally", "moreover",
        "furthermore", "plus", "besides", "alternatively"
    ]

    public static func containsRefinementModifier(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Simple tokenization is sufficient for modifier checks
        let words = lower.split(whereSeparator: { !$0.isLetter })
        
        // Fast exit: Check intersection without creating full Set if possible,
        // though Set creation is fine for small inputs.
        for word in words {
            if refinementModifiers.contains(String(word)) {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    private static func termFrequencyVector(_ text: String) -> [String: Double] {
        var freq: [String: Double] = [:]
        
        // Combined normalization and tokenization
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { token, _, _, _ in
            guard let token = token?.lowercased() else { return }
            // Filter noise (numbers/punctuation usually handled by .byWords, but explicit check implies intent)
            // Using .byWords is safer for Unicode than isLetter check.
            freq[token, default: 0] += 1
        }
        
        return freq
    }

    private static func significantTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        let minLength = 3
        
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { token, _, _, _ in
            guard let token = token?.lowercased(), token.count >= minLength else { return }
            tokens.append(token)
        }
        return tokens
    }
}
