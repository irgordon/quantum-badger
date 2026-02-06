import Foundation
import CryptoKit

final class AuditPayloadStore {
    private let directoryURL: URL
    private let keychain: KeychainStore
    private var retentionDays: Int

    init(
        directoryURL: URL = AppPaths.auditPayloadsDirectory,
        keychain: KeychainStore,
        retentionDays: Int = 30
    ) {
        self.directoryURL = directoryURL
        self.keychain = keychain
        self.retentionDays = retentionDays
    }

    func updateRetentionDays(_ value: Int) {
        retentionDays = value
    }

    func storePayload(_ data: Data) -> String? {
        let id = UUID().uuidString
        let url = directoryURL.appendingPathComponent("\(id).payload")
        do {
            let key = try keychain.loadOrCreateKey()
            let sealed = try AES.GCM.seal(data, using: key)
            if let combined = sealed.combined {
                try JSONStore.writeAtomically(data: combined, to: url)
                return id
            }
        } catch {
            AppLogger.storage.error("Failed to store audit payload: \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }

    func loadPayload(id: String) -> Data? {
        let url = directoryURL.appendingPathComponent("\(id).payload")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let key = try keychain.loadOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            AppLogger.storage.error("Failed to load audit payload: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func isolatePayload(id: String) -> Bool {
        let sourceURL = directoryURL.appendingPathComponent("\(id).payload")
        let quarantineURL = directoryURL.appendingPathComponent("\(id).payload.quarantine")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }
        do {
            if FileManager.default.fileExists(atPath: quarantineURL.path) {
                try FileManager.default.removeItem(at: quarantineURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: quarantineURL)
            return true
        } catch {
            AppLogger.storage.error("Failed to quarantine audit payload: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    func pruneExpiredAndVacuum(referencedIds: Set<String>) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return
        }
        for case let fileURL as URL in enumerator {
            let id = fileURL.deletingPathExtension().lastPathComponent
            let isReferenced = referencedIds.contains(id)
            let attributes = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = attributes?.contentModificationDate ?? Date()
            let isExpired = modifiedAt < cutoff
            if isExpired || !isReferenced {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
