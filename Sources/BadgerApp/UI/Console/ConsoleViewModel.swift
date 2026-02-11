import SwiftUI
import BadgerCore
import BadgerRuntime
import Observation

@MainActor
@Observable
final class ConsoleViewModel {
    // MARK: - Dependencies
    let orchestrator: Orchestrator
    private let toolApprovalManager: ToolApprovalManager
    private let policy: PolicyEngine
    private let executionRecoveryManager: ExecutionRecoveryManager
    let conversationHistoryStore: ConversationHistoryStore
    private let memoryManager: MemoryManager
    let vaultStore: VaultStore
    private let auditLog: AuditLog
    var toolLimitsStore: ToolLimitsStore

    // MARK: - UI State
    var prompt: String = ""
    var activePlan: WorkflowPlan?
    var results: [UUID: ToolResult] = [:]
    var searchMatches: [LocalSearchMatch] = []
    var assistantResponse: String = ""
    var assistantMessage: QuantumMessage?
    var isGenerating: Bool = false
    
    // Notices & Overlays
    var searchNotice: String?
    var saveNotice: String?
    var exportNotice: String?
    var compactionNotice: String?
    
    // Complex State
    var webCards: [WebScoutResult] = []
    var webCardsNotice: String?
    var webCardsMessage: QuantumMessage?
    var localSearchMessage: QuantumMessage?
    var conversationEntries: [ConversationEntry] = []
    
    // Flags
    var allowPublicCloudForThisRequest: Bool = false
    var isSaveLocationPickerPresented: Bool = false
    
    // File Saver State
    var saveLocationName: String = ""
    var saveContents: String = ""
    var saveLocationReference: VaultReference?

    private var generationTask: Task<Void, Never>?

    init(appState: AppState) {
        self.orchestrator = appState.runtimeCapabilities.orchestrator
        self.toolApprovalManager = appState.securityCapabilities.toolApprovalManager
        self.policy = appState.securityCapabilities.policy
        self.executionRecoveryManager = appState.executionRecoveryManager
        self.conversationHistoryStore = appState.conversationHistoryStore
        self.memoryManager = appState.storageCapabilities.memoryManager
        self.vaultStore = appState.storageCapabilities.vaultStore
        self.auditLog = appState.storageCapabilities.auditLog
        self.toolLimitsStore = appState.toolLimitsStore
    }

    // MARK: - Actions

    func submitPrompt() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let allowPublic = allowPublicCloudForThisRequest
        allowPublicCloudForThisRequest = false // Reset flag
        
        await appendConversationEntry(ConversationEntry(content: trimmed, source: "Console", role: .user))
        
        stopGeneration()
        assistantResponse = ""
        assistantMessage = nil
        isGenerating = true
        
