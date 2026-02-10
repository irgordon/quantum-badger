import Foundation

/// Channel through which a remote command was received.
@frozen
public enum RemoteChannel: String, Sendable, Codable, Equatable, Hashable {
    case iMessage
    case whatsApp
}
