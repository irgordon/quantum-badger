import Foundation

/// Manages the lifecycle of the currently loaded local model.
///
/// The loader enforces that only one model is loaded at a time,
/// reports progress, and always supports cancellation. Loading
/// runs entirely off the main thread.
public actor ModelLoader {

    // MARK: - Load State

    /// Observable state for the model loading lifecycle.
    public enum LoadState: Sendable, Equatable {
        case idle
        case loading(fractionComplete: Double)
        case loaded(ModelDescriptor)
        case failed(String)
    }

    // MARK: - State

    /// Current load state — read by the UI via coordinator snapshots.
    public private(set) var state: LoadState = .idle

    /// The currently loaded model descriptor, if any.
    public var loadedModel: ModelDescriptor? {
        if case .loaded(let descriptor) = state { return descriptor }
        return nil
    }

    /// Active load task for cancellation support.
    private var loadTask: Task<Void, any Error>?

    // MARK: - Load

    /// Load a model from disk.
    ///
    /// - Parameters:
    ///   - descriptor: The model to load.
    ///   - url: Path to the model file.
    ///   - availableRAM: Current available RAM for final safety check.
    /// - Throws: ``ModelValidationError`` if the model cannot be safely loaded.
    public func load(
        _ descriptor: ModelDescriptor,
        at url: URL,
        availableRAM: UInt64
    ) async throws {
        // Cancel any existing load.
        loadTask?.cancel()
        loadTask = nil

        // Final RAM check right before loading — conditions may have changed
        // since validation (another app may have launched).
        let safetyBuffer: UInt64 = 2 * 1024 * 1024 * 1024
        if let needed = descriptor.estimatedRAMBytes {
            guard availableRAM > needed + safetyBuffer else {
                let message = "Not enough free memory to safely load \(descriptor.name). Close some apps and try again."
                state = .failed(message)
                throw ModelValidationError.insufficientMemory(
                    needed: needed,
                    available: availableRAM
                )
            }
        }

        state = .loading(fractionComplete: 0)

        // Simulate loading progress (in production, this reads model weights).
        // The key contract: loading is always cancellable.
        loadTask = Task {
            for step in 1...10 {
                try Task.checkCancellation()

                // Simulated progress — real implementation would report from MLX.
                let fraction = Double(step) / 10.0
                state = .loading(fractionComplete: fraction)

                // Yield to allow cancellation and UI updates.
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms per step
            }

            state = .loaded(descriptor)
        }

        do {
            try await loadTask?.value
        } catch is CancellationError {
            state = .idle
            throw ModelValidationError.validationCancelled
        } catch {
            let message = "Could not load \(descriptor.name). The model file may be damaged or incompatible."
            state = .failed(message)
            throw error
        }
    }

    // MARK: - Unload

    /// Unload the current model and free resources.
    public func unload() {
        loadTask?.cancel()
        loadTask = nil
        state = .idle
    }

    // MARK: - Cancel

    /// Cancel any in‑progress load.
    public func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        state = .idle
    }
}
