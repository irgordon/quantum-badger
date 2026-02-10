import Foundation
import CryptoKit

public enum ModelEngineType: String, Codable, CaseIterable, Identifiable, Sendable {
    case mlx
    case gguf
    case coreML
    case cloud
    case unknown

    public var id: String { rawValue }
}

public enum CloudTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case privateCloud
    case publicCloud

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .privateCloud: return "Private Cloud Compute"
        case .publicCloud: return "Public Cloud"
        }
    }
}

public struct LocalModel: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var bookmarkData: Data?
    public var hash: String
    public var engine: ModelEngineType
    public var contextTokens: Int
    public var temperatureCap: Double
    public var maxTokens: Int
    public var cpuThreads: Int
    public var gpuLayers: Int
    public var expectedLatencySeconds: Double
    public var isActive: Bool
    public var isCloud: Bool
    public var cloudTier: CloudTier
    public var maxPromptChars: Int
    public var redactSensitivePrompts: Bool
    public var provenance: String
    public var addedAt: Date

    public static func inferEngine(from path: String, isCloud: Bool) -> ModelEngineType {
        if isCloud { return .cloud }
        let lower = path.lowercased()
        if lower.hasSuffix(".gguf") { return .gguf }
        if lower.hasSuffix(".mlx") { return .mlx }
        if lower.hasSuffix(".mlmodelc") || lower.hasSuffix(".mlmodel") { return .coreML }
        return .unknown
    }

    public init(
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
        cloudTier: CloudTier = .privateCloud,
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
        self.cloudTier = cloudTier
        self.maxPromptChars = maxPromptChars
        self.redactSensitivePrompts = redactSensitivePrompts
        self.provenance = provenance
        self.addedAt = addedAt
    }

    public func verifyIntegrity(at url: URL) -> Bool? {
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Streaming SHA256 calculation to avoid loading large models into RAM
        guard let inputStream = InputStream(url: url) else { return false }
        inputStream.open()
        defer { inputStream.close() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while inputStream.hasBytesAvailable {
            let read = inputStream.read(buffer, maxLength: bufferSize)
            if read < 0 { return false } // Read error
            if read == 0 { break } // EOF
            let data = UnsafeRawBufferPointer(start: buffer, count: read)
            hasher.update(bufferPointer: data)
        }
        
        let digest = hasher.finalize()
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        return computed.lowercased() == trimmed.lowercased()
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
        case cloudTier
        case maxPromptChars
        case redactSensitivePrompts
        case provenance
        case addedAt
    }

    public init(from decoder: Decoder) throws {
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
        cloudTier = try container.decodeIfPresent(CloudTier.self, forKey: .cloudTier) ?? .privateCloud
        maxPromptChars = try container.decodeIfPresent(Int.self, forKey: .maxPromptChars) ?? 2000
        redactSensitivePrompts = try container.decodeIfPresent(Bool.self, forKey: .redactSensitivePrompts) ?? true
        provenance = try container.decode(String.self, forKey: .provenance)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

public struct ModelLimits: Codable, Sendable {
    public var maxContextTokens: Int
    public var maxTemperature: Double
    public var maxTokens: Int
    
    public init(maxContextTokens: Int, maxTemperature: Double, maxTokens: Int) {
        self.maxContextTokens = maxContextTokens
        self.maxTemperature = maxTemperature
        self.maxTokens = maxTokens
    }
}
