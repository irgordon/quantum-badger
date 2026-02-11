import Foundation

// MARK: - Capability Tier

/// Human‑readable capability tier for model selection UI.
@frozen
public enum CapabilityTier: String, Sendable, Codable, CaseIterable, Hashable {
    case fast
    case balanced
    case deepReasoning

    /// Plain‑language label shown in Settings.
    public var displayName: String {
        switch self {
        case .fast:           return "Fast"
        case .balanced:       return "Balanced"
        case .deepReasoning:  return "Deep Reasoning"
        }
    }

    /// One‑sentence explanation suitable for a caption label.
    public var tradeoffSummary: String {
        switch self {
        case .fast:
            return "Quickest responses with lower depth. Best for simple tasks."
        case .balanced:
            return "Good balance of speed and reasoning quality."
        case .deepReasoning:
            return "Most capable reasoning at the cost of higher latency and resource use."
        }
    }
}

// MARK: - Model Descriptor

/// Unified identity for any model — cloud or local, bundled or user‑supplied.
///
/// `ModelDescriptor` is a value type designed for direct use in SwiftUI
/// `List` / `Picker` bindings. It carries enough metadata for the Settings
/// UI to render provider badges, RAM‑fit indicators, and trust labels
/// without touching any actor state.
public struct ModelDescriptor: Sendable, Codable, Identifiable, Hashable {

    // MARK: Identity

    public let id: UUID
    public let name: String
    public let provider: String

    // MARK: Execution

    public let location: ExecutionLocation
    public let capabilityTier: CapabilityTier

    // MARK: Local‑Only Metadata

    /// Parameter count in billions (e.g. `8` for an 8 B model). `nil` for cloud.
    public let parameterBillions: Double?

    /// Quantization label (e.g. `"Q4_K_M"`). `nil` for cloud models.
    public let quantization: String?

    /// Estimated RAM required for inference in bytes. `nil` for cloud.
    public let estimatedRAMBytes: UInt64?

    // MARK: Trust & Provenance

    /// `true` for user‑supplied models added via "Add Local Model…".
    public let isUserSupplied: Bool

    /// `true` when the model comes from a trusted, verified source.
    public let isVerified: Bool

    /// Plain‑language description shown under the model name.
    public let tradeoffDescription: String

    // MARK: Init

    public init(
        id: UUID = UUID(),
        name: String,
        provider: String,
        location: ExecutionLocation,
        capabilityTier: CapabilityTier,
        parameterBillions: Double? = nil,
        quantization: String? = nil,
        estimatedRAMBytes: UInt64? = nil,
        isUserSupplied: Bool = false,
        isVerified: Bool = true,
        tradeoffDescription: String
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.location = location
        self.capabilityTier = capabilityTier
        self.parameterBillions = parameterBillions
        self.quantization = quantization
        self.estimatedRAMBytes = estimatedRAMBytes
        self.isUserSupplied = isUserSupplied
        self.isVerified = isVerified
        self.tradeoffDescription = tradeoffDescription
    }

    // MARK: RAM Helpers

    /// Whether this model fits in the given budget, with a 2 GB safety buffer.
    public func fitsInBudget(_ budgetBytes: UInt64) -> Bool {
        guard let needed = estimatedRAMBytes else { return true } // Cloud
        let safetyBuffer: UInt64 = 2 * 1024 * 1024 * 1024
        return needed + safetyBuffer <= budgetBytes
    }

    /// Human‑readable RAM requirement (e.g. "~6.0 GB").
    public var formattedRAM: String {
        guard let bytes = estimatedRAMBytes, bytes > 0 else { return "—" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "~%.1f GB", gb)
    }

    /// Fit label for the settings UI.
    public func fitLabel(budgetBytes: UInt64) -> String {
        guard location == .local else { return "Cloud" }
        return fitsInBudget(budgetBytes)
            ? "Fits on this Mac"
            : "May exceed available memory"
    }
}
