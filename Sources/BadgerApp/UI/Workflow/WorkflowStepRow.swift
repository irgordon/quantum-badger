import SwiftUI
import BadgerCore

struct WorkflowStepRow: View {
    let step: WorkflowStep
    let onApprove: () -> Void
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // 1. Status Icon
                StatusIcon(status: step.status)
                    .frame(width: 24)
                    .padding(.top, 2)
                
                VStack(alignment: .leading) {
                    // 2. Title & Tool Name
                    Text(step.title)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(step.tool)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                    
                    // 3. Approval Button
                    if step.status == .awaitingApproval {
                        Button(action: onApprove) {
                            Label("Approve Execution", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                }
                
                Spacer()
                
                // 4. Time / Duration (Placeholder logic)
                if let result = step.result {
                    Text(result.finishedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 5. Output Viewer (Collapsible)
            if let result = step.result {
                DisclosureGroup(
                    isExpanded: $isExpanded,
                    content: {
                        Text(result.rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    label: {
                        Text(result.succeeded ? "View Output" : "View Error")
                            .font(.caption)
                            .foregroundStyle(result.succeeded ? .secondary : .red)
                    }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// Helper View for the icon
struct StatusIcon: View {
    let status: WorkflowStepStatus
    
    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .awaitingApproval:
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
        }
    }
}
