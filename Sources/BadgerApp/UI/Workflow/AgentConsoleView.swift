import SwiftUI
import BadgerCore
import BadgerRuntime
import SwiftData

struct AgentConsoleView: View {
    @State private var viewModel: WorkflowViewModel
    @State private var promptText: String = ""
    
    // We instantiate the history service here, or it could be passed in
    // This allows the view to own the persistence lifecycle for this screen
    init(orchestrator: Orchestrator) {
        let historyService = HistoryService()
        _viewModel = State(initialValue: WorkflowViewModel(
            orchestrator: orchestrator,
            historyService: historyService
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // 1. The Plan List
                if let plan = viewModel.plan {
                    WorkflowView(plan: plan) { stepID in
                        viewModel.approve(stepID: stepID)
                    }
                } else {
                    ContentUnavailableView(
                        "Ready to Help",
                        systemImage: "sparkles",
                        description: Text("Enter a goal to generate a plan.")
                    )
                }
                
                Spacer()
                
                // 2. Input Area
                HStack {
                    TextField("What should I do?", text: $promptText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isBusy)
                        .onSubmit {
                            submit()
                        }
                    
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Go") {
                            submit()
                        }
                        .disabled(promptText.isEmpty)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Agent Console")
        }
    }
    
    private func submit() {
        guard !promptText.isEmpty else { return }
        viewModel.submit(intent: promptText)
        promptText = ""
    }
}
