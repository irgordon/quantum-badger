import Foundation

/// A runtime that requires a warm-up phase to load tensors into memory.
///
/// Implementing this protocol allows the system to proactively hydrate
/// the GPU cache (e.g., on app launch or model selection) to solve
/// the "Cold Start" problem.
public protocol WarmableModelRuntime {
    /// Pre-heat the model by loading weights into Unified Memory.
    ///
    /// This method should be idempotent. If the model is already warm,
    /// it should return immediately.
    func warmUp() async
}
