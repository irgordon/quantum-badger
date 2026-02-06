import Foundation
import Observation

@MainActor
@Observable
final class MessagingPolicyStore {
    private let storageURL: URL
    private(set) var trustedContacts: [TrustedContact]
    private(set) var maxMessagesPerMinute: Int
    private var messageTimestamps: [Date] = []
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.messagingPolicyURL) {
        self.storageURL = storageURL
        let defaults = MessagingPolicySnapshot(trustedContacts: [], maxMessagesPerMinute: 5)
        self.trustedContacts = defaults.trustedContacts
        self.maxMessagesPerMinute = max(1, min(defaults.maxMessagesPerMinute, 20))
        loadAsync(defaults: defaults)
    }

    func addContact(name: String, handle: String, conversationKey: String?) {
        didMutate = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedHandle.isEmpty else { return }
        let key = conversationKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = (key?.isEmpty ?? true) ? nil : key
        let contact = TrustedContact(id: UUID(), name: trimmedName, handle: trimmedHandle, conversationKey: normalizedKey)
        trustedContacts.append(contact)
        persist()
    }

    func removeContact(_ contact: TrustedContact) {
        didMutate = true
        trustedContacts.removeAll { $0.id == contact.id }
        persist()
    }

    func resolveRecipient(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trustedContacts.contains(where: { $0.handle.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return trimmed
        }
        if let match = trustedContacts.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match.handle
        }
        return nil
    }

    func contact(for handle: String) -> TrustedContact? {
        trustedContacts.first { $0.handle.caseInsensitiveCompare(handle) == .orderedSame }
    }

    func conversationKey(for recipient: String) -> String? {
        trustedContacts.first { $0.handle.caseInsensitiveCompare(recipient) == .orderedSame }?.conversationKey
    }

    func isConversationAllowed(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        return trustedContacts.contains(where: { $0.conversationKey == key })
    }

    func isRecipientAllowed(_ value: String) -> Bool {
        resolveRecipient(value) != nil
    }

    func setMaxMessagesPerMinute(_ value: Int) {
        didMutate = true
        maxMessagesPerMinute = max(1, min(value, 20))
        persist()
    }

    func canSendMessageNow() -> Bool {
        purgeOld()
        return messageTimestamps.count < maxMessagesPerMinute
    }

    func recordMessageSent() {
        purgeOld()
        messageTimestamps.append(Date())
    }

    private func purgeOld() {
        let cutoff = Date().addingTimeInterval(-60)
        messageTimestamps.removeAll { $0 < cutoff }
    }

    private func persist() {
        let snapshot = MessagingPolicySnapshot(
            trustedContacts: trustedContacts,
            maxMessagesPerMinute: maxMessagesPerMinute
        )
        try? JSONStore.save(snapshot, to: storageURL)
    }

    private func loadAsync(defaults: MessagingPolicySnapshot) {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = JSONStore.load(MessagingPolicySnapshot.self, from: storageURL, defaultValue: defaults)
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.trustedContacts = snapshot.trustedContacts
                self.maxMessagesPerMinute = max(1, min(snapshot.maxMessagesPerMinute, 20))
            }
        }
    }
}

struct TrustedContact: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var handle: String
    var conversationKey: String?
}

private struct MessagingPolicySnapshot: Codable {
    var trustedContacts: [TrustedContact]
    var maxMessagesPerMinute: Int
}
