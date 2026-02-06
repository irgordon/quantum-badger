import SwiftUI
import QuantumBadgerRuntime

struct NetworkAuditView: View {
    let auditLog: AuditLog
    @State private var healthReport: PersistenceHealthReport?
    @State private var isHealthCheckRunning: Bool = false
    @State private var healthFixMessage: String?
    @State private var healthFixTask: Task<Void, Never>?

    private var redactionEntries: [AuditEntry] {
        auditLog.entries.filter { $0.event.kind == .networkPayloadRedacted }
            .sorted { $0.event.timestamp > $1.event.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Payload Redactions")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Persistence Health") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Run Health Check") {
                        guard !isHealthCheckRunning else { return }
                        isHealthCheckRunning = true
                        healthFixMessage = nil
                        Task {
                            healthReport = await PersistenceHealthCheck.run(auditLog: auditLog)
                            isHealthCheckRunning = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isHealthCheckRunning)

                    if isHealthCheckRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Health check in progress…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let report = healthReport {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Audit entries: \(report.auditEntryCount)")
                                .font(.caption)
                            Text("Payload files: \(report.payloadFileCount) (referenced \(report.referencedPayloadCount))")
                                .font(.caption)
                                .foregroundColor(report.payloadCountMatches ? .secondary : .orange)
                            Text(report.auditChainValid ? "Audit chain verified." : "Audit chain mismatch detected.")
                                .font(.caption)
                                .foregroundColor(report.auditChainValid ? .secondary : .red)
                            if !report.payloadHashCombined.isEmpty {
                                Text("Payload hash: \(report.payloadHashCombined.prefix(12))…")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if report.payloadUnreadableCount > 0 {
                                Text("Unreadable payloads: \(report.payloadUnreadableCount)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        if report.payloadUnreadableCount > 0 {
                            Button("Health Auto-Fix") {
                                healthFixTask?.cancel()
                                healthFixTask = Task {
                                    let result = await HealthAutoFixer.run(auditLog: auditLog, report: report)
                                    await MainActor.run {
                                        healthFixMessage = result.message
                                        healthFixTask = nil
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            if healthFixTask != nil {
                                Button("Cancel Auto-Fix") {
                                    healthFixTask?.cancel()
                                    healthFixTask = nil
                                    healthFixMessage = "Auto-fix cancelled."
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if let healthFixMessage {
                            Text(healthFixMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if redactionEntries.isEmpty {
                Text("No redacted payloads yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(redactionEntries) { entry in
                    NetworkRedactionRow(entry: entry, auditLog: auditLog)
                }
                .frame(minHeight: 320)
            }
        }
        .padding()
    }
}

private struct NetworkRedactionRow: View {
    let entry: AuditEntry
    let auditLog: AuditLog
    @State private var beforeText: String = "Loading…"
    @State private var afterText: String = "Loading…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.event.summary)
                .font(.headline)
            Text(entry.event.timestamp.formatted(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(beforeText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .privacySensitive()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("After")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(afterText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .privacySensitive()
                }
            }

            if entry.event.payloadTruncated == true {
                Text("Preview shortened for safety.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .task {
            await loadPayloads()
        }
    }

    @MainActor
    private func loadPayloads() async {
        let before = await loadPayload(ref: entry.event.payloadBeforeRef, fallback: entry.event.payloadBefore)
        let after = await loadPayload(ref: entry.event.payloadAfterRef, fallback: entry.event.payloadAfter)
        beforeText = before
        afterText = after
    }

    private func loadPayload(ref: String?, fallback: String?) async -> String {
        if let ref {
            let payload = await Task.detached(priority: .utility) { auditLog.payloadString(for: ref) }.value
            if let payload {
                return prettyJSON(payload) ?? payload
            }
        }
        if let fallback {
            return prettyJSON(fallback) ?? fallback
        }
        return "Unavailable"
    }

    private func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(json),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
