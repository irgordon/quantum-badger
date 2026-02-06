import Foundation
import SwiftData
import CryptoKit
import Observation

@Model
final class MemoryRecord {
    @Attribute(.unique) var id: UUID
    var trustLevel: String
    var sourceType: String
    var sourceDetail: String
    var createdAt: Date
    var confirmedAt: Date?
    var expiresAt: Date?
    var encryptedContent: Data

    init(
        id: UUID = UUID(),
        trustLevel: String,
        sourceType: String,
        sourceDetail: String,
        createdAt: Date,
        confirmedAt: Date?,
        expiresAt: Date?,
        encryptedContent: Data
    ) {
        self.id = id
        self.trustLevel = trustLevel
        self.sourceType = sourceType
        self.sourceDetail = sourceDetail
        self.createdAt = createdAt
        self.confirmedAt = confirmedAt
        self.expiresAt = expiresAt
        self.encryptedContent = encryptedContent
    }
}

enum MemoryAddResult {
    case success
    case needsConfirmation
    case failed(MemoryValidationError)
}

struct PendingMemoryWrite: Identifiable {
    let id: UUID
    let entry: MemoryEntry
    let origin: String
    let createdAt: Date
}

@MainActor
@Observable
final class MemoryManager {
    private(set) var ephemeralEntries: [MemoryEntry] = []
    private(set) var pendingProposals: [MemoryEntry] = []
    private(set) var pendingWrites: [PendingMemoryWrite] = []
    private(set) var recoveryIssue: MemoryRecoveryIssue?

    private let modelContext: ModelContext
    private let keychain: KeychainStore
    private let auditLog: AuditLog
    private let observationStore: MemoryObservationStore
    private let summaryStore: MemorySummaryStore
    private let writePolicy: MemoryWritePolicy

    init(
        modelContext: ModelContext,
        keychain: KeychainStore = KeychainStore(),
        auditLog: AuditLog,
        writePolicy: MemoryWritePolicy = MemoryWritePolicy()
    ) {
        self.modelContext = modelContext
        self.keychain = keychain
        self.auditLog = auditLog
        self.observationStore = MemoryObservationStore()
        self.summaryStore = MemorySummaryStore()
        self.writePolicy = writePolicy
    }

    func addEntry(_ entry: MemoryEntry, source: MemoryWriteSource = .system) -> MemoryAddResult {
        do {
            try MemorySchemaValidator.validate(entry)
        } catch let error as MemoryValidationError {
            return .failed(error)
        } catch {
            return .failed(.emptyContent)
        }

        let decision = writePolicy.evaluate(entry: entry, source: source)
        if !decision.isAllowed {
            // Universal policy gate: no persistence without explicit user intent.
            let origin = entry.sourceDetail.isEmpty ? "tool output" : entry.sourceDetail
            enqueuePendingWrite(entry: entry, origin: origin)
            SystemEventBus.shared.post(.memoryWriteNeedsConfirmation(origin: origin))
            return decision.requiresUserConfirmation ? .needsConfirmation : .failed(.emptyContent)
        }

        switch entry.trustLevel {
        case .level0Ephemeral:
            ephemeralEntries.append(entry)
            return .success
        case .level1UserAuthored:
            guard entry.isConfirmed else { return .needsConfirmation }
            return persistRecord(entry)
        case .level2UserConfirmed:
            guard entry.isConfirmed else { return .needsConfirmation }
            return persistRecord(entry)
        case .level3Observational:
            observationStore.add(entry)
            return .success
        case .level4Summary:
            let piiCheck = MemoryPIIScanner.scan(entry.content)
            if piiCheck.containsSensitiveData {
                return .failed(.containsSensitiveData)
            }
            summaryStore.add(entry)
            return .success
        case .level5External:
            return persistRecord(entry)
        }
    }

    func confirmAndStore(_ entry: MemoryEntry) -> MemoryAddResult {
        var updated = entry
        updated.isConfirmed = true
        updated.confirmedAt = Date()
        return addEntry(updated, source: .userAction)
    }

