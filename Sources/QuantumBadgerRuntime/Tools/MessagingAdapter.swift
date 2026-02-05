import Foundation

protocol MessagingAdapter {
    func sendDraft(recipient: String, body: String) async -> Bool
}

struct DisabledMessagingAdapter: MessagingAdapter {
    func sendDraft(recipient: String, body: String) async -> Bool {
        false
    }
}
