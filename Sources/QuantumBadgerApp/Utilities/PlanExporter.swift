import Foundation
import QuantumBadgerRuntime

struct PlanExportPackage: Codable {
    let version: Int
    let generatedAt: Date
    let plan: WorkflowPlan
    let results: [ToolResult]
    let auditEntries: [AuditEntry]
    let toolResultHashes: [UUID: String]
    let auditLogTailHash: String?
}

enum PlanExporter {
    static func export(
        plan: WorkflowPlan,
        results: [ToolResult],
        auditEntries: [AuditEntry],
        option: ExportOption,
        to url: URL
    ) async -> Bool {
        do {
            let relevantAudit = auditEntries.filter { entry in
                switch entry.event.kind {
                case .planProposed, .toolStarted, .toolFinished, .toolDenied, .toolStopped:
                    return true
                default:
                    return false
                }
            }

            let resultHashes = Dictionary(
                uniqueKeysWithValues: results.map { ($0.id, ToolResultHasher.hash($0)) }
            )

            let package = PlanExportPackage(
                version: 1,
                generatedAt: Date(),
                plan: plan,
                results: results,
                auditEntries: relevantAudit,
                toolResultHashes: resultHashes,
                auditLogTailHash: auditEntries.last?.hash
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(package)

            if option.isEncrypted {
                guard let password = option.password else { return false }
                let envelope = try ExportEnvelope.seal(data: data, password: password)
                let payload = try encoder.encode(envelope)
                try JSONStore.writeAtomically(data: payload, to: url)
            } else {
                try JSONStore.writeAtomically(data: data, to: url)
            }
            return true
        } catch {
            return false
        }
    }
}
