import Foundation
import NaturalLanguage

// MARK: - Dependencies

/// Abstract interface for the math layer to allow easy testing.
public protocol SemanticEngine: Sendable {
    func similarity(between a: String, and b: String) -> Double
    func entityPersistence(new: String, old: String) -> Double
    func hasRefinementModifiers(_ text: String) -> Bool
}

// MARK: - The Implementation

/// Semantic Delta Analysis (SDA) engine for intent arbitration.
///
/// `IntentArbitrator` decides whether a new user intent should **refine**
/// the active plan in‑situ or **preempt** it entirely.
public struct IntentArbitrator: Sendable {
    
    @frozen
    public enum IntentAction: String, Sendable, Codable, Equatable, Hashable {
        /// Modify the current plan in‑place to absorb the new intent.
        case refine
        /// Archive the current plan and start a fresh reasoning loop.
        case preempt
    }

    public let preemptionThreshold: Double
    public let refinementThreshold: Double
    
    /// Dependency injection for the math logic
    private let engine: SemanticEngine

    public init(
        engine: SemanticEngine = DefaultSemanticEngine(),
        preemptionThreshold: Double = 0.6, // Higher default for Embeddings
        refinementThreshold: Double = 0.7
    ) {
        self.engine = engine
        self.preemptionThreshold = preemptionThreshold
        self.refinementThreshold = refinementThreshold
    }

    /// Evaluate a new user intent against the active plan.
    public func evaluate(newIntent: String, currentPlan: Plan) async throws -> IntentAction {
        try Task.checkCancellation()

        let currentIntent = currentPlan.sourceIntent

        // Gate 1: Semantic Embedding Similarity
        // We use embeddings now, so 'synonyms' are handled correctly.
        let theta = engine.similarity(between: newIntent, and: currentIntent)
        
        // If they are totally unrelated topics, preempt immediately.
        if theta < preemptionThreshold {
            return .preempt
        }

        // Gate 2: Entity Persistence (The "Noun" Check)
        // If we are talking about the same specific objects, it's likely a refinement.
        let epsilon = engine.entityPersistence(new: newIntent, old: currentIntent)
        
        if epsilon >= refinementThreshold {
            return .refine
        }

        // Gate 3: Linguistic Modifiers (The "Grammar" Check)
        // Check for "actually", "instead", "no, make it..."
        if engine.hasRefinementModifiers(newIntent) {
            return .refine
        }

        // Fallback:
        // High semantic similarity (passed Gate 1) but low entity overlap (failed Gate 2)
        // and no explicit keywords (failed Gate 3).
        //
        // Example: "Show me weather" -> "Show me stocks"
        // High similarity (both 'Show me'), low persistence (weather != stocks).
        // Conclusion: PREEMPT.
        return .preempt
    }
}

// MARK: - Default Engine (NaturalLanguage)

public struct DefaultSemanticEngine: SemanticEngine {
    
    public init() {}
    
    public func similarity(between a: String, and b: String) -> Double {
        // Use Apple's Sentence Embeddings for high-quality semantic diffing
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return 0.0
        }
        return embedding.distance(between: a, and: b).distanceToSimilarity
    }
    
    public func entityPersistence(new: String, old: String) -> Double {
        // Simple token overlap for significant words (length > 3)
        let tokenizer = NLTokenizer(unit: .word)
        
        func extractTokens(from text: String) -> Set<String> {
            var tokens = Set<String>()
            tokenizer.string = text
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let word = String(text[range]).lowercased()
                if word.count >= 3 { tokens.insert(word) }
                return true
            }
            return tokens
        }
        
        let oldTokens = extractTokens(from: old)
        let newTokens = extractTokens(from: new)
        
        guard !oldTokens.isEmpty else { return 0 }
        
        let intersection = oldTokens.intersection(newTokens)
        return Double(intersection.count) / Double(oldTokens.count)
    }
    
    public func hasRefinementModifiers(_ text: String) -> Bool {
        let modifiers = ["actually", "instead", "change", "add", "remove", "no", "also", "plus"]
        let lower = text.lowercased()
        return modifiers.contains { lower.contains($0) }
    }
}

// Helper to invert NLEmbedding distance to similarity (0...1)
extension Double {
    var distanceToSimilarity: Double {
        return 1.0 - (self / 2.0) // Cosine distance is 0..2
    }
}
