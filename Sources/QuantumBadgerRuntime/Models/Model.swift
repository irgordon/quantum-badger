import Foundation

enum ModelEngineType: String, Codable, CaseIterable, Identifiable {
    case mlx
    case gguf
    case coreML
    case cloud
    case unknown

    var id: String { rawValue }
}

struct LocalModel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?
    var hash: String
    var engine: ModelEngineType
    var contextTokens: Int
    var temperatureCap: Double
    var maxTokens: Int
    var cpuThreads: Int
    var gpuLayers: Int
    var expectedLatencySeconds: Double
    var isActive: Bool
    var isCloud: Bool
    var maxPromptChars: Int
    var redactSensitivePrompts: Bool
    var provenance: String
    var addedAt: Date

    static func inferEngine(from path: String, isCloud: Bool) -> ModelEngineType {
        if isCloud { return .cloud }
        let lower = path.lowercased()
        if lower.hasSuffix(".gguf") { return .gguf }
        if lower.hasSuffix(".mlx") { return .mlx }
        if lower.hasSuffix(".mlmodelc") || lower.hasSuffix(".mlmodel") { return .coreML }
        return .unknown
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmarkData: Data? = nil,
        hash: String,
        engine: ModelEngineType = .unknown,
        contextTokens: Int,
        temperatureCap: Double,
        maxTokens: Int,
        cpuThreads: Int,
        gpuLayers: Int,
        expectedLatencySeconds: Double = 12,
        isActive: Bool = true,
        isCloud: Bool = false,
        maxPromptChars: Int = 2000,
        redactSensitivePrompts: Bool = true,
        provenance: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.hash = hash
        self.engine = engine
        self.contextTokens = contextTokens
        self.temperatureCap = temperatureCap
        self.maxTokens = maxTokens
        self.cpuThreads = cpuThreads
        self.gpuLayers = gpuLayers
        self.expectedLatencySeconds = expectedLatencySeconds
        self.isActive = isActive
        self.isCloud = isCloud
        self.maxPromptChars = maxPromptChars
        self.redactSensitivePrompts = redactSensitivePrompts
        self.provenance = provenance
        self.addedAt = addedAt
    }

    func verifyIntegrity(at url: URL) -> Bool? {
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: url) else { return false }
        let computed = Hashing.sha256(data).lowercased()
        return computed == trimmed.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case bookmarkData
        case hash
        case engine
        case contextTokens
        case temperatureCap
        case maxTokens
        case cpuThreads
        case gpuLayers
        case expectedLatencySeconds
        case isActive
        case isCloud
        case maxPromptChars
        case redactSensitivePrompts
        case provenance
        case addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        hash = try container.decodeIfPresent(String.self, forKey: .hash) ?? ""
        engine = try container.decodeIfPresent(ModelEngineType.self, forKey: .engine) ?? .unknown
        contextTokens = try container.decode(Int.self, forKey: .contextTokens)
        temperatureCap = try container.decode(Double.self, forKey: .temperatureCap)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        cpuThreads = try container.decode(Int.self, forKey: .cpuThreads)
        gpuLayers = try container.decode(Int.self, forKey: .gpuLayers)
        expectedLatencySeconds = try container.decodeIfPresent(Double.self, forKey: .expectedLatencySeconds) ?? 10
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isCloud = try container.decodeIfPresent(Bool.self, forKey: .isCloud) ?? false
        maxPromptChars = try container.decodeIfPresent(Int.self, forKey: .maxPromptChars) ?? 2000
        redactSensitivePrompts = try container.decodeIfPresent(Bool.self, forKey: .redactSensitivePrompts) ?? true
        provenance = try container.decode(String.self, forKey: .provenance)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

struct ModelLimits: Codable {
    var maxContextTokens: Int
    var maxTemperature: Double
    var maxTokens: Int
}
