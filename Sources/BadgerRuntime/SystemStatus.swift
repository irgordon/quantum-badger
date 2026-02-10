import Foundation

/// Snapshot of system health for UI consumption.
///
/// Published as a `nonisolated` copy from ``HybridExecutionManager``
/// so SwiftUI views can read it without crossing actor boundaries.
public struct SystemStatus: Sendable, Codable, Equatable, Hashable {
    /// Total physical RAM in bytes.
    public let totalRAMBytes: UInt64

    /// Available RAM estimate in bytes.
    public let availableRAMBytes: UInt64

    /// Current execution location.
    public let executionLocation: ExecutionLocation

    /// Thermal state description.
    public let thermalState: String

    /// Whether the system is thermally throttled.
    public let isThrottled: Bool

    /// Whether Safe Mode (cloud‑only) is active.
    public let isSafeModeActive: Bool

    /// Whether remote command handling is enabled.
    public let isRemoteControlEnabled: Bool

    /// Local model budget in bytes.
    public let localModelBudgetBytes: UInt64

    /// Current conversation context size in tokens.
    public let conversationTokenCount: UInt64

    /// Whether older conversation entries have been compacted.
    public let isConversationCompacted: Bool

    /// Name of the currently active model (e.g. "GPT‑4.1‑mini").
    public let activeModelName: String

    /// Where the active model executes.
    public let activeModelLocation: ExecutionLocation
    
    /// Whether the system is currently offline.
    public let isOffline: Bool

    public init(
        totalRAMBytes: UInt64,
        availableRAMBytes: UInt64,
        executionLocation: ExecutionLocation,
        thermalState: String,
        isThrottled: Bool,
        isSafeModeActive: Bool,
        isRemoteControlEnabled: Bool,
        localModelBudgetBytes: UInt64,
        conversationTokenCount: UInt64 = 0,
        isConversationCompacted: Bool = false,
        activeModelName: String = "Automatic",
        activeModelLocation: ExecutionLocation = .cloud,
        isOffline: Bool = false
    ) {
        self.totalRAMBytes = totalRAMBytes
        self.availableRAMBytes = availableRAMBytes
        self.executionLocation = executionLocation
        self.thermalState = thermalState
        self.isThrottled = isThrottled
        self.isSafeModeActive = isSafeModeActive
        self.isRemoteControlEnabled = isRemoteControlEnabled
        self.localModelBudgetBytes = localModelBudgetBytes
        self.conversationTokenCount = conversationTokenCount
        self.isConversationCompacted = isConversationCompacted
        self.activeModelName = activeModelName
        self.activeModelLocation = activeModelLocation
        self.isOffline = isOffline
    }
}