        generationTask = Task {
            do {
                let stream = await orchestrator.streamResponse(
                    for: trimmed,
                    hint: ExecutionHint(allowPublicCloud: allowPublic)
                )
                
                for try await message in stream {
                    self.assistantResponse += message.content
                    self.assistantMessage = message
                }
                
                let normalized = await IntentResultNormalizer.shared.normalize(
                    rawText: assistantResponse, kind: .text, source: .system, toolName: "assistant.response"
                )
                
                self.assistantMessage = normalized.message
                self.isGenerating = false
                
                await appendConversationEntry(ConversationEntry(
                    content: assistantResponse,
                    source: normalized.message.toolName ?? "assistant",
                    role: .assistant
                ))
            } catch {
                if error is CancellationError {
                    assistantResponse = "Stopped. You can continue when ready."
                } else {
                    assistantResponse = "I couldn't complete that right now. Please try again."
                }
                isGenerating = false
            }
        }
    }
    
    func makePlan() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let plan = await orchestrator.proposePlan(for: trimmed)
        self.activePlan = plan
        executionRecoveryManager.startGoal(plan.intent, plan: plan.steps)
        await updateGoalSnapshot(plan: plan)
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        Task { await orchestrator.cancelActiveGeneration() }
        isGenerating = false
    }

    // MARK: - Tool Execution Logic
    
    func runLocalSearch() async {
        let currentPrompt = prompt
        
        await toolApprovalManager.requestApproval(
            policy: policy,
            toolName: "local.search",
            input: ["query": currentPrompt]
        ) { [weak self] approvalToken in
            guard let self else { return }
            await self.executeLocalSearch(query: currentPrompt, token: approvalToken)
        }
    }
    
    private func executeLocalSearch(query: String, token: String?) async {
         let request = ToolRequest(
            id: UUID(),
            toolName: "local.search",
            input: inputWithApprovalToken(["query": query], token),
            vaultReferences: nil,
            requestedAt: Date()
        )
        
        let step = WorkflowStep(id: request.id, title: "Local search", tool: request.toolName, input: request.input, requiresApproval: false)
        
        await appendConversationEntry(ConversationEntry(content: "Tool call local.search", source: "local.search", role: .toolCall, toolCallID: request.id))

        let result = await orchestrator.run(step: step)
        let decoded = decodeMatches(from: result)
        
        self.results[request.id] = result
        if let decoded { self.searchMatches = decoded }
        self.searchNotice = searchNoticeText(from: result)
        self.localSearchMessage = result.normalizedMessages?.first(where: { $0.kind == .localSearchResults })
        
        SystemSearchDonationManager.donate(messages: result.normalizedMessages ?? [])
        
        await appendConversationEntry(ConversationEntry(content: toolResultContent(from: result), source: result.toolName, role: .toolResult, toolCallID: request.id))
    }
    
    func writeSecureFile() async {
        guard let reference = saveLocationReference else { return }
        
        let request = ToolRequest(
            id: UUID(),
            toolName: "filesystem.write",
            input: ["pathRef": reference.label, "contents": saveContents],
            vaultReferences: [reference],
            requestedAt: Date()
        )
        
        let step = WorkflowStep(id: request.id, title: "Write file", tool: request.toolName, input: request.input, requiresApproval: true)
        
        await toolApprovalManager.requestApproval(policy: policy, toolName: step.tool, input: step.input) { [weak self] approvalToken in
            guard let self else { return }
            
            var updatedStep = step
            updatedStep.input = inputWithApprovalToken(step.input, approvalToken)
            
            await self.appendConversationEntry(ConversationEntry(content: "Tool call filesystem.write", source: "filesystem.write", role: .toolCall, toolCallID: updatedStep.id))
            
            let result = await self.orchestrator.run(step: updatedStep)
            self.results[step.id] = result
            
            await self.appendConversationEntry(ConversationEntry(content: self.toolResultContent(from: result), source: result.toolName, role: .toolResult, toolCallID: updatedStep.id))
        }
    }
    
    // MARK: - Plan Execution

    func runStep(_ step: WorkflowStep) async {
        await executeStep(step)
    }
    
    func runPlan() async {
        guard let plan = activePlan else { return }
        for step in plan.steps {
            // Check if already completed?
            if let result = results[step.id], result.succeeded { continue }
            await executeStep(step)
        }
    }
    
    func exportPlan() {
        guard let plan = activePlan else { return }
        saveContents = "Plan:\n"
        for step in plan.steps {
            saveContents += "- \(step.title) (\(step.tool))\n"
            if let result = results[step.id] {
                saveContents += "  Result: \(result.succeeded ? "Success" : "Failure")\n"
            }
        }
        saveLocationName = "PlanReport.txt"
        isSaveLocationPickerPresented = true
    }

    private func executeStep(_ step: WorkflowStep) async {
        if step.requiresApproval {
             await toolApprovalManager.requestApproval(
                 policy: policy,
                 toolName: step.tool,
                 input: step.input
             ) { [weak self] approvalToken in
                 guard let self else { return }
                 var updatedStep = step
                 updatedStep.input = inputWithApprovalToken(step.input, approvalToken)
                 await self.execute(step: updatedStep)
             }
        } else {
             await execute(step: step)
        }
    }
    
    private func execute(step: WorkflowStep) async {
         await appendConversationEntry(ConversationEntry(content: "Running \(step.title)...", source: step.tool, role: .toolCall, toolCallID: step.id))
         let result = await orchestrator.run(step: step)
         self.results[step.id] = result
         
         if result.toolName == "web.scout", let cards = decodeWebCards(from: result) {
             self.webCards = cards
             self.webCardsNotice = webCardsNotice(from: result)
             self.webCardsMessage = result.normalizedMessages?.first(where: { $0.kind == .webScoutResult })
         }
         
         await appendConversationEntry(ConversationEntry(content: toolResultContent(from: result), source: result.toolName, role: .toolResult, toolCallID: step.id))
    }

    // MARK: - History & Compaction
    
    func loadConversationHistory() async {
        conversationEntries = await conversationHistoryStore.list()
        if let compaction = await conversationHistoryStore.lastCompactionRecord() {
             if Date().timeIntervalSince(compaction.occurredAt) < 10 {
                compactionNotice = "Context optimized to keep things fast."
                scheduleCompactionNoticeClear()
            }
        }
    }
    
    private func appendConversationEntry(_ entry: ConversationEntry) async {
        _ = await conversationHistoryStore.append(entry)
        await loadConversationHistory()
    }
    
    private func scheduleCompactionNoticeClear() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.compactionNotice = nil
        }
    }
    
    private func updateGoalSnapshot(plan: WorkflowPlan) async {
        let totalSteps = max(1, plan.steps.count)
        var completedSteps = 0
        var failedSteps = 0
        for step in plan.steps {
            guard let result = results[step.id] else { continue }
            if result.succeeded {
                completedSteps += 1
            } else {
                failedSteps += 1
            }
        }
        // Implementation stub for TaskPlanner update if needed
    }
    
