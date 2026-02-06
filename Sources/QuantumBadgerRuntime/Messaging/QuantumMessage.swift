import Foundation

enum QuantumMessageKind: String, Codable {
    case text
    case localSearchResults
    case webScoutResults
    case toolNotice
    case toolError
}

enum QuantumMessageSource: String, Codable {
    case user
    case tool
    case system
}

struct QuantumMessage: Identifiable, Codable {
    let id: UUID
    let kind: QuantumMessageKind
    let source: QuantumMessageSource
    let toolName: String?
    let content: String
    let createdAt: Date
    let isVerified: Bool
    let localMatches: [LocalSearchMatch]?
    let webCards: [WebScoutResult]?

    init(
        id: UUID = UUID(),
        kind: QuantumMessageKind,
        source: QuantumMessageSource,
        toolName: String?,
        content: String,
        createdAt: Date,
        isVerified: Bool = false,
        localMatches: [LocalSearchMatch]? = nil,
        webCards: [WebScoutResult]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.toolName = toolName
        self.content = content
        self.createdAt = createdAt
        self.isVerified = isVerified
        self.localMatches = localMatches
        self.webCards = webCards
    }
}
