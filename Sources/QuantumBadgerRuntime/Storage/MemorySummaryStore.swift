import Foundation
import CryptoKit

final class MemorySummaryStore {
    private let storageURL: URL
    private let keychain: KeychainStore
    // Performance: cache decrypted entries to avoid disk I/O + re-decryption on every read.
    private var cachedEncrypted: [EncryptedMemoryEntry]?
    private var cachedDecrypted: [MemoryEntry]?

    init(storageURL: URL = AppPaths.memorySummaryURL, keychain: KeychainStore = KeychainStore()) {
        self.storageURL = storageURL
        self.keychain = keychain
    }

    func add(_ entry: MemoryEntry) {
        guard let encrypted = encrypt(entry) else { return }
        loadCachesIfNeeded()
        var items = cachedEncrypted ?? []
        items.append(encrypted)
        cachedEncrypted = items
        if cachedDecrypted == nil {
            cachedDecrypted = items.compactMap { decrypt($0) }
        } else {
            cachedDecrypted?.append(entry)
        }
        persistCachedEncrypted()
    }

    func entries() -> [MemoryEntry] {
        loadCachesIfNeeded()
        return cachedDecrypted ?? []
    }

    func purgeExpired() {
        loadCachesIfNeeded()
        let now = Date()
        let filtered = (cachedEncrypted ?? []).filter { entry in
            if let expiresAt = entry.expiresAt { return expiresAt > now }
            return true
        }
        cachedEncrypted = filtered
        if let decrypted = cachedDecrypted {
            let validIds = Set(filtered.map(\.id))
            cachedDecrypted = decrypted.filter { validIds.contains($0.id) }
        } else {
            cachedDecrypted = filtered.compactMap { decrypt($0) }
        }
        persistCachedEncrypted()
    }

    func delete(_ entry: MemoryEntry) {
        loadCachesIfNeeded()
        let filtered = (cachedEncrypted ?? []).filter { $0.id != entry.id }
        cachedEncrypted = filtered
        cachedDecrypted = (cachedDecrypted ?? []).filter { $0.id != entry.id }
        persistCachedEncrypted()
    }

    func reset() {
        cachedEncrypted = []
        cachedDecrypted = []
        persistCachedEncrypted()
    }

    private func loadCachesIfNeeded() {
        if cachedEncrypted != nil && cachedDecrypted != nil { return }
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([EncryptedMemoryEntry].self, from: data) else {
            cachedEncrypted = []
            cachedDecrypted = []
            return
        }
        cachedEncrypted = decoded
        cachedDecrypted = decoded.compactMap { decrypt($0) }
    }

    private func persistCachedEncrypted() {
        if let data = try? JSONEncoder().encode(cachedEncrypted ?? []) {
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
