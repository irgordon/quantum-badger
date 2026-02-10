import Foundation

/// Semantic Delta Analysis (SDA) engine for intent arbitration.
///
/// `IntentArbitrator` decides whether a new user intent should **refine**
/// the active plan in‑situ or **preempt** it entirely.
///
/// ## Decision Gates
///
/// The evaluation proceeds through three sequential gates:
///
/// ### Gate 1 — Cosine Similarity (θ)
///
/// $$
/// \theta = \frac{\vec{A} \cdot \vec{B}}{|\vec{A}| \, |\vec{B}|}
/// $$
///
/// where **A** and **B** are bag‑of‑words TF vectors of the new intent and
/// current plan source intent, respectively.
///
/// - If  $\theta < 0.4$  → **Preempt & Archive**.
///
/// ### Gate 2 — Entity Persistence (ε)
///
/// $$
/// \varepsilon = \frac{|T_{current} \cap T_{new}|}{|T_{current}|}
/// $$
///
/// where $T$ is the set of significant tokens (length ≥ 3).
///
/// - If  $\varepsilon \geq 0.7$  → **Refine In‑Situ**.
///
/// ### Gate 3 — Linguistic Modifiers
///
/// Detect refinement signal words such as *"actually"*, *"instead"*, *"also"*.
///
/// - If modifiers are present  → **Refine**.
/// - Otherwise                → **Preempt**.
public struct IntentArbitrator: Sendable {

    /// The action the system must take after evaluating a new intent
    /// against the current plan.
    @frozen
    public enum IntentAction: String, Sendable, Codable, Equatable, Hashable {
        /// Modify the current plan in‑place to absorb the new intent.
        case refine
        /// Archive the current plan and start a fresh reasoning loop.
        case preempt
    }

    /// Similarity threshold below which the intent is considered
    /// semantically divergent enough to warrant full preemption.
    public let preemptionThreshold: Double

    /// Entity persistence ratio at or above which the intent is
    /// considered a refinement of the existing plan.
    public let refinementThreshold: Double

    public init(
        preemptionThreshold: Double = 0.4,
        refinementThreshold: Double = 0.7
    ) {
        self.preemptionThreshold = preemptionThreshold
        self.refinementThreshold = refinementThreshold
    }

    /// Evaluate a new user intent against the active plan.
    ///
    /// - Parameters:
    ///   - newIntent: The raw text of the user's new request.
    ///   - currentPlan: The currently active plan.
    /// - Returns: The recommended ``IntentAction``.
    public func evaluate(
        newIntent: String,
        currentPlan: Plan
    ) async throws -> IntentAction {
        // Allow cooperative cancellation.
        try Task.checkCancellation()

        // Gate 1: Cosine Similarity
        let similarity = SimilarityUtils.cosineSimilarity(
            newIntent,
            currentPlan.sourceIntent
        )
        if similarity < preemptionThreshold {
            return .preempt
        }

        // Gate 2: Entity Persistence
        let persistence = SimilarityUtils.entityPersistence(
            newIntent: newIntent,
            currentPlanIntent: currentPlan.sourceIntent
        )
        if persistence >= refinementThreshold {
            return .refine
        }

        // Gate 3: Linguistic Modifiers
        if SimilarityUtils.containsRefinementModifier(newIntent) {
            return .refine
        }

        // Default: the intent is sufficiently divergent.
        return .preempt
    }
}
