import Foundation

struct HealthAutoFixResult: Codable {
    let isolatedCount: Int
    let failedCount: Int
    let message: String
}

enum HealthAutoFixer {
    static func run(auditLog: AuditLog, report: PersistenceHealthReport) async -> HealthAutoFixResult {
        guard report.payloadUnreadableCount > 0 else {
            return HealthAutoFixResult(isolatedCount: 0, failedCount: 0, message: "No unreadable payloads found.")
        }
        var isolated = 0
        var failed = 0
        for id in report.unreadablePayloadIds {
            if Task.isCancelled {
                return HealthAutoFixResult(
                    isolatedCount: isolated,
                    failedCount: failed,
                    message: "Health auto-fix paused."
                )
            }
            if auditLog.isolatePayload(id: id) {
                isolated += 1
            } else {
                failed += 1
            }
        }
        let message = "Isolated \(isolated) unreadable payload\(isolated == 1 ? "" : "s")."
        return HealthAutoFixResult(isolatedCount: isolated, failedCount: failed, message: message)
    }
}
