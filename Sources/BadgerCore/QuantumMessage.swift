import Foundation

/// The kind of message content.
public enum QuantumMessageKind: String, Codable, Sendable, Equatable, Hashable {
    case text
    case localSearchResults
    case webScoutResults
    case toolNotice
    case toolError
}

/// The source of the message.
public enum QuantumMessageSource: String, Codable, Sendable, Equatable, Hashable {
    case user
    case tool
    case system
    case assistant // Retained for compatibility with existing UI/Memory logic
    case summary // Retained for compaction logic
}

/// The central data contract for the Quantum Badger Runtime.
public struct QuantumMessage: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let kind: QuantumMessageKind
    public let source: QuantumMessageSource
    public let toolName: String?
    public let content: String
    public let createdAt: Date
    
    // MemoryController Versioning (Retained)
    public let version: UInt64
    
    public let isVerified: Bool
    public let signature: String?
    public let localMatches: [LocalSearchMatch]?
    public let webCards: [WebScoutResult]?
    public let appEntityIds: [String]?

    public init(
        id: UUID = UUID(),
        kind: QuantumMessageKind = .text,
        source: QuantumMessageSource,
        toolName: String? = nil,
        content: String,
        createdAt: Date = Date(),
        version: UInt64 = 0,
        isVerified: Bool = false,
        signature: String? = nil,
        localMatches: [LocalSearchMatch]? = nil,
        webCards: [WebScoutResult]? = nil,
        appEntityIds: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.toolName = toolName
        self.content = content
        self.createdAt = createdAt
        self.version = version
        self.isVerified = isVerified
        self.signature = signature
        self.localMatches = localMatches
        self.webCards = webCards
        self.appEntityIds = appEntityIds
    }
}

// MARK: - Integration Helpers

public extension QuantumMessage {
    // Computed property for UI compat if needed, or update UI to use source/kind.
    // We will update UI.
    
    func integrityStatus() -> MessageIntegrityStatus {
        guard let signature = signature, let data = content.data(using: .utf8) else {
            return .unverified
        }
        return InboundIdentityValidator.shared.integrityStatus(for: data, signature: Data(hexString: signature))
    }
}

/// A local file match.
public struct LocalSearchMatch: Sendable, Codable, Equatable, Hashable {
    public let path: String
    public let snippet: String?
    public let score: Double
    
    public init(path: String, snippet: String?, score: Double) {
        self.path = path
        self.snippet = snippet
        self.score = score
    }
}

/// A web search result card.
public struct WebScoutResult: Sendable, Codable, Equatable, Hashable {
    public let url: String
    public let title: String
    public let snippet: String
    
    public init(url: String, title: String, snippet: String) {
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

// MARK: - Cryptographic Visibility

public enum MessageIntegrityStatus {
    case verified
    case unverified
    case identityUnavailable
}

public extension MessageIntegrityStatus {
    var label: String {
        switch self {
        case .verified:
            return "VERIFIED"
        case .unverified:
            return "UNVERIFIED"
        case .identityUnavailable:
            return "IDENTITY UNAVAILABLE"
        }
    }
}

public extension QuantumMessage {
    /// Verify the cryptographic integrity of this message.
    ///
    /// - Note: This computes the hash and verifies the signature on-demand.
    ///   For high-performance scrolling, results should be cached by the UI layer.
    func integrityStatus() -> MessageIntegrityStatus {
        guard let data = content.data(using: .utf8) else {
            return .unverified
        }
        
        // If system messages don't have signatures yet, we might want to skip verification or
        // treat them as trusted-by-context. For strict "Sovereignty", everything should be signed.
        // If signature is missing, InboundIdentityValidator returns .unverified.
        return InboundIdentityValidator.shared.integrityStatus(for: data, signature: signature)
    }
}
