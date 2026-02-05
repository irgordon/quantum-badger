import Foundation
import Observation

@Observable
final class ModelRegistry {
    private(set) var models: [LocalModel]
    private(set) var limits: ModelLimits
    private var lockedModelIds: Set<UUID> = []
    private let persistQueue = DispatchQueue(label: "com.quantumbadger.modelregistry.persist", qos: .utility)

    private let storageURL: URL
    private let checksumURL: URL
    private let backupURL: URL
    private let backupChecksumURL: URL
    private let auditLog: AuditLog

    init(
        storageURL: URL = AppPaths.modelsURL,
        checksumURL: URL = AppPaths.modelsChecksumURL,
        backupURL: URL = AppPaths.modelsBackupURL,
        backupChecksumURL: URL = AppPaths.modelsBackupChecksumURL,
        auditLog: AuditLog
    ) {
        self.storageURL = storageURL
        self.checksumURL = checksumURL
        self.backupURL = backupURL
        self.backupChecksumURL = backupChecksumURL
        self.auditLog = auditLog

        let defaults = RegistrySnapshot(
            models: [],
            limits: ModelLimits(maxContextTokens: 8192, maxTemperature: 1.2, maxTokens: 2048)
        )
        let snapshot = loadSnapshot(defaults: defaults)
        self.models = snapshot.models
        self.limits = snapshot.limits
    }

    func addModel(_ model: LocalModel) {
        models.append(model)
        persist()
        auditLog.record(event: .modelAdded(model))
    }

    @discardableResult
    func removeModel(_ model: LocalModel) -> Bool {
        guard !lockedModelIds.contains(model.id) else {
            AppLogger.security.error("Attempted to remove a locked model.", privacy: .private)
            return false
        }
        models.removeAll { $0.id == model.id }
        persist()
        auditLog.record(event: .modelRemoved(model))
        return true
    }

    func updateModel(_ model: LocalModel) {
        guard let index = models.firstIndex(where: { $0.id == model.id }) else { return }
        models[index] = model
        persist()
        auditLog.record(event: .modelUpdated(model))
    }

    func lockModel(_ id: UUID) {
        lockedModelIds.insert(id)
    }

    func unlockModel(_ id: UUID) {
        lockedModelIds.remove(id)
    }

    func isModelLocked(_ id: UUID) -> Bool {
        lockedModelIds.contains(id)
    }

    func withSecurityScopedModelURL<T>(_ model: LocalModel, perform: (URL) throws -> T) rethrows -> T? {
        guard let bookmarkData = model.bookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if isStale {
                try refreshBookmark(for: model, url: url)
            }
            return try perform(url)
        } catch {
            AppLogger.security.error("Failed to resolve model bookmark: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func updateLimits(_ limits: ModelLimits) {
        self.limits = limits
        persist()
        auditLog.record(event: .limitsUpdated(limits))
    }

    func localModels() -> [LocalModel] {
        models.filter { !$0.isCloud }
    }

    func isModelPathReachable(_ model: LocalModel) -> Bool {
        guard !model.isCloud else { return true }
        let fm = FileManager.default
        if fm.fileExists(atPath: model.path) {
            return true
        }
        if let bookmarkData = model.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            ) {
                if fm.fileExists(atPath: url.path) {
                    return true
                }
            }
        }
        return false
    }

    private func persist() {
        let snapshot = RegistrySnapshot(models: models, limits: limits)
        let storageURL = self.storageURL
        let checksumURL = self.checksumURL
        let backupURL = self.backupURL
        let backupChecksumURL = self.backupChecksumURL
        persistQueue.async { [snapshot] in
            do {
                try self.backupCurrentSnapshotIfPresent(
                    storageURL: storageURL,
                    checksumURL: checksumURL,
                    backupURL: backupURL,
                    backupChecksumURL: backupChecksumURL
                )
                let data = try JSONEncoder().encode(snapshot)
                try JSONStore.writeAtomically(data: data, to: storageURL)
                try self.writeChecksum(for: data, to: checksumURL)
            } catch {
                AppLogger.storage.error(
                    "Failed to persist model registry: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    private func refreshBookmark(for model: LocalModel, url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var updated = model
        updated.bookmarkData = bookmarkData
        updateModel(updated)
    }

    private struct RegistrySnapshot: Codable {
        var models: [LocalModel]
        var limits: ModelLimits
    }

    private func loadSnapshot(defaults: RegistrySnapshot) -> RegistrySnapshot {
        if let snapshot = loadVerifiedSnapshot(from: storageURL, checksumURL: checksumURL) {
            return snapshot
        }
        if let snapshot = loadVerifiedSnapshot(from: backupURL, checksumURL: backupChecksumURL) {
            restoreBackup(snapshot: snapshot)
            return snapshot
        }
        AppLogger.storage.error("Model registry corrupted; resetting to defaults.")
        return defaults
    }

    private func loadVerifiedSnapshot(from url: URL, checksumURL: URL) -> RegistrySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let checksumData = try? Data(contentsOf: checksumURL),
              let checksum = String(data: checksumData, encoding: .utf8) else {
            return nil
        }
        let trimmed = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
        let computed = Hashing.sha256(data)
        guard trimmed == computed else { return nil }
        do {
            return try JSONDecoder().decode(RegistrySnapshot.self, from: data)
        } catch {
            AppLogger.storage.error(
                "Failed to decode model registry: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    private func writeChecksum(for data: Data, to url: URL) throws {
        let checksum = Hashing.sha256(data)
        let payload = Data(checksum.utf8)
        try JSONStore.writeAtomically(data: payload, to: url)
    }

    private func backupCurrentSnapshotIfPresent(
        storageURL: URL,
        checksumURL: URL,
        backupURL: URL,
        backupChecksumURL: URL
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: storageURL.path) {
            if fm.fileExists(atPath: backupURL.path) {
                try? fm.removeItem(at: backupURL)
            }
            try fm.copyItem(at: storageURL, to: backupURL)
        }
        if fm.fileExists(atPath: checksumURL.path) {
            if fm.fileExists(atPath: backupChecksumURL.path) {
                try? fm.removeItem(at: backupChecksumURL)
            }
            try fm.copyItem(at: checksumURL, to: backupChecksumURL)
        }
    }

    private func restoreBackup(snapshot: RegistrySnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try JSONStore.writeAtomically(data: data, to: storageURL)
            try writeChecksum(for: data, to: checksumURL)
        } catch {
            AppLogger.storage.error(
                "Failed to restore model registry backup: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}
