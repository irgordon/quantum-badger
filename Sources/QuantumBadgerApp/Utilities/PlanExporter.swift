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

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            if option.isEncrypted {
                let package = PlanExportPackage(
                    version: 1,
                    generatedAt: Date(),
                    plan: plan,
                    results: results,
                    auditEntries: relevantAudit,
                    toolResultHashes: resultHashes,
                    auditLogTailHash: auditEntries.last?.hash
                )
                let data = try encoder.encode(package)
                guard let password = option.password else { return false }
                let envelope = try ExportEnvelope.seal(data: data, password: password)
                let payload = try encoder.encode(envelope)
                try JSONStore.writeAtomically(data: payload, to: url)
            } else {
                return exportStreaming(
                    plan: plan,
                    results: results,
                    auditEntries: relevantAudit,
                    resultHashes: resultHashes,
                    tailHash: auditEntries.last?.hash,
                    encoder: encoder,
                    to: url
                )
            }
            return true
        } catch {
            return false
        }
    }

    private static func exportStreaming(
        plan: WorkflowPlan,
        results: [ToolResult],
        auditEntries: [AuditEntry],
        resultHashes: [UUID: String],
        tailHash: String?,
        encoder: JSONEncoder,
        to url: URL
    ) -> Bool {
        let tempURL = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else { return false }
        defer { try? handle.close() }

        func write(_ string: String) throws {
            try handle.write(contentsOf: Data(string.utf8))
        }

        do {
            try write("{")
            try write("\"version\":1,")

            let generatedAt = Date()
            let generatedAtJSON = try encoder.encode(generatedAt)
            try write("\"generatedAt\":")
            try handle.write(contentsOf: generatedAtJSON)
            try write(",")

            let planJSON = try encoder.encode(plan)
            try write("\"plan\":")
            try handle.write(contentsOf: planJSON)
            try write(",")

            try write("\"results\":[")
            var first = true
            for result in results {
                let data = try encoder.encode(result)
                if !first { try write(",") }
                try handle.write(contentsOf: data)
                first = false
            }
            try write("],")

            try write("\"auditEntries\":[")
            first = true
            for entry in auditEntries {
                let data = try encoder.encode(entry)
                if !first { try write(",") }
                try handle.write(contentsOf: data)
                first = false
            }
            try write("],")

            let hashesJSON = try encoder.encode(resultHashes)
            try write("\"toolResultHashes\":")
            try handle.write(contentsOf: hashesJSON)
            try write(",")

            let tailJSON = try encoder.encode(tailHash)
            try write("\"auditLogTailHash\":")
            try handle.write(contentsOf: tailJSON)
            try write("}")

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
            return true
        } catch {
            return false
        }
    }
}
