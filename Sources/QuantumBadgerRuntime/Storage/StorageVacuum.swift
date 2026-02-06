import Foundation

enum StorageVacuum {
    static func cleanupAuditPayloads(auditLog: AuditLog) {
        let referenced = auditLogSnapshotPayloadRefs(auditLog)
        DispatchQueue.global(qos: .utility).async {
            auditLog.performPayloadVacuum(referenced: referenced)
        }
    }

    private static func auditLogSnapshotPayloadRefs(_ auditLog: AuditLog) -> Set<String> {
        var refs = Set<String>()
        for entry in auditLog.entries {
            if let ref = entry.event.payloadBeforeRef {
                refs.insert(ref)
            }
            if let ref = entry.event.payloadAfterRef {
                refs.insert(ref)
            }
        }
        return refs
    }
}