// MARK: - Decoding Helpers

private func decodeMatches(from result: ToolResult) -> [LocalSearchMatch]? {
    guard let jsonString = result.output["matches"],
          let data = jsonString.data(using: .utf8) else { return nil }
    
    let decoder = JSONDecoder()
    return try? decoder.decode([LocalSearchMatch].self, from: data)
}

private func decodeWebCards(from result: ToolResult) -> [WebScoutResult]? {
    guard let cardsJson = result.output["cards"],
          let data = cardsJson.data(using: .utf8) else { return nil }
    
    let decoder = JSONDecoder()
    return try? decoder.decode([WebScoutResult].self, from: data)
}

private func searchNoticeText(from result: ToolResult) -> String? {
    guard result.toolName == "local.search" else { return nil }
    guard result.output["truncated"] == "true" else { return nil }
    let count = result.output["count"] ?? "some"
    let stopReason = result.output["stopReason"]
    if stopReason == "cancelled" {
        return "Search stopped early. Showing the first \(count) matches we found."
    }
    return "Showing first \(count) matches. Some results were hidden to keep things fast."
}

private func webCardsNotice(from result: ToolResult) -> String? {
    guard result.toolName == "web.scout" else { return nil }
    if result.output["cards"] != nil,
       result.output["cardsSignature"] != nil,
       decodeWebCards(from: result) == nil {
        return "Web results couldn’t be verified. Try again."
    }
    if result.succeeded {
        return "Here are the web results I found."
    }
    return "Web results couldn’t be loaded. Try again or adjust your web settings."
}

private func toolResultContent(from result: ToolResult) -> String {
    if result.succeeded {
        if let note = result.output["result"] ?? result.output["status"] ?? result.output["note"] {
            return note
        }
        return "Tool \(result.toolName) completed."
    }
    let reason = result.output["error"] ?? "Unknown error."
    return "Tool \(result.toolName) failed: \(reason)"
}
}
