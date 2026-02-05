import Foundation
import CryptoKit
import Observation
import LocalAuthentication

@Observable
final class VaultStore {
    private(set) var items: [VaultItem] = []

    private let keychain = KeychainStore()
    private let storageURL: URL
    private let auditLog: AuditLog

    init(storageURL: URL = AppPaths.vaultURL, auditLog: AuditLog) {
        self.storageURL = storageURL
        self.auditLog = auditLog
        load()
    }

    func storeSecret(label: String, value: String) {
        var snapshot = VaultSnapshot(items: items)
        let item = VaultItem(id: UUID(), label: label, createdAt: Date())
        snapshot.items.append(item)
        items = snapshot.items
        persist(snapshot: snapshot)
        do {
            try keychain.saveSecret(value, label: label)
        } catch {
            AppLogger.security.error("Failed to store secret in Keychain: \(error.localizedDescription, privacy: .private)")
        }
        auditLog.record(event: .vaultStored(label))
    }

    func storeBookmark(label: String, url: URL) {
        var snapshot = VaultSnapshot(items: items)
        if !snapshot.items.contains(where: { $0.label == label }) {
            snapshot.items.append(VaultItem(id: UUID(), label: label, createdAt: Date()))
        }
        items = snapshot.items
        persist(snapshot: snapshot)
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let encoded = "bookmark:\(bookmarkData.base64EncodedString())"
            try keychain.saveSecret(encoded, label: label)
        } catch {
            AppLogger.security.error("Failed to store bookmark: \(error.localizedDescription, privacy: .private)")
        }
        auditLog.record(event: .vaultStored(label))
    }

    func reference(forLabel label: String) -> VaultReference? {
        guard items.contains(where: { $0.label == label }) else { return nil }
        return VaultReference(label: label)
    }

    func secret(for reference: VaultReference, context: LAContext? = nil) -> String? {
        secret(forLabel: reference.label, context: context)
    }

    func remove(item: VaultItem) {
        items.removeAll { $0.id == item.id }
        persist(snapshot: VaultSnapshot(items: items))
        do {
            try keychain.deleteSecret(label: item.label)
        } catch {
            AppLogger.security.error("Failed to delete secret from Keychain: \(error.localizedDescription, privacy: .private)")
        }
        auditLog.record(event: .vaultRemoved(item.label))
    }

    func secret(forLabel label: String, context: LAContext? = nil) -> String? {
        do {
            return try keychain.loadSecret(label: label, context: context)
        } catch {
            AppLogger.security.error("Failed to load secret from Keychain: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    struct BookmarkResolution {
        let url: URL
        let isStale: Bool
    }

    func bookmarkResolution(for reference: VaultReference, context: LAContext? = nil) -> BookmarkResolution? {
        guard let stored = secret(forLabel: reference.label, context: context) else { return nil }
        guard stored.hasPrefix("bookmark:") else { return nil }
        let base64 = String(stored.dropFirst("bookmark:".count))
        guard let data = Data(base64Encoded: base64) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return BookmarkResolution(url: url, isStale: isStale)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let key = try keychain.loadOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: key)
            let snapshot = try JSONDecoder().decode(VaultSnapshot.self, from: decrypted)
            items = snapshot.items
        } catch {
            AppLogger.storage.error("Failed to load vault: \(error.localizedDescription, privacy: .private)")
            items = []
        }
    }

    private func persist(snapshot: VaultSnapshot) {
        do {
            let key = try keychain.loadOrCreateKey()
            let data = try JSONEncoder().encode(snapshot)
            let sealed = try AES.GCM.seal(data, using: key)
            if let combined = sealed.combined {
                try JSONStore.writeAtomically(data: combined, to: storageURL)
            }
        } catch {
            AppLogger.storage.error("Failed to persist vault: \(error.localizedDescription, privacy: .private)")
        }
    }
}

struct VaultItem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var createdAt: Date
}

struct VaultSnapshot: Codable {
    var items: [VaultItem]
}
