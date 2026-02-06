import Foundation

struct PersistenceHealthReport: Codable {
    let auditEntryCount: Int
    let auditChainHash: String
    let auditChainValid: Bool
    let referencedPayloadCount: Int
    let payloadFileCount: Int
    let payloadCountMatches: Bool
    let payloadHashCombined: String
    let payloadHashedCount: Int
    let payloadUnreadableCount: Int
    let unreadablePayloadIds: [String]
}

enum PersistenceHealthCheck {
    static func run(auditLog: AuditLog) async -> PersistenceHealthReport {
        let auditEntryCount = auditLog.entries.count
        let auditChainHash = auditLog.integrityHash()
        let auditChainValid = auditLog.verifyIntegrity()
        let referenced = referencedPayloadIds(auditLog)
        let payloadFileCount = countPayloadFiles()
        let payloadCountMatches = payloadFileCount == referenced.count
        let payloadScan = await ParallelHealthScanner.scanPayloads()

        return PersistenceHealthReport(
            auditEntryCount: auditEntryCount,
            auditChainHash: auditChainHash,
            auditChainValid: auditChainValid,
            referencedPayloadCount: referenced.count,
            payloadFileCount: payloadFileCount,
            payloadCountMatches: payloadCountMatches,
            payloadHashCombined: payloadScan.combinedHash,
            payloadHashedCount: payloadScan.hashedCount,
            payloadUnreadableCount: payloadScan.unreadableCount,
            unreadablePayloadIds: payloadScan.unreadableIds
        )
    }

    private static func referencedPayloadIds(_ auditLog: AuditLog) -> Set<String> {
        var ids = Set<String>()
        for entry in auditLog.entries {
            if let ref = entry.event.payloadBeforeRef {
                ids.insert(ref)
            }
            if let ref = entry.event.payloadAfterRef {
                ids.insert(ref)
            }
        }
        return ids
    }

    private static func countPayloadFiles() -> Int {
        let directory = AppPaths.auditPayloadsDirectory
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "payload" {
                count += 1
            }
        }
        return count
    }
}
