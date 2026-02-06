import Foundation
import CryptoKit
import Observation

@Observable
final class AuditLog {
    private(set) var entries: [AuditEntry] = []
    private let storageURL: URL
    private let keychain: KeychainStore
    private let payloadStore: AuditPayloadStore
    private let persistQueue = DispatchQueue(label: "com.quantumbadger.audit.persist", qos: .utility)
    private let maxEntries = 2000
    private var rotationInProgress: Bool = false
    private var lastPayloadCleanup: Date?

    init(storageURL: URL = AppPaths.auditLogURL, keychain: KeychainStore = KeychainStore(service: "com.quantumbadger.audit")) {
        self.storageURL = storageURL
        self.keychain = keychain
        self.payloadStore = AuditPayloadStore(keychain: keychain)
        load()
    }

    func record(event: AuditEvent) {
        let previousHash = entries.last?.hash ?? ""
        let hash = hashEvent(event, previousHash: previousHash)
        let entry = AuditEntry(id: UUID(), event: event, previousHash: previousHash, hash: hash)
        entries.append(entry)
        rotateIfNeeded()
        persist()
    }

    func exportRequested() async {
        record(event: .exportRequested)
    }

    func export(to url: URL, option: ExportOption) async -> Bool {
        record(event: .exportRequested)
        do {
            if option.isEncrypted {
                let exportEntries = entries.map { resolvePayloadsForExport($0) }
                let data = try JSONEncoder().encode(exportEntries)
                guard let password = option.password else { return false }
                let envelope = try ExportEnvelope.seal(data: data, password: password)
                let payload = try JSONEncoder().encode(envelope)
                try JSONStore.writeAtomically(data: payload, to: url)
            } else {
                return exportUnencryptedStreaming(to: url)
            }
            return true
        } catch {
            AppLogger.storage.error("Failed to export audit log: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func exportUnencryptedStreaming(to url: URL) -> Bool {
        let tempURL = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else { return false }
        defer {
            try? handle.close()
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            try handle.write(contentsOf: Data("[".utf8))
            var first = true
            for entry in entries {
                let resolved = resolvePayloadsForExport(entry)
                let data = try encoder.encode(resolved)
                if !first {
                    try handle.write(contentsOf: Data(",".utf8))
                }
                try handle.write(contentsOf: data)
                first = false
            }
            try handle.write(contentsOf: Data("]".utf8))
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
            return true
        } catch {
            AppLogger.storage.error("Failed to export audit log: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let key = try keychain.loadOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: key)
            entries = try JSONDecoder().decode([AuditEntry].self, from: decrypted)
            rotateIfNeeded()
            schedulePayloadCleanup()
        } catch {
            AppLogger.storage.error("Failed to load audit log: \(error.localizedDescription, privacy: .private)")
            entries = []
        }
    }

    private func persist() {
        let snapshot = entries
        let storageURL = self.storageURL
        persistQueue.async { [keychain] in
            do {
                let key = try keychain.loadOrCreateKey()
                let data = try JSONEncoder().encode(snapshot)
                let sealed = try AES.GCM.seal(data, using: key)
                if let combined = sealed.combined {
                    try JSONStore.writeAtomically(data: combined, to: storageURL)
                }
            } catch {
                AppLogger.storage.error("Failed to persist audit log: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func flush() async {
        let snapshot = entries
        let storageURL = self.storageURL
        await withCheckedContinuation { continuation in
            persistQueue.async { [keychain] in
                do {
                    let key = try keychain.loadOrCreateKey()
                    let data = try JSONEncoder().encode(snapshot)
                    let sealed = try AES.GCM.seal(data, using: key)
                    if let combined = sealed.combined {
                        try JSONStore.writeAtomically(data: combined, to: storageURL)
                    }
                } catch {
                    AppLogger.storage.error("Failed to flush audit log: \(error.localizedDescription, privacy: .private)")
                }
                continuation.resume()
            }
        }
    }

    private func rotateIfNeeded() {
        guard entries.count > maxEntries else { return }
        guard !rotationInProgress else { return }
        rotationInProgress = true
        let snapshot = entries
        let snapshotLastId = snapshot.last?.id
        persistQueue.async { [weak self] in
            guard let self else { return }
            let truncated = Array(snapshot.suffix(self.maxEntries))
            let recomputed = self.recomputeHashes(truncated)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.rotationInProgress = false }
                guard self.entries.count == snapshot.count,
                      self.entries.last?.id == snapshotLastId else {
                    return
                }
                self.entries = recomputed
                self.schedulePayloadCleanup()
            }
        }
    }

    private func recomputeHashes(_ items: [AuditEntry]) -> [AuditEntry] {
        var recomputed: [AuditEntry] = []
        var previousHash = ""
        for entry in items {
            let hash = hashEvent(entry.event, previousHash: previousHash)
            let updated = AuditEntry(id: entry.id, event: entry.event, previousHash: previousHash, hash: hash)
            recomputed.append(updated)
            previousHash = hash
        }
        return recomputed
    }

    private func hashEvent(_ event: AuditEvent, previousHash: String) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let eventData = (try? encoder.encode(event)) ?? Data()
        let previousData = Data(previousHash.utf8)
        var payload = Data()
        payload.append(eventData)
        payload.append(previousData)
        return Hashing.sha256(payload)
    }

    func integrityHash() -> String {
        entries.last?.hash ?? ""
    }

    func verifyIntegrity() -> Bool {
        var previousHash = ""
        for entry in entries {
            let recomputed = hashEvent(entry.event, previousHash: previousHash)
            if recomputed != entry.hash {
                return false
            }
            previousHash = recomputed
        }
        return true
    }

    func recordNetworkPayloadRedaction(decision: NetworkDecision, before: Data, after: Data) {
        let beforeId = payloadStore.storePayload(before)
        let afterId = payloadStore.storePayload(after)
        let previewLimit = 500
        let beforeString = String(data: before, encoding: .utf8) ?? "<non-utf8 payload>"
        let afterString = String(data: after, encoding: .utf8) ?? "<non-utf8 payload>"
        let truncated = beforeString.count > previewLimit || afterString.count > previewLimit
        let previewBefore = beforeString.count > previewLimit ? String(beforeString.prefix(previewLimit)) + "…" : beforeString
        let previewAfter = afterString.count > previewLimit ? String(afterString.prefix(previewLimit)) + "…" : afterString
        let event = AuditEvent.networkPayloadRedacted(
            decision: decision,
            beforePreview: previewBefore,
            afterPreview: previewAfter,
            beforeRef: beforeId,
            afterRef: afterId,
            truncated: truncated
        )
        let previousHash = entries.last?.hash ?? ""
        let hash = hashEvent(event, previousHash: previousHash)
        let entry = AuditEntry(id: UUID(), event: event, previousHash: previousHash, hash: hash)
        entries.append(entry)
        rotateIfNeeded()
        persist()
        schedulePayloadCleanup()
    }

    func payloadString(for ref: String) -> String? {
        guard let data = payloadStore.loadPayload(id: ref) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func isolatePayload(id: String) -> Bool {
        payloadStore.isolatePayload(id: id)
    }

    private func resolvePayloadsForExport(_ entry: AuditEntry) -> AuditEntry {
        guard entry.event.kind == .networkPayloadRedacted else { return entry }
        var event = entry.event
        if let ref = event.payloadBeforeRef, let loaded = payloadStore.loadPayload(id: ref),
           let text = String(data: loaded, encoding: .utf8) {
            event.payloadBefore = text
        }
        if let ref = event.payloadAfterRef, let loaded = payloadStore.loadPayload(id: ref),
           let text = String(data: loaded, encoding: .utf8) {
            event.payloadAfter = text
        }
        return AuditEntry(id: entry.id, event: event, previousHash: entry.previousHash, hash: entry.hash)
    }

    private func schedulePayloadCleanup() {
        schedulePayloadCleanup(force: false)
    }

    func updatePayloadRetentionDays(_ days: Int) {
        payloadStore.updateRetentionDays(days)
        schedulePayloadCleanup(force: true)
    }

    private func schedulePayloadCleanup(force: Bool) {
        let now = Date()
        if !force, let last = lastPayloadCleanup, now.timeIntervalSince(last) < 60 * 60 * 12 {
            return
        }
        lastPayloadCleanup = now
        let referenced = referencedPayloadIds()
        persistQueue.async { [payloadStore] in
            payloadStore.pruneExpiredAndVacuum(referencedIds: referenced)
        }
    }

    private func referencedPayloadIds() -> Set<String> {
        var ids = Set<String>()
        for entry in entries {
            if let ref = entry.event.payloadBeforeRef {
                ids.insert(ref)
            }
            if let ref = entry.event.payloadAfterRef {
                ids.insert(ref)
            }
        }
        return ids
    }

    func performPayloadVacuum(referenced: Set<String>) {
        persistQueue.async { [payloadStore] in
            payloadStore.pruneExpiredAndVacuum(referencedIds: referenced)
        }
    }
}

struct AuditEntry: Identifiable, Codable {
    let id: UUID
    let event: AuditEvent
    let previousHash: String
    let hash: String
}

struct AuditEvent: Codable {
    enum Kind: String, Codable {
        case planProposed
        case toolStarted
        case toolFinished
        case toolDenied
        case toolStopped
        case modelPrompted
        case permissionGranted
        case permissionRevoked
        case modelAdded
        case modelRemoved
        case modelUpdated
        case limitsUpdated
        case vaultStored
        case vaultRemoved
        case exportRequested
        case networkAttempt
        case networkRedirectBlocked
        case networkResponseTruncated
        case networkCircuitTripped
        case networkPayloadRedacted
        case memorySnapshot
        case memoryStored
        case memoryDeleted
        case memoryRollback
        case decodingSkipped
    }

    var kind: Kind
    var summary: String
    var timestamp: Date
    var purpose: NetworkPurpose?
    var allowed: Bool?
    var toolId: UUID?
    var toolResultHash: String?
    var payloadBefore: String?
    var payloadAfter: String?
    var payloadTruncated: Bool?
    var payloadBeforeRef: String?
    var payloadAfterRef: String?
    var memorySnapshot: MemorySnapshot?
    var rollbackSnapshotId: UUID?

    static func planProposed(_ plan: WorkflowPlan) -> AuditEvent {
        AuditEvent(kind: .planProposed, summary: "Plan for intent: \(plan.intent)", timestamp: Date())
    }

    static func toolStarted(_ request: ToolRequest) -> AuditEvent {
        AuditEvent(kind: .toolStarted, summary: "Tool started: \(request.toolName)", timestamp: Date(), toolId: request.id)
    }

    static func toolFinished(_ result: ToolResult) -> AuditEvent {
        AuditEvent(
            kind: .toolFinished,
            summary: "Tool finished: \(result.toolName)",
            timestamp: Date(),
            toolId: result.id,
            toolResultHash: ToolResultHasher.hash(result)
        )
    }

    static func toolDenied(_ request: ToolRequest, reason: String) -> AuditEvent {
        AuditEvent(kind: .toolDenied, summary: "Tool denied: \(request.toolName) - \(reason)", timestamp: Date(), toolId: request.id)
    }

    static func toolStopped(_ toolName: String, toolId: UUID?, reason: String) -> AuditEvent {
        AuditEvent(kind: .toolStopped, summary: "Tool stopped: \(toolName) (\(reason))", timestamp: Date(), toolId: toolId)
    }

    static func modelPrompted(_ redactedPrompt: String) -> AuditEvent {
        let trimmed = redactedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.count > 500 ? String(trimmed.prefix(500)) + "…" : trimmed
        return AuditEvent(
            kind: .modelPrompted,
            summary: "Model prompt: \(preview)",
            timestamp: Date()
        )
    }

    static func permissionGranted(_ permission: String) -> AuditEvent {
        AuditEvent(kind: .permissionGranted, summary: "Permission granted: \(permission)", timestamp: Date())
    }

    static func permissionRevoked(_ permission: String) -> AuditEvent {
        AuditEvent(kind: .permissionRevoked, summary: "Permission revoked: \(permission)", timestamp: Date())
    }

    static func modelAdded(_ model: LocalModel) -> AuditEvent {
        AuditEvent(kind: .modelAdded, summary: "Model added: \(model.name)", timestamp: Date())
    }

    static func modelRemoved(_ model: LocalModel) -> AuditEvent {
        AuditEvent(kind: .modelRemoved, summary: "Model removed: \(model.name)", timestamp: Date())
    }

    static func modelUpdated(_ model: LocalModel) -> AuditEvent {
        AuditEvent(kind: .modelUpdated, summary: "Model updated: \(model.name)", timestamp: Date())
    }

    static func limitsUpdated(_ limits: ModelLimits) -> AuditEvent {
        AuditEvent(kind: .limitsUpdated, summary: "Limits updated: ctx \(limits.maxContextTokens), temp \(limits.maxTemperature)", timestamp: Date())
    }

    static func vaultStored(_ label: String) -> AuditEvent {
        AuditEvent(kind: .vaultStored, summary: "Vault stored: \(label)", timestamp: Date())
    }

    static func vaultRemoved(_ label: String) -> AuditEvent {
        AuditEvent(kind: .vaultRemoved, summary: "Vault removed: \(label)", timestamp: Date())
    }

    static var exportRequested: AuditEvent {
        AuditEvent(kind: .exportRequested, summary: "Activity export requested", timestamp: Date())
    }

    static func memoryStored(_ entry: MemoryEntry) -> AuditEvent {
        AuditEvent(kind: .memoryStored, summary: "Memory stored: \(entry.trustLevel.rawValue)", timestamp: Date())
    }

    static func memorySnapshot(_ snapshot: MemorySnapshot) -> AuditEvent {
        let summary = "Memory snapshot before \(snapshot.origin)"
        return AuditEvent(
            kind: .memorySnapshot,
            summary: summary,
            timestamp: snapshot.timestamp,
            memorySnapshot: snapshot
        )
    }

    static func memoryDeleted(_ entry: MemoryEntry) -> AuditEvent {
        AuditEvent(kind: .memoryDeleted, summary: "Memory deleted: \(entry.trustLevel.rawValue)", timestamp: Date())
    }

    static func memoryRollback(snapshotId: UUID) -> AuditEvent {
        AuditEvent(
            kind: .memoryRollback,
            summary: "Memory rollback to snapshot \(snapshotId.uuidString.prefix(8))",
            timestamp: Date(),
            rollbackSnapshotId: snapshotId
        )
    }

    static func decodingSkipped(path: String, index: Int, reason: String) -> AuditEvent {
        let pathDescription = path.isEmpty ? "root" : path
        return AuditEvent(
            kind: .decodingSkipped,
            summary: "Skipped malformed element at \(pathDescription)[\(index)]: \(reason)",
            timestamp: Date()
        )
    }

    static func networkAttempt(decision: NetworkDecision, allowed: Bool, reason: String? = nil) -> AuditEvent {
        let host = decision.host ?? "unknown"
        let outcome = allowed ? "allowed" : "denied"
        let detail = reason ?? decision.reason
        let purpose = decision.purpose.rawValue
        return AuditEvent(
            kind: .networkAttempt,
            summary: "Network \(outcome): \(purpose) -> \(host) (\(detail))",
            timestamp: Date(),
            purpose: decision.purpose,
            allowed: allowed
        )
    }

    static func networkRedirectBlocked(host: String) -> AuditEvent {
        AuditEvent(
            kind: .networkRedirectBlocked,
            summary: "Redirect blocked to host: \(host)",
            timestamp: Date()
        )
    }

    static func networkResponseTruncated(host: String, reason: String) -> AuditEvent {
        AuditEvent(
            kind: .networkResponseTruncated,
            summary: "Response truncated from host: \(host) (\(reason))",
            timestamp: Date()
        )
    }

    static func networkCircuitTripped(host: String, cooldownSeconds: Int) -> AuditEvent {
        AuditEvent(
            kind: .networkCircuitTripped,
            summary: "Circuit tripped for \(host). Cooling down for \(cooldownSeconds)s.",
            timestamp: Date()
        )
    }

    static func networkPayloadRedacted(
        decision: NetworkDecision,
        beforePreview: String,
        afterPreview: String,
        beforeRef: String?,
        afterRef: String?,
        truncated: Bool
    ) -> AuditEvent {
        let host = decision.host ?? "unknown"
        let summary = "Redacted outbound payload for \(decision.purpose.rawValue) -> \(host)"
        return AuditEvent(
            kind: .networkPayloadRedacted,
            summary: summary,
            timestamp: Date(),
            purpose: decision.purpose,
            allowed: true,
            payloadBefore: beforePreview,
            payloadAfter: afterPreview,
            payloadTruncated: truncated,
            payloadBeforeRef: beforeRef,
            payloadAfterRef: afterRef
        )
    }
}
