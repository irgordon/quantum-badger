import AppIntents
import AppKit
import Foundation

// MARK: - App Shortcuts

struct MessagingDraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DraftMessageIntent(),
            phrases: [
                "Draft a message with \(.applicationName)",
                "Compose a secure message in \(.applicationName)",
                "Prepare a message using \(.applicationName)"
            ],
            shortTitle: "Draft Secure Message",
            systemImageName: "envelope.badge.shield.half.filled"
        )
    }
}

// MARK: - Draft Message Intent

struct DraftMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft Secure Message"
    static var description = IntentDescription("Prepares a message draft using the system's secure sharing service. Requires user confirmation to send.")
    static var openAppWhenRun: Bool = true // Must be true to launch NSSharingService UI

    @Parameter(title: "Recipient", requestValueDialog: "Who is this message for?")
    var recipient: String?
    
    @Parameter(title: "Message", requestValueDialog: "What would you like to say?")
    var messageComponents: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The "Safe Handoff" pattern:
        // 1. Prepare content programmatically.
        // 2. Hand off to system UI for human verification and physical "Send" click.
        // This prevents "Prompt Injection" auto-sending.
        
        let text = messageComponents ?? ""
        let service = NSSharingService(named: .composeMessage)
        
        guard let service = service else {
            return .result(dialog: "Messaging service is unavailable.")
        }
        
        service.recipients = [recipient ?? ""]
        service.perform(withItems: [text])
        
        return .result(
            dialog: "I've drafted the message. Please review and hit Send."
        )
    }
}
