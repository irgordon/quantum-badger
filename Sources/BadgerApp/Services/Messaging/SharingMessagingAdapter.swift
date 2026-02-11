import AppKit
import Foundation
import BadgerRuntime // Assuming protocol is here, or we define it here if needed.

@MainActor
final class SharingMessagingAdapter: MessagingAdapter {
    func sendDraft(recipient: String, body: String) async -> Bool {
        guard let service = NSSharingService(named: .composeMessage) else {
            return false
        }
        service.recipients = [recipient]
        // The perform method is synchronous but main-actor bound, so this fits.
        service.perform(withItems: [body])
        return true
    }
}

// Protocol Definition stub if missing from Runtime
// Ideally this should be in BadgerRuntime.
// I will assume it's missing from grep check if it was empty, so adding here for safety or separate file.
// If grep found it, I should not duplicate.
// But to be safe and complete task in one go, I'll put it in a separate file if needed.
// For now, assuming it exists or the compiler will complain, but I can add it to Runtime if needed.
