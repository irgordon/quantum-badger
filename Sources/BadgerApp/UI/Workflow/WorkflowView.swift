import SwiftUI
import BadgerCore

struct WorkflowView: View {
    let plan: WorkflowPlan
    
    // In a real app, you'd pass an action handler or ViewModel here
    var onApproveStep: (UUID) -> Void
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Text("Intent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(plan.intent)
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }
            
            Section("Execution Plan") {
                ForEach(plan.steps) { step in
                    WorkflowStepRow(step: step) {
                        onApproveStep(step.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Agent Operation")
    }
}

#Preview {
    // 1. Create Dummy Data
    let step1 = WorkflowStep(
        title: "Search for info",
        tool: "web.search",
        input: ToolCallPayload(toolName: "web.search", rawArguments: "{}"),
        requiresApproval: false,
        status: .completed,
        result: ToolResult(stepId: UUID(), toolName: "web.search", rawOutput: "{\"results\": 42}", succeeded: true)
    )
    
    let step2 = WorkflowStep(
        title: "Write to file",
        tool: "fs.write",
        input: ToolCallPayload(toolName: "fs.write", rawArguments: "{}"),
        requiresApproval: true,
        status: .awaitingApproval
    )
    
    let step3 = WorkflowStep(
        title: "Summarize",
        tool: "ai.summarize",
        input: ToolCallPayload(toolName: "ai.summarize", rawArguments: "{}"),
        requiresApproval: false,
        status: .pending
    )
    
    let plan = WorkflowPlan(
        intent: "Research quantum physics and save a summary",
        steps: [step1, step2, step3]
    )
    
    // 2. Render View
    return NavigationStack {
        WorkflowView(plan: plan) { stepId in
            print("User approved step: \(stepId)")
        }
    }
}
