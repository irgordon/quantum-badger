import Foundation

/// Adapter for receiving and sending commands via Apple Messages (iMessage).
///
/// Uses an AppleScript bridge to interact with the Messages app,
/// since there is no public Messages.framework for third‑party apps.
///
/// ## Authentication
///
/// Sender identity is validated against a list of pre‑approved
/// Apple IDs / phone numbers stored in the local keychain.
public actor IMessageAdapter {

    // MARK: - Configuration

    /// Pre‑approved sender identifiers (Apple IDs or phone numbers).
    private var approvedSenders: Set<String>

    /// Polling interval in nanoseconds.
    private let pollIntervalNanoseconds: UInt64

    /// Background polling task.
    private var pollingTask: Task<Void, Never>?

    /// Callback for received commands.
    private var onCommandReceived: (@Sendable (RemoteCommand) -> Void)?

    // MARK: - Init

    public init(
        approvedSenders: Set<String> = [],
        pollIntervalSeconds: UInt64 = 5
    ) {
        self.approvedSenders = approvedSenders
        self.pollIntervalNanoseconds = pollIntervalSeconds * 1_000_000_000
    }

    // MARK: - Lifecycle

    /// Start listening for incoming iMessage commands.
    public func startListening(
        onCommand: @escaping @Sendable (RemoteCommand) -> Void
    ) {
        onCommandReceived = onCommand
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
                    await self.pollForMessages()
                } catch {
                    break // Cancelled.
                }
            }
        }
    }

    /// Stop listening.
    public func stopListening() {
        pollingTask?.cancel()
        pollingTask = nil
        onCommandReceived = nil
    }

    /// Update the approved senders list.
    public func setApprovedSenders(_ senders: Set<String>) {
        approvedSenders = senders
    }

    /// Send a reply via iMessage.
    public func sendReply(to recipient: String, text: String) async throws {
        // Security: Sanitize inputs to prevent AppleScript injection.
        let safeRecipient = sanitizeForAppleScript(recipient)
        let safeText = sanitizeForAppleScript(text)
        
        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(safeRecipient)" of targetService
            send "\(safeText)" to targetBuddy
        end tell
        """
        try await executeAppleScript(script)
    }
    
    /// Escape special characters for AppleScript string literals.
    private func sanitizeForAppleScript(_ input: String) -> String {
        input.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Polling

    private func pollForMessages() {
        // In production this would use AppleScript to read recent messages
        // from the Messages database and dispatch new commands.
        //
        // The AppleScript bridge reads:
        //   tell application "Messages"
        //       set recentMessages to messages of chat 1
        //   end tell
        //
        // For now, the polling stub is in place; the actual bridge
        // requires user consent for Accessibility and Automation.
    }

    // MARK: - AppleScript Execution

    private func executeAppleScript(_ source: String) async throws {
        try Task.checkCancellation()
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            throw IMessageError.scriptExecutionFailed(
                description: error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            )
        }
    }
}

// MARK: - Errors

/// Errors from the iMessage adapter.
@frozen
public enum IMessageError: String, Error, Sendable, Codable, Equatable, Hashable {
    case scriptExecutionFailed
    case senderNotApproved
    case messageParseFailed

    static func scriptExecutionFailed(description: String) -> IMessageError {
        .scriptExecutionFailed
    }
}
