
import Foundation

@MainActor
public protocol MessagingAdapter {
    func sendDraft(recipient: String, body: String) async -> Bool
}
