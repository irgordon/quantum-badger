import SwiftUI
import BadgerCore
import BadgerRuntime

struct PlanView: View {
    let plan: WorkflowPlan
    let results: [UUID: ToolResult]
    let exportNotice: String?
    let runStep: (WorkflowStep) -> Void
    let runAll: () -> Void
    let exportPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.headline)
                Spacer()
                Button("Run Plan") {
                    runAll()
                }
                .buttonStyle(.borderedProminent)
                Button("Export Report") {
                    exportPlan()
                }
                .buttonStyle(.bordered)
            }
            if let exportNotice {
                Text(exportNotice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(plan.steps) { step in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Action: \(step.tool)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let result = results[step.id] {
                            Text(result.succeeded ? "Completed" : "Blocked")
                                .font(.caption)
                                .foregroundColor(result.succeeded ? .green : .red)
                            if let message = result.normalizedMessages?.first {
                                SecurityStatusBadge(message: message)
                            }
                        }
                    }
                    Spacer()
                    Button(step.requiresApproval ? "Approve and Run" : "Run Step") {
                        runStep(step)
                    }
                    .buttonStyle(.bordered)
                }
                Divider()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
    }
}
