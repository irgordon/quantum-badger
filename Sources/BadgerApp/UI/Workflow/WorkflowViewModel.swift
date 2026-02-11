import SwiftUI
import Observation
import BadgerCore
import BadgerRuntime
import SwiftData

@Observable
@MainActor
public final class WorkflowViewModel {
    
    // MARK: - State
    
    /// The current plan being executed or reviewed.
    public var plan: WorkflowPlan?
    
    /// True if the agent is currently "thinking" or "working".
    public var isBusy: Bool = false
    
    /// Any error encountered during the process.
    public var error: Error?
    
    // MARK: - Dependencies
    
    private let orchestrator: Orchestrator
    private let historyService: HistoryService
    
    // MARK: - Init
    
    public init(orchestrator: Orchestrator, historyService: HistoryService) {
        self.orchestrator = orchestrator
        self.historyService = historyService
        
        // Load recent plan on launch?
        // For now, we start fresh, but future iterations could load 
        // self.plan = historyService.fetchRecent().first
    }
    
    // MARK: - User Intent
    
    /// Called when the user types a request (e.g., "Research Swift 6").
    public func submit(intent: String) {
        guard !intent.isEmpty else { return }
        
        Task {
            isBusy = true
            defer { isBusy = false }
            
            do {
                // 1. Ask Orchestrator to build/refine the plan
                let newPlan = try await orchestrator.process(intent: intent)
                
                // 2. Update UI
                self.plan = newPlan
                
                // 3. Start execution loop automatically
                await runExecutionLoop()
                
            } catch {
                self.error = error
            }
        }
    }
    
    /// Called when the user taps "Approve" on a paused step.
    public func approve(stepID: UUID) {
        guard var currentPlan = plan else { return }
        
        // Find the step and mark it as pending (ready to run)
        guard let index = currentPlan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        
        // Update state to remove the "Awaiting Approval" blocker
        var step = currentPlan.steps[index]
        step.status = .pending
        currentPlan.steps[index] = step
        self.plan = currentPlan
        
        // Resume execution
        Task {
            await runExecutionLoop()
        }
    }
    
    // MARK: - Execution Engine
    
    /// Iterates through the plan, executing valid steps until blocked or finished.
    private func runExecutionLoop() async {
        guard var currentPlan = plan else { return }
        
        // SAVE INITIAL STATE
        historyService.save(currentPlan)
        
        isBusy = true
        defer { isBusy = false }
        
        // Loop until we can't do anything more
        // We use a while loop that re-evaluates 'plan' each iteration to ensure we have fresh state
        while let nextStepIndex = plan?.steps.firstIndex(where: { $0.status == .pending }) {
            
            // Re-grab the plan to safe-guard against async mutation overlap (though @MainActor protects us mostly)
            guard var activePlan = self.plan else { break }
            var step = activePlan.steps[nextStepIndex]
            
            // A. Check Approval
            if step.requiresApproval {
                step.status = .awaitingApproval
                activePlan.steps[nextStepIndex] = step
                self.plan = activePlan
                // Save state before pausing
                historyService.save(activePlan)
                return // STOP here, wait for user.
            }
            
            // B. Mark Running
            step.status = .running
            // Initialize an empty result so the UI has something to show
            step.result = ToolResult(
               id: UUID(),
               stepId: step.id,
               toolName: step.tool,
               rawOutput: "", // Start empty
               succeeded: true // Assumed success until failure
            )
            activePlan.steps[nextStepIndex] = step
            self.plan = activePlan
            
            // C. Execute (Stream)
            var fullOutput = ""
            var failed = false
            
            do {
                // Connect to the stream
                let stream = await orchestrator.runStream(step: step)
                
                for try await chunk in stream {
                    fullOutput += chunk
                    
                    // REAL-TIME UI UPDATE
                    // We recreate the result struct with the growing string
                    step.result = ToolResult(
                        id: step.result?.id ?? UUID(), // Preserve ID if possible
                        stepId: step.id,
                        toolName: step.tool,
                        rawOutput: fullOutput, // The growing text
                        succeeded: true,
                        finishedAt: Date() // Keeps updating timestamp
                    )
                    activePlan.steps[nextStepIndex] = step
                    self.plan = activePlan // Forces View Redraw
                }
                
                // Stream Finished Successfully
                step.status = .completed
                
            } catch {
                failed = true
                step.status = .failed
                step.result = ToolResult(
                   id: step.result?.id ?? UUID(),
                   stepId: step.id,
                   toolName: step.tool,
                   rawOutput: fullOutput + "\n\nError: \(error.localizedDescription)",
                   succeeded: false,
                   finishedAt: Date()
                )
            }
            
            // D. Update UI State (Final)
            activePlan.steps[nextStepIndex] = step
            self.plan = activePlan
            
            // SAVE PROGRESS TO DISK
            historyService.save(activePlan)
            
            // If failed, maybe stop? For now, we continue or break based on logic.
            if failed {
                break // Stop on error
            }
        }
        
        // MARK PLAN COMPLETE (if all done)
        if let finalPlan = self.plan {
             // Simple check: if no pending/running/failed/approval steps
             let allDone = finalPlan.steps.allSatisfy { $0.status == .completed || $0.status == .skipped }
             if allDone {
                 var completedPlan = finalPlan
                 completedPlan.completedAt = Date()
                 self.plan = completedPlan
                 historyService.save(completedPlan)
             }
        }
    }
}
