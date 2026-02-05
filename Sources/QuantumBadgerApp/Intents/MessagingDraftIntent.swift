import AppIntents
import AppKit

struct MessagingDraftIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft a Message"
    static var description = IntentDescription("Draft a message using Quantum Badger’s trusted contacts.")

    @Parameter(title: "Recipient")
    var recipient: String

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let service = NSSharingService(named: .composeMessage) else {
            return .result(value: "Messaging draft is unavailable on this Mac.")
        }
        service.recipients = [recipient]
        service.perform(withItems: [message])
        return .result(value: "Draft opened in Messages.")
    }
}

struct MessagingDraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: MessagingDraftIntent(),
                phrases: [
                    "Draft a message with \(.applicationName)"
                ],
                shortTitle: "Draft Message",
                systemImageName: "bubble.left"
            )
        ]
    }
}
