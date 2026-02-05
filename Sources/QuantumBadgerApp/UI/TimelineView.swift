import SwiftUI
import QuantumBadgerRuntime

struct TimelineView: View {
    let auditLog: AuditLog

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(.title)
                .fontWeight(.semibold)

            List(auditLog.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.event.summary)
                        .font(.body)
                    Text(entry.event.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}
