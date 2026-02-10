import Foundation

/// A command received from a remote channel.
public struct RemoteCommand: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Source channel.
    public let channel: RemoteChannel

    /// Raw text as received.
    public let rawText: String

    /// Whether the sender identity has been authenticated.
    public let isAuthenticated: Bool

    /// When the command was received.
    public let receivedAt: Date

    /// The sender identifier (phone number, Apple ID, etc.).
    public let senderID: String

    public init(
        id: UUID = UUID(),
        channel: RemoteChannel,
        rawText: String,
        isAuthenticated: Bool,
        receivedAt: Date = Date(),
        senderID: String
    ) {
        self.id = id
        self.channel = channel
        self.rawText = rawText
        self.isAuthenticated = isAuthenticated
        self.receivedAt = receivedAt
        self.senderID = senderID
    }
}
