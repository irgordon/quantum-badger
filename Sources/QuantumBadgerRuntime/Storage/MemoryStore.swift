import Foundation
import CryptoKit
import Observation

@Observable
final class MemoryStore {
    private(set) var entries: [MemoryEntry] = []
    private(set) var ephemeralEntries: [MemoryEntry] = []

    private let storageURL: URL
    private let keychain: KeychainStore
    private let auditLog: AuditLog

    init(storageURL: URL = AppPaths.memoryURL, keychain: KeychainStore = KeychainStore(), auditLog: AuditLog) {
        self.storageURL = storageURL
        self.keychain = keychain
        self.auditLog = auditLog
        load()
    }

    @discardableResult
    func addEntry(_ entry: MemoryEntry) -> Result<Void, MemoryValidationError> {
        do {
            try MemorySchemaValidator.validate(entry)
        } catch let error as MemoryValidationError {
            return .failure(error)
        } catch {
            return .failure(.emptyContent)
        }
        if entry.trustLevel == .level0Ephemeral {
            ephemeralEntries.append(entry)
            return .success(())
        }
        if entry.trustLevel == .level1UserAuthored || entry.trustLevel == .level2UserConfirmed {
            guard entry.isConfirmed else { return .success(()) }
        }
        entries.append(entry)
        persist()
        auditLog.record(event: .memoryStored(entry))
        return .success(())
    }

    func deleteEntry(_ entry: MemoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        auditLog.record(event: .memoryDeleted(entry))
    }

    func purgeExpired() {
        let now = Date()
        entries.removeAll { entry in
            if let expiresAt = entry.expiresAt {
                return expiresAt <= now
            }
            return false
        }
        ephemeralEntries.removeAll { entry in
            if let expiresAt = entry.expiresAt {
                return expiresAt <= now
            }
            return false
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let key = try keychain.loadOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: key)
            entries = try JSONDecoder().decode([MemoryEntry].self, from: decrypted)
        } catch {
            AppLogger.storage.error("Failed to load memory store: \(error.localizedDescription, privacy: .private)")
            entries = []
        }
    }

    private func persist() {
        do {
            let key = try keychain.loadOrCreateKey()
            let data = try JSONEncoder().encode(entries)
            let sealed = try AES.GCM.seal(data, using: key)
            if let combined = sealed.combined {
                try JSONStore.writeAtomically(data: combined, to: storageURL)
            }
        } catch {
            AppLogger.storage.error("Failed to persist memory store: \(error.localizedDescription, privacy: .private)")
        }
    }
}

enum MemoryTrustLevel: String, Codable, CaseIterable, Identifiable {
    case level0Ephemeral
    case level1UserAuthored
    case level2UserConfirmed
    case level3Observational
    case level4Summary
    case level5External

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .level0Ephemeral: return "Level 0 — Ephemeral"
        case .level1UserAuthored: return "Level 1 — User Authored"
        case .level2UserConfirmed: return "Level 2 — User Confirmed"
        case .level3Observational: return "Level 3 — Observational"
        case .level4Summary: return "Level 4 — Summary"
        case .level5External: return "Level 5 — External"
        }
    }
}

enum MemorySource: String, Codable, CaseIterable, Identifiable {
    case user
    case model
    case tool
    case external

    var id: String { rawValue }
}

struct MemoryEntry: Identifiable, Codable {
    let id: UUID
    var trustLevel: MemoryTrustLevel
    var content: String
    var sourceType: MemorySource
    var sourceDetail: String
    var createdAt: Date
    var isConfirmed: Bool
    var confirmedAt: Date?
    var expiresAt: Date?

    init(
        id: UUID = UUID(),
        trustLevel: MemoryTrustLevel,
        content: String,
        sourceType: MemorySource,
        sourceDetail: String,
        createdAt: Date = Date(),
        isConfirmed: Bool,
        confirmedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.trustLevel = trustLevel
        self.content = content
        self.sourceType = sourceType
        self.sourceDetail = sourceDetail
        self.createdAt = createdAt
        self.isConfirmed = isConfirmed
        self.confirmedAt = confirmedAt
        self.expiresAt = expiresAt
    }
}
