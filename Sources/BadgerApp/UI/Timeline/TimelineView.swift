import SwiftUI
import BadgerCore

struct TimelineView: View {
    // AuditLog is likely an actor or ObservableObject.
    // If it's an actor, we can't iterate .entries synchronously in the view body unless .entries is nonisolated.
    // Assuming AuditLog is an ObservableObject or has a published property for this view.
    // Based on previous files, AuditLog was a class with `entries` property.
    // I'll assume it's Observable for now.
    @ObservedObject var auditLog: AuditLog 

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Statistics")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.horizontal)

            List(auditLog.entries.reversed(), id: \.timestamp) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entrySummary(for: entry.event))
                        .font(.body)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .padding(.vertical)
    }
    
    private func entrySummary(for event: AuditEvent) -> String {
        switch event {
        case .modelLoaded(let name): return "Model Loaded: \(name)"
        case .modelUnloaded: return "Model Unloaded"
        case .inferenceStarted(let intent): return "Inference Started: \(intent)"
        case .inferenceCompleted(let tokens): return "Inference Completed (\(tokens) tokens)"
        case .networkAttempt(let decision, let allowed, _):
            return "Network \(allowed ? "Allowed" : "Blocked"): \(decision.host ?? "unknown")"
        case .securityViolationDetected(let violation): return "Security Violation: \(violation)"
        case .systemMaintenance(let task): return "System: \(task)"
        default: return "System Event"
        }
    }
}