    func deleteRecord(id: UUID) {
        if let record = try? modelContext.fetch(FetchDescriptor<MemoryRecord>()).first(where: { $0.id == id }) {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }

    func delete(_ entry: MemoryEntry) {
        switch entry.trustLevel {
        case .level0Ephemeral:
            ephemeralEntries.removeAll { $0.id == entry.id }
        case .level3Observational:
            observationStore.delete(entry)
        case .level4Summary:
            summaryStore.delete(entry)
        default:
            deleteRecord(id: entry.id)
        }
        auditLog.record(event: .memoryDeleted(entry))
    }

    func purgeExpired() {
        let now = Date()
        ephemeralEntries.removeAll { $0.expiresAt != nil && $0.expiresAt! <= now }
        observationStore.purgeExpired()
        summaryStore.purgeExpired()
        let descriptor = FetchDescriptor<MemoryRecord>()
        if let records = try? modelContext.fetch(descriptor) {
            for record in records where record.expiresAt != nil && record.expiresAt! <= now {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }
    }

    func timelineEntries() -> [MemoryEntry] {
        var items: [MemoryEntry] = []
        items.append(contentsOf: ephemeralEntries)
        items.append(contentsOf: observationStore.entries())
        items.append(contentsOf: summaryStore.entries())
        let descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let cachedKey = try? keychain.loadOrCreateKey()
        if let records = try? modelContext.fetch(descriptor) {
            let decrypted = records.compactMap { record in
                guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                      let sourceType = MemorySource(rawValue: record.sourceType),
                      let content = decrypt(record.encryptedContent, key: cachedKey) else { return nil }
                return MemoryEntry(
                    id: record.id,
                    trustLevel: trustLevel,
                    content: content,
                    sourceType: sourceType,
                    sourceDetail: record.sourceDetail,
                    createdAt: record.createdAt,
                    isConfirmed: record.confirmedAt != nil,
                    confirmedAt: record.confirmedAt,
                    expiresAt: record.expiresAt
                )
            }
            items.append(contentsOf: decrypted)
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func loadTimelineEntries() async -> [MemoryEntry] {
        let ephemeral = ephemeralEntries
        let observations = observationStore.entries()
        let summaries = summaryStore.entries()
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [] }
            var items: [MemoryEntry] = []
            items.append(contentsOf: ephemeral)
            items.append(contentsOf: observations)
            items.append(contentsOf: summaries)
            let cachedKey = try? self.keychain.loadOrCreateKey()
            let batchSize = 200
            var offset = 0
            while true {
                var descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset
                guard let records = try? self.modelContext.fetch(descriptor), !records.isEmpty else {
                    break
                }
                let decrypted = records.compactMap { record in
                    guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                          let sourceType = MemorySource(rawValue: record.sourceType),
                          let content = self.decrypt(record.encryptedContent, key: cachedKey) else { return nil }
                    return MemoryEntry(
                        id: record.id,
                        trustLevel: trustLevel,
                        content: content,
                        sourceType: sourceType,
                        sourceDetail: record.sourceDetail,
                        createdAt: record.createdAt,
                        isConfirmed: record.confirmedAt != nil,
                        confirmedAt: record.confirmedAt,
                        expiresAt: record.expiresAt
                    )
                }
                items.append(contentsOf: decrypted)
                if records.count < batchSize {
                    break
                }
                offset += batchSize
            }
            return items.sorted { $0.createdAt > $1.createdAt }
        }.value
    }

    func streamTimelineEntries(batchSize: Int = 200) -> AsyncThrowingStream<MemoryEntry, Error> {
        let safeBatchSize = max(1, min(batchSize, 1000))
        let ephemeral = ephemeralEntries
        let observations = observationStore.entries()
        let summaries = summaryStore.entries()
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .utility) { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for entry in ephemeral {
                    continuation.yield(entry)
                }
                for entry in observations {
                    continuation.yield(entry)
                }
                for entry in summaries {
                    continuation.yield(entry)
                }

                let cachedKey = try? self.keychain.loadOrCreateKey()
                var offset = 0
                while true {
                    var descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                    descriptor.fetchLimit = safeBatchSize
                    descriptor.fetchOffset = offset
                    guard let records = try? self.modelContext.fetch(descriptor), !records.isEmpty else {
                        break
                    }
                    for record in records {
                        guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                              let sourceType = MemorySource(rawValue: record.sourceType),
                              let content = self.decrypt(record.encryptedContent, key: cachedKey) else { continue }
                        continuation.yield(MemoryEntry(
                            id: record.id,
                            trustLevel: trustLevel,
                            content: content,
                            sourceType: sourceType,
                            sourceDetail: record.sourceDetail,
                            createdAt: record.createdAt,
                            isConfirmed: record.confirmedAt != nil,
                            confirmedAt: record.confirmedAt,
                            expiresAt: record.expiresAt
                        ))
                    }
                    if records.count < safeBatchSize {
                        break
                    }
                    offset += safeBatchSize
                }
                continuation.finish()
            }
        }
    }

