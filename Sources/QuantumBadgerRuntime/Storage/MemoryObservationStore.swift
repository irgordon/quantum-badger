import Foundation
import CryptoKit

final class MemoryObservationStore {
    private let storageURL: URL
    private let keychain: KeychainStore

    init(storageURL: URL = AppPaths.memoryObservationURL, keychain: KeychainStore = KeychainStore()) {
        self.storageURL = storageURL
        self.keychain = keychain
    }

    func add(_ entry: MemoryEntry) {
        var items = encryptedEntries()
        if let encrypted = encrypt(entry) {
            items.append(encrypted)
            persist(items)
        }
    }

    func entries() -> [MemoryEntry] {
        return encryptedEntries().compactMap { decrypt($0) }
    }

    func purgeExpired() {
        let now = Date()
        let filtered = encryptedEntries().filter { entry in
            if let expiresAt = entry.expiresAt { return expiresAt > now }
            return true
        }
        persist(filtered)
    }

    func delete(_ entry: MemoryEntry) {
        let filtered = encryptedEntries().filter { $0.id != entry.id }
        persist(filtered)
    }

    func reset() {
        persist([])
    }

    private func encryptedEntries() -> [EncryptedMemoryEntry] {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([EncryptedMemoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ entries: [EncryptedMemoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? JSONStore.writeAtomically(data: data, to: storageURL)
        }
    }

    private func encrypt(_ entry: MemoryEntry) -> EncryptedMemoryEntry? {
        guard let key = try? keychain.loadOrCreateKey(),
              let data = entry.content.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else { return nil }
        return EncryptedMemoryEntry(
            id: entry.id,
            trustLevel: entry.trustLevel.rawValue,
            sourceType: entry.sourceType.rawValue,
            sourceDetail: entry.sourceDetail,
            createdAt: entry.createdAt,
            confirmedAt: entry.confirmedAt,
            expiresAt: entry.expiresAt,
            encryptedContent: combined
        )
    }

    private func decrypt(_ entry: EncryptedMemoryEntry) -> MemoryEntry? {
        guard let key = try? keychain.loadOrCreateKey(),
              let box = try? AES.GCM.SealedBox(combined: entry.encryptedContent),
              let decrypted = try? AES.GCM.open(box, using: key),
              let content = String(data: decrypted, encoding: .utf8),
              let trustLevel = MemoryTrustLevel(rawValue: entry.trustLevel),
              let sourceType = MemorySource(rawValue: entry.sourceType) else { return nil }
        return MemoryEntry(
            id: entry.id,
            trustLevel: trustLevel,
            content: content,
            sourceType: sourceType,
            sourceDetail: entry.sourceDetail,
            createdAt: entry.createdAt,
            isConfirmed: entry.confirmedAt != nil,
            confirmedAt: entry.confirmedAt,
            expiresAt: entry.expiresAt
        )
    }
}

private struct EncryptedMemoryEntry: Codable {
    let id: UUID
    let trustLevel: String
    let sourceType: String
    let sourceDetail: String
    let createdAt: Date
    let confirmedAt: Date?
    let expiresAt: Date?
    let encryptedContent: Data
}
