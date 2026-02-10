import Foundation
import Accelerate

/// Pure‑Swift similarity utilities for Semantic Delta Analysis.
///
/// Uses a simple bag‑of‑words term‑frequency vector to avoid external
/// NLP dependencies while remaining deterministic and ``Sendable``.
public struct SimilarityUtils: Sendable {

    private init() {}

    // MARK: - Cosine Similarity

    /// Compute cosine similarity between two text strings using
    /// normalised bag‑of‑words term‑frequency vectors.
    ///
    /// - Returns: A value in `[0, 1]` where 1 means identical term distributions.
    public static func cosineSimilarity(_ a: String, _ b: String) -> Double {
        let vecA = termFrequencyVector(a)
        let vecB = termFrequencyVector(b)

        let allTerms = Set(vecA.keys).union(vecB.keys)
        guard !allTerms.isEmpty else { return 0.0 }

        // Vectorize inputs.
        let sortedTerms = allTerms.sorted()
        var vA = [Double](repeating: 0, count: sortedTerms.count)
        var vB = [Double](repeating: 0, count: sortedTerms.count)

        for (i, term) in sortedTerms.enumerated() {
            vA[i] = vecA[term, default: 0]
            vB[i] = vecB[term, default: 0]
        }

        // vDSP Dot Product
        var dot: Double = 0
        vDSP_dotprD(vA, 1, vB, 1, &dot, vDSP_Length(sortedTerms.count))

        // vDSP Magnitudes (Sum of Squares)
        var magA: Double = 0
        vDSP_svesqD(vA, 1, &magA, vDSP_Length(sortedTerms.count))

        var magB: Double = 0
        vDSP_svesqD(vB, 1, &magB, vDSP_Length(sortedTerms.count))

        let denominator = magA.squareRoot() * magB.squareRoot()
        guard denominator > 0 else { return 0.0 }
        return dot / denominator
    }

    // MARK: - Entity Persistence

    /// Compute entity persistence ratio between two texts.
    ///
    /// Entity persistence measures how many "significant" tokens from the
    /// current plan reappear in the new intent. Tokens shorter than 3
    /// characters are excluded as noise.
    ///
    /// - Returns: A value in `[0, 1]` where 1 means all current entities
    ///   are preserved in the new intent.
    public static func entityPersistence(
        newIntent: String,
        currentPlanIntent: String
    ) -> Double {
        let currentTokens = significantTokens(currentPlanIntent)
        guard !currentTokens.isEmpty else { return 0.0 }

        let newTokens = Set(significantTokens(newIntent))
        let preserved = currentTokens.filter { newTokens.contains($0) }
        return Double(preserved.count) / Double(currentTokens.count)
    }

    // MARK: - Linguistic Modifier Detection

    /// Known refinement signal words.
    ///
    /// When these modifiers appear in a new intent, they indicate the user
    /// wishes to **refine** the current plan rather than replace it.
    public static let refinementModifiers: Set<String> = [
        "actually", "instead", "also", "additionally", "moreover",
        "furthermore", "plus", "besides", "alternatively",
    ]

    /// Check whether the text contains linguistic refinement modifiers.
    public static func containsRefinementModifier(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = Set(
            lower.split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        return !words.isDisjoint(with: refinementModifiers)
    }

    // MARK: - Private Helpers

    private static func termFrequencyVector(
        _ text: String
    ) -> [String: Double] {
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        var freq: [String: Double] = [:]
        for token in tokens {
            freq[token, default: 0] += 1
        }
        return freq
    }

    private static func significantTokens(
        _ text: String
    ) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
    }
}