    func exportTimeline(to url: URL) async -> Bool {
        let tempURL = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else { return false }
        defer { try? handle.close() }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            try handle.write(contentsOf: Data("[".utf8))
            var first = true
            // Performance: stream entries to avoid loading the full timeline into memory.
            for try await entry in streamTimelineEntries() {
                let data = try encoder.encode(entry)
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
            AppLogger.storage.error("Failed to export memory timeline: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    func loadTimelinePage(limit: Int, offset: Int) async -> [MemoryEntry] {
        let safeLimit = max(1, min(limit, 500))
        let safeOffset = max(0, offset)
        var descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = safeLimit
        descriptor.fetchOffset = safeOffset
        let includeHeader = safeOffset == 0
        let ephemeral = includeHeader ? ephemeralEntries : []
        let observations = includeHeader ? observationStore.entries() : []
        let summaries = includeHeader ? summaryStore.entries() : []

        return await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [] }
            var items: [MemoryEntry] = []
            items.append(contentsOf: ephemeral)
            items.append(contentsOf: observations)
            items.append(contentsOf: summaries)
            let cachedKey = try? self.keychain.loadOrCreateKey()
            if let records = try? self.modelContext.fetch(descriptor) {
                let decrypted = records.compactMap { record in
                    guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                          let sourceType = MemorySource(rawValue: record.sourceType),
                          let content = self.decrypt(record.encryptedContent, key: cachedKey) else { return nil }
                    return MemoryEntry(
                        id: record.id,
                        trustLevel: trustLevel,
                        content: content,
                        sourceType: sourceType,
                        sourceDetail: record.sourceDetail,
                        createdAt: record.createdAt,
                        isConfirmed: record.confirmedAt != nil,
                        confirmedAt: record.confirmedAt,
                        expiresAt: record.expiresAt
                    )
                }
                items.append(contentsOf: decrypted)
            }
            return items.sorted { $0.createdAt > $1.createdAt }
        }.value
    }

    func allowsToolAction(from entry: MemoryEntry) -> Bool {
        entry.trustLevel == .level1UserAuthored
    }

    func storeProposalAsObservation(_ entry: MemoryEntry) -> MemoryAddResult {
        pendingProposals.removeAll { $0.id == entry.id }
        var updated = entry
        updated.trustLevel = .level3Observational
        updated.expiresAt = updated.expiresAt ?? Date().addingTimeInterval(60 * 60 * 24 * 30)
        return addEntry(updated, source: .userAction)
    }

    func promoteProposalToConfirmed(_ entry: MemoryEntry) -> MemoryAddResult {
        pendingProposals.removeAll { $0.id == entry.id }
        let promoted = MemoryEntry(
            id: entry.id,
            trustLevel: .level2UserConfirmed,
            content: entry.content,
            sourceType: entry.sourceType,
            sourceDetail: entry.sourceDetail,
            createdAt: entry.createdAt,
            isConfirmed: true,
            confirmedAt: Date(),
            expiresAt: nil
        )
        return confirmAndStore(promoted)
    }

    func dismissProposal(_ entry: MemoryEntry) {
        pendingProposals.removeAll { $0.id == entry.id }
    }

    func approvePendingWrite(_ pending: PendingMemoryWrite) -> MemoryAddResult {
        pendingWrites.removeAll { $0.id == pending.id }
        if pending.entry.trustLevel == .level1UserAuthored || pending.entry.trustLevel == .level2UserConfirmed {
            return confirmAndStore(pending.entry)
        }
        return addEntry(pending.entry, source: .userAction)
    }

    func dismissPendingWrite(_ pending: PendingMemoryWrite) {
        pendingWrites.removeAll { $0.id == pending.id }
    }

