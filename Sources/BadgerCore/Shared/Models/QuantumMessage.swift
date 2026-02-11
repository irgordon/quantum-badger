import Foundation

// MARK: - Enums

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
    case assistant
    case summary
}

// MARK: - Data Contract

/// The central data contract for the Quantum Badger Runtime.
public struct QuantumMessage: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let kind: QuantumMessageKind
    public let source: QuantumMessageSource
    public let toolName: String?
    public let content: String
    public let createdAt: Date
    
    /// MemoryController Versioning
    public let version: UInt64
    
    /// Cryptographic Proof
    public let isVerified: Bool
    public let signature: String?
    
    /// Payload Attachments
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

// MARK: - Attachments

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

// MARK: - Integrity Logic

public enum MessageIntegrityStatus: Sendable {
    case verified
    case unverified
    case identityUnavailable
    
    public var label: String {
        switch self {
        case .verified: return "VERIFIED"
        case .unverified: return "UNVERIFIED"
        case .identityUnavailable: return "IDENTITY UNAVAILABLE"
        }
    }
}

// Note: Ensure InboundIdentityValidator is available in the module where this is used.
public extension QuantumMessage {
    /// Verify the cryptographic integrity of this message.
    func integrityStatus() -> MessageIntegrityStatus {
        guard let signature = signature,
              !signature.isEmpty,
              let data = content.data(using: .utf8) else {
            return .unverified
        }
        
        // Decoupling Note: If InboundIdentityValidator is in a different module,
        // this logic should be moved to a ViewHelper or ViewModel.
        // Assuming 'BadgerCore' contains both for now.
        return InboundIdentityValidator.shared.integrityStatus(for: data, signature: signature)
    }
}
