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

@MainActor
@Observable
final class MemoryManager {
    private(set) var ephemeralEntries: [MemoryEntry] = []
    private(set) var pendingProposals: [MemoryEntry] = []
    private(set) var recoveryIssue: MemoryRecoveryIssue?

    private let modelContext: ModelContext
    private let keychain: KeychainStore
    private let auditLog: AuditLog
    private let observationStore: MemoryObservationStore
    private let summaryStore: MemorySummaryStore

    init(modelContext: ModelContext, keychain: KeychainStore = KeychainStore(), auditLog: AuditLog) {
        self.modelContext = modelContext
        self.keychain = keychain
        self.auditLog = auditLog
        self.observationStore = MemoryObservationStore()
        self.summaryStore = MemorySummaryStore()
    }

    func addEntry(_ entry: MemoryEntry) -> MemoryAddResult {
        do {
            try MemorySchemaValidator.validate(entry)
        } catch let error as MemoryValidationError {
            return .failed(error)
        } catch {
            return .failed(.emptyContent)
        }

        switch entry.trustLevel {
        case .level0Ephemeral:
            ephemeralEntries.append(entry)
            return .success
        case .level1UserAuthored:
            guard entry.isConfirmed else { return .needsConfirmation }
            return persistRecord(entry)
        case .level2UserConfirmed:
            return .needsConfirmation
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
        if updated.trustLevel == .level2UserConfirmed {
            return persistRecord(updated)
        }
        return addEntry(updated)
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
        if let records = try? modelContext.fetch(descriptor) {
            let decrypted = records.compactMap { record in
                guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                      let sourceType = MemorySource(rawValue: record.sourceType),
                      let content = decrypt(record.encryptedContent) else { return nil }
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
        let descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [] }
            var items: [MemoryEntry] = []
            items.append(contentsOf: ephemeral)
            items.append(contentsOf: observations)
            items.append(contentsOf: summaries)
            if let records = try? self.modelContext.fetch(descriptor) {
                let decrypted = records.compactMap { record in
                    guard let trustLevel = MemoryTrustLevel(rawValue: record.trustLevel),
                          let sourceType = MemorySource(rawValue: record.sourceType),
                          let content = self.decrypt(record.encryptedContent) else { return nil }
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
        return addEntry(updated)
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

    private func decrypt(_ data: Data) -> String? {
        guard let key = try? keychain.loadOrCreateKey() else {
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
        ephemeralEntries = []
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
