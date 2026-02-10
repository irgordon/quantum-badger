import Foundation

/// Static + dynamic registry of available models.
///
/// Cloud and bundled local models are populated at init. User‑supplied
/// custom models are appended after validation and persisted across launches
/// via `@AppStorage`‑compatible JSON encoding.
public actor ModelCatalog {

    // MARK: - Published State

    /// All cloud models — immutable after init.
    public let cloudModels: [ModelDescriptor]

    /// Bundled + user‑added local models.
    public private(set) var localModels: [ModelDescriptor]

    // MARK: - Constants

    private static let oneGB: UInt64 = 1_073_741_824

    // MARK: - Init

    public init() {
        self.cloudModels = Self.defaultCloudModels()
        self.localModels = Self.defaultLocalModels()
    }

    // MARK: - Custom Model Management

    /// Append a validated custom model to the local catalog.
    public func addCustomModel(_ descriptor: ModelDescriptor) {
        localModels.append(descriptor)
    }

    /// Remove a custom model by ID. Bundled models cannot be removed.
    public func removeCustomModel(id: UUID) {
        localModels.removeAll { $0.id == id && $0.isUserSupplied }
    }

    // MARK: - Safe‑Mode Default

    /// The default cloud model for ≤8 GB systems.
    public var safeModeDefault: ModelDescriptor {
        cloudModels.first { $0.name == "GPT‑4.1‑mini" } ?? cloudModels[0]
    }

    // MARK: - Static Catalogs

    private static func defaultCloudModels() -> [ModelDescriptor] {
        [
            ModelDescriptor(
                name: "GPT‑4.1‑mini",
                provider: "OpenAI",
                location: .cloud,
                capabilityTier: .fast,
                tradeoffDescription: "Fastest cloud option. Great for simple requests and low‑latency tasks."
            ),
            ModelDescriptor(
                name: "GPT‑4.1",
                provider: "OpenAI",
                location: .cloud,
                capabilityTier: .balanced,
                tradeoffDescription: "Strong general‑purpose reasoning with moderate latency."
            ),
            ModelDescriptor(
                name: "Sonnet 4",
                provider: "Anthropic",
                location: .cloud,
                capabilityTier: .balanced,
                tradeoffDescription: "Balanced speed and depth from Anthropic's latest family."
            ),
            ModelDescriptor(
                name: "Opus 4",
                provider: "Anthropic",
                location: .cloud,
                capabilityTier: .deepReasoning,
                tradeoffDescription: "Deepest reasoning available. Best for complex analysis and planning."
            ),
            ModelDescriptor(
                name: "Gemini Flash",
                provider: "Google",
                location: .cloud,
                capabilityTier: .fast,
                tradeoffDescription: "Google's fastest model. Optimized for throughput over depth."
            ),
            ModelDescriptor(
                name: "Gemini Pro",
                provider: "Google",
                location: .cloud,
                capabilityTier: .deepReasoning,
                tradeoffDescription: "Google's most capable reasoning model with broad knowledge."
            ),
        ]
    }

    private static func defaultLocalModels() -> [ModelDescriptor] {
        [
            ModelDescriptor(
                name: "Qwen 3 8B",
                provider: "Local",
                location: .local,
                capabilityTier: .balanced,
                parameterBillions: 8,
                quantization: "Q4_K_M",
                estimatedRAMBytes: 6 * oneGB,
                tradeoffDescription: "Strong on‑device model. Requires ~6 GB RAM."
            ),
            ModelDescriptor(
                name: "Qwen 2.5 7B",
                provider: "Local",
                location: .local,
                capabilityTier: .balanced,
                parameterBillions: 7,
                quantization: "Q4_K_M",
                estimatedRAMBytes: 5 * oneGB,
                tradeoffDescription: "Compact local model. Requires ~5 GB RAM."
            ),
        ]
    }
}
