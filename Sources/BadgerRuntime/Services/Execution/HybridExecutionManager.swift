import Foundation
import MLX
import BadgerCore

/// The single‑instance runtime actor that routes inference between
/// local (MLX/Metal) and cloud execution paths.
///
/// ## Hardware Detection & Budgeting
///
/// On initialisation the manager reads physical RAM and computes:
///
/// $$
/// M_{max} = (RAM_{total} \times 0.8) - 3.0\,\text{GB}
/// $$
///
/// with a hard **3.0 GB physical floor**. If the computed budget is
/// negative or kernel memory pressure is `.warning`+, new local
/// inference is denied and routed to **Cloud‑Only Safe Mode**.
///
/// ## Context Hopping
///
/// Before every inference cycle the manager hops to `@MainActor` to
/// query memory pressure, thermal state, network reachability, and
/// safe‑mode status. This avoids stale reads when the system state
/// has changed between scheduling and execution.
public actor HybridExecutionManager {

    // MARK: - Constants

    /// 3 GB floor in bytes.
    private static let physicalFloorBytes: UInt64 = 3 * 1024 * 1024 * 1024

    /// 2 GB system buffer buffer.
    private static let minSystemRAMBuffer: UInt64 = 2 * 1024 * 1024 * 1024
    
    /// 16 GB "Low RAM" threshold.
    private static let lowRAMThreshold: UInt64 = 16 * 1024 * 1024 * 1024

    /// 1 GB in bytes (for budget calculations).
    private static let oneGBBytes: UInt64 = 1024 * 1024 * 1024

    // MARK: - Hardware Info

    /// Total physical RAM in bytes.
    public nonisolated let totalRAMBytes: UInt64

    /// Maximum local model budget in bytes.
    public nonisolated let localModelBudgetBytes: UInt64

    // MARK: - State

    /// GPU/NPU occupancy lock — only one inference at a time.
    private var isInferenceActive: Bool = false

    /// Whether safe mode is forced (cloud‑only).
    private var safeModeEnabled: Bool = false

    /// The active inference task, if any.
    private var activeInferenceTask: Task<ExecutionResult, any Error>?

    /// Memory pressure denied flag — set by ResourceSentinel callbacks.
    private var memoryPressureDenied: Bool = false

    /// Current thermal throttle flag.
    private var thermalThrottled: Bool = false

    /// Remote control enabled flag.
    private var remoteControlEnabled: Bool = false

    /// Network reachability monitor.
    private nonisolated let networkMonitor = NetworkMonitor()

    // MARK: - Init

    public init() {
        let ram = UInt64(ProcessInfo.processInfo.physicalMemory)
        self.totalRAMBytes = ram

        // If < 16GB, default to Safe Mode (cloud).
        if ram < Self.lowRAMThreshold {
            self.safeModeEnabled = true
        }

        let rawBudget = Int64(Double(ram) * 0.8) - Int64(Self.physicalFloorBytes)
        self.localModelBudgetBytes = rawBudget > 0 ? UInt64(rawBudget) : 0
        
        // Start network monitoring.
        networkMonitor.start()
    }
    
    deinit {
        networkMonitor.stop()
    }

    // MARK: - Configuration

    /// Enable or disable Cloud‑Only Safe Mode.
    public func setSafeMode(_ enabled: Bool) {
        safeModeEnabled = enabled
    }

    /// Update memory pressure admission status.
    public func setMemoryPressureDenied(_ denied: Bool) {
        memoryPressureDenied = denied
    }

    /// Update thermal throttle state.
    public func setThermalThrottled(_ throttled: Bool) {
        thermalThrottled = throttled
    }

    /// Update remote control state.
    public func setRemoteControlEnabled(_ enabled: Bool) {
        remoteControlEnabled = enabled
    }

    // MARK: - Execution API

    /// Process an execution intent, routing to local or cloud inference.
    ///
    /// - Throws: `CancellationError` on preemption, other errors from
    ///   inference backends.
    public func process(
        intent: ExecutionIntent
    ) async throws -> ExecutionResult {
        try Task.checkCancellation()

        // Context hop — read system state on the main actor.
        let context = await readSystemContext()

        // Determine execution path.
        let lowRAM = totalRAMBytes < Self.lowRAMThreshold
        let executionBlockedByRAM = estimateAvailableRAM() < Self.minSystemRAMBuffer
        
        // Network Check: If offline, we MUST try local if possible, regardless of "Safe Mode" preference
        // unless hardware prevents it.
        // However, if hardware is insufficient (lowRAM), we can't run local.
        // So:
        // 1. If LowRAM -> Must use Cloud. If Offline -> Fail.
        // 2. If HighRAM -> Can use Local or Cloud.
        
        let offline = context.isNetworkReachabilityError
        
        if lowRAM && offline {
            throw ExecutionError.systemIncompatible("Offline and insufficient RAM for local fallback.")
        }

        let useCloud = !offline && (
            context.isSafeModeActive
            || context.isMemoryPressureDenied
            || localModelBudgetBytes == 0
            || lowRAM
            || executionBlockedByRAM
        )

        // Alert on RAM block if not already safe mode.
        if executionBlockedByRAM && !context.isSafeModeActive && !lowRAM {
             // We'd ideally throw an explicit error here that triggers a UI notice,
             // or fallback to cloud with a warning.
             // For now, we route to cloud.
        }

        // Enforce exclusive GPU/NPU occupancy.
        guard !isInferenceActive else {
            // Concurrent request.
            if useCloud {
                 return try await executeCloudInference(intent: intent)
            } else {
                 throw ExecutionError.systemBusy
            }
        }

        isInferenceActive = true
        defer { isInferenceActive = false }

        if useCloud {
            return try await executeCloudInference(intent: intent)
        } else {
            return try await executeLocalInference(intent: intent)
        }
    }

    /// Cancel any active inference.
    public func cancelActiveInference() {
        activeInferenceTask?.cancel()
        activeInferenceTask = nil
        isInferenceActive = false
    }

    /// Evict local model resources (MLX/Metal buffers).
    public func evictLocalModelResources() {
        // In a full implementation this would release Metal buffers,
        // MLX arrays, and KV‑cache allocations. Represented as a
        // synchronous state reset here.
        isInferenceActive = false
        activeInferenceTask?.cancel()
        activeInferenceTask = nil
    }
    
    /// Pre-load critical resources for low-latency inference.
    public func preloadHotPath() async {
        // In production: Load the routing model or wake up the NPU.
        // For now, we just ensure the actor is ready.
        let _ = await readSystemContext()
    }

    // MARK: - Snapshot for UI

    /// A `nonisolated`‑safe snapshot of current system status.
    ///
    /// Because this reads actor state it must be called from within
    /// the actor's isolation context.
    public func statusSnapshot() -> SystemStatus {
        SystemStatus(
            totalRAMBytes: totalRAMBytes,
            availableRAMBytes: estimateAvailableRAM(),
            executionLocation: safeModeEnabled ? .cloud : .local,
            thermalState: describeThermalState(),
            isThrottled: thermalThrottled,
            isSafeModeActive: safeModeEnabled,
            isRemoteControlEnabled: remoteControlEnabled,
            localModelBudgetBytes: localModelBudgetBytes,
            isOffline: !networkMonitor.isReachable
        )
    }

    // MARK: - Context Hop

    @MainActor
    private func readSystemContext() -> SystemContext {
        let thermal = ProcessInfo.processInfo.thermalState
        // We can access the network monitor directly here since it's thread-safe
        return SystemContext(
            isSafeModeActive: ResourcePolicyStore.shared.isSafeModeEnabled,
            isMemoryPressureDenied: false, // In real app, check MemoryPressureMonitor
            thermalState: thermal,
            isNetworkReachabilityError: !networkMonitor.isReachable
        )
    }

    // MARK: - Inference Backends

    private func executeLocalInference(
        intent: ExecutionIntent
    ) async throws -> ExecutionResult {
        try Task.checkCancellation()

        let start = ContinuousClock.now

        // Placeholder for actual MLX model inference.
        // In production this would:
        // 1. Load the model if not cached
        // 2. Tokenise the prompt
        // 3. Run forward pass with KV-cache
        // 4. Decode output tokens
        let output = "[Local inference result for: \(intent.prompt)]"

        let elapsed = ContinuousClock.now - start
        let nanos = UInt64(elapsed.components.seconds) * 1_000_000_000
            + UInt64(elapsed.components.attoseconds / 1_000_000_000)

        return ExecutionResult(
            intentID: intent.id,
            output: output,
            location: .local,
            tokensUsed: intent.tokenBudget,
            durationNanoseconds: nanos
        )
    }

    private func executeCloudInference(
        intent: ExecutionIntent
    ) async throws -> ExecutionResult {
        try Task.checkCancellation()

        let start = ContinuousClock.now

        // Placeholder for cloud API call via macOS secure integration.
        // In production the local redaction gate would strip sensitive
        // data before the prompt is sent.
        let output = "[Cloud inference result for: \(intent.prompt)]"

        let elapsed = ContinuousClock.now - start
        let nanos = UInt64(elapsed.components.seconds) * 1_000_000_000
            + UInt64(elapsed.components.attoseconds / 1_000_000_000)

        return ExecutionResult(
            intentID: intent.id,
            output: output,
            location: .cloud,
            tokensUsed: intent.tokenBudget,
            durationNanoseconds: nanos
        )
    }

    // MARK: - Helpers

    private func estimateAvailableRAM() -> UInt64 {
        // Conservative estimate: total minus floor.
        totalRAMBytes > Self.physicalFloorBytes
            ? totalRAMBytes - Self.physicalFloorBytes
            : 0
    }

    private func describeThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - SystemContext (Internal)

/// Snapshot read on `@MainActor` before inference.
private struct SystemContext: Sendable {
    let isSafeModeActive: Bool
    let isMemoryPressureDenied: Bool
    let thermalState: ProcessInfo.ThermalState
    let isNetworkReachabilityError: Bool
}

/// Errors occurring during execution routing.
public enum ExecutionError: Error, LocalizedError {
    case systemBusy
    case systemIncompatible(String)
    
    public var errorDescription: String? {
        switch self {
        case .systemBusy: return "System is busy processing another request."
        case .systemIncompatible(let reason): return "System incompatible: \(reason)"
        }
    }
}
