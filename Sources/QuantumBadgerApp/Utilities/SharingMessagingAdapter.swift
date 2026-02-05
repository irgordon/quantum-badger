import AppKit
import Foundation
import QuantumBadgerRuntime

@MainActor
final class SharingMessagingAdapter: MessagingAdapter {
    func sendDraft(recipient: String, body: String) async -> Bool {
        guard let service = NSSharingService(named: .composeMessage) else {
            return false
        }
        service.recipients = [recipient]
        service.perform(withItems: [body])
        return true
    }
}