    @MainActor
    @discardableResult
    func proposePromotions(from result: ToolResult) -> [MemoryEntry] {
        guard isPromotionEligible(result) else { return [] }
        let proposals = decodeProposals(from: result.output)
        guard !proposals.isEmpty else { return [] }

        let expiration = Date().addingTimeInterval(60 * 60 * 24 * 30)
        var stored: [MemoryEntry] = []
        for proposal in proposals {
            let entry = MemoryEntry(
                trustLevel: .level3Observational,
                content: proposal,
                sourceType: .tool,
                sourceDetail: result.toolName,
                isConfirmed: false,
                confirmedAt: nil,
                expiresAt: expiration
            )
            pendingProposals.append(entry)
            stored.append(entry)
        }
        return stored
    }

    private func persistRecord(_ entry: MemoryEntry) -> MemoryAddResult {
        guard let encrypted = encrypt(entry.content) else {
            return .failed(.emptyContent)
        }
        let record = MemoryRecord(
            trustLevel: entry.trustLevel.rawValue,
            sourceType: entry.sourceType.rawValue,
            sourceDetail: entry.sourceDetail,
            createdAt: entry.createdAt,
            confirmedAt: entry.confirmedAt,
            expiresAt: entry.expiresAt,
            encryptedContent: encrypted
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
            auditLog.record(event: .memoryStored(entry))
            return .success
        } catch {
            return .failed(.emptyContent)
        }
    }

    private func encrypt(_ content: String) -> Data? {
        guard let data = content.data(using: .utf8) else { return nil }
        guard let key = try? keychain.loadOrCreateKey() else {
            recoveryIssue = .keyUnavailable
            return nil
        }
        guard
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else { return nil }
        return combined
    }

    private func decrypt(_ data: Data, key: SymmetricKey?) -> String? {
        guard let key else {
            recoveryIssue = .keyUnavailable
            return nil
        }
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(box, using: key) else {
            recoveryIssue = .decryptionFailed
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    private func decodeProposals(from output: [String: String]) -> [String] {
        if let raw = output["memoryProposals"], let data = raw.data(using: .utf8) {
            if let proposals = try? JSONDecoder().decode([String].self, from: data) {
                return proposals
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .filter { $0.count <= 200 }
                    .filter { !MemoryPIIScanner.scan($0).containsSensitiveData }
                    .filter { !isHighEntropy($0) }
                    .prefix(3)
                    .map { $0 }
            }
        }
        if let proposal = output["memoryProposal"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proposal.isEmpty {
            guard proposal.count <= 200 else { return [] }
            guard !MemoryPIIScanner.scan(proposal).containsSensitiveData else { return [] }
            guard !isHighEntropy(proposal) else { return [] }
            return [proposal]
        }
        return []
    }

    func clearRecoveryIssue() {
        recoveryIssue = nil
    }

    func resetVault() {
        pendingProposals = []
        pendingWrites = []
        ephemeralEntries = []
        observationStore.reset()
        summaryStore.reset()
        let descriptor = FetchDescriptor<MemoryRecord>()
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }
        keychain.deleteKey()
        recoveryIssue = nil
    }

    func clearEphemeralCache() {
        pendingProposals = []
        pendingWrites = []
        ephemeralEntries = []
    }

    private func enqueuePendingWrite(entry: MemoryEntry, origin: String) {
        if pendingWrites.contains(where: { $0.entry.id == entry.id }) {
            return
        }
        pendingWrites.append(
            PendingMemoryWrite(
                id: UUID(),
                entry: entry,
                origin: origin,
                createdAt: Date()
            )
        )
    }

    private func isHighEntropy(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 24 { return false }
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let isBase64Like = trimmed.unicodeScalars.allSatisfy { base64Chars.contains($0) }
        if isBase64Like && trimmed.count >= 32 {
            return true
        }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let isHexLike = trimmed.unicodeScalars.allSatisfy { hexChars.contains($0) }
        if isHexLike && trimmed.count >= 32 {
            return true
        }
        return false
    }

    private func isPromotionEligible(_ result: ToolResult) -> Bool {
        guard result.succeeded else { return false }
        guard ["local.search"].contains(result.toolName) else { return false }
        guard result.output["memoryProposals"] != nil || result.output["memoryProposal"] != nil else { return false }
        return true
    }
}

enum MemoryRecoveryIssue: String {
    case keyUnavailable
    case decryptionFailed
}
