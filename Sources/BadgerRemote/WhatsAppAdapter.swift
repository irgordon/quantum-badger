import Foundation

/// Adapter for the WhatsApp Cloud API webhook interface.
///
/// Receives incoming messages via HTTP webhook callbacks and sends
/// replies through the WhatsApp Cloud API. All communication uses
/// HTTPS with bearer‑token authentication.
public actor WhatsAppAdapter {

    // MARK: - Configuration

    /// WhatsApp Cloud API base URL.
    private let apiBaseURL: URL

    /// Bearer token for API authentication.
    private let accessToken: String

    /// Phone number ID for the WhatsApp Business Account.
    private let phoneNumberID: String

    /// Pre‑approved sender phone numbers.
    private var approvedSenders: Set<String>

    /// URLSession for API calls.
    private let session: URLSession

    /// Callback for received commands.
    private var onCommandReceived: (@Sendable (RemoteCommand) -> Void)?

    // MARK: - Init

    public init(
        accessToken: String,
        phoneNumberID: String,
        approvedSenders: Set<String> = [],
        apiBaseURL: URL = URL(string: "https://graph.facebook.com/v21.0")!
    ) {
        self.accessToken = accessToken
        self.phoneNumberID = phoneNumberID
        self.approvedSenders = approvedSenders
        self.apiBaseURL = apiBaseURL

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Webhook Handling

    /// Process an incoming webhook payload from WhatsApp.
    ///
    /// - Parameter payload: Raw JSON data from the webhook POST body.
    /// - Returns: Parsed ``RemoteCommand`` if the message is valid and from
    ///   an approved sender.
    public func processWebhook(payload: Data) throws -> RemoteCommand? {
        let decoded = try JSONDecoder().decode(
            WhatsAppWebhookPayload.self,
            from: payload
        )

        guard let entry = decoded.entry.first,
              let change = entry.changes.first,
              let message = change.value.messages?.first else {
            return nil
        }

        let senderPhone = message.from
        let isApproved = approvedSenders.contains(senderPhone)

        guard isApproved else { return nil }

        return RemoteCommand(
            channel: .whatsApp,
            rawText: message.text?.body ?? "",
            isAuthenticated: true,
            senderID: senderPhone
        )
    }

    /// Register the command handler.
    public func setCommandHandler(
        _ handler: @escaping @Sendable (RemoteCommand) -> Void
    ) {
        onCommandReceived = handler
    }

    /// Update approved senders.
    public func setApprovedSenders(_ senders: Set<String>) {
        approvedSenders = senders
    }

    // MARK: - Sending

    /// Send a text reply to a WhatsApp user.
    public func sendReply(to phone: String, text: String) async throws {
        try Task.checkCancellation()

        let url = apiBaseURL
            .appendingPathComponent(phoneNumberID)
            .appendingPathComponent("messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "messaging_product": "whatsapp",
            "to": phone,
            "type": "text",
            "text": ["body": text],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw WhatsAppError.sendFailed
        }
    }
}

// MARK: - Webhook Payload Models

/// Top‑level WhatsApp webhook payload.
struct WhatsAppWebhookPayload: Sendable, Codable {
    let entry: [WebhookEntry]
}

struct WebhookEntry: Sendable, Codable {
    let changes: [WebhookChange]
}

struct WebhookChange: Sendable, Codable {
    let value: WebhookValue
}

struct WebhookValue: Sendable, Codable {
    let messages: [WebhookMessage]?
}

struct WebhookMessage: Sendable, Codable {
    let from: String
    let text: WebhookText?
}

struct WebhookText: Sendable, Codable {
    let body: String
}

// MARK: - Errors

@frozen
public enum WhatsAppError: String, Error, Sendable, Codable, Equatable, Hashable {
    case sendFailed
    case webhookParseFailed
    case senderNotApproved
}
