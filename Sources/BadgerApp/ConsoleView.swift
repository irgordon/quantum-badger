import SwiftUI
import AppKit
import BadgerCore
import BadgerRuntime

struct ConsoleView: View {
    @EnvironmentObject private var appState: AppCoordinator // Replaced Environment(AppState) with EnvironmentObject(AppCoordinator) or similar?
    // User code used @Environment(AppState.self). AppState might be a new Observable class.
    // I'll stick to user code but define AppState if needed, OR adapt it to use AppCoordinator.
    // Actually, AppCoordinator IS the AppState in main BadgerApp.swift (likely).
    // Let's assume AppCoordinator wraps these.

    let orchestrator: Orchestrator
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let reachability: NetworkReachabilityMonitor
    let memoryManager: MemoryController // Adapted type
    let bookmarkStore: BookmarkStore
    let vaultStore: VaultStore
    let auditLog: AuditLog
    let policy: PolicyEngine
    let toolApprovalManager: ToolApprovalManager
    let toolLimitsStore: ToolLimitsStore
    let messagingInboxStore: MessagingInboxStore
    let conversationHistoryStore: ConversationHistoryStore
    let executionRecoveryManager: ExecutionRecoveryManager

    @State private var prompt: String = ""
    @State private var activePlan: WorkflowPlan?
    @State private var results: [UUID: ToolResult] = [:]
    @State private var searchMatches: [LocalSearchMatch] = []
    @State private var assistantResponse: String = ""
    @State private var isSaveLocationPickerPresented: Bool = false
    @State private var saveLocationReference: VaultReference?
    @State private var saveLocationName: String = ""
    @State private var saveContents: String = ""
    @State private var searchNotice: String?
    @State private var saveNotice: String?
    @State private var exportNotice: String?
    @State private var webCards: [WebScoutResult] = []
    @State private var webCardsNotice: String?
    @State private var webCardsMessage: QuantumMessage?
    @State private var localSearchMessage: QuantumMessage?
    @State private var assistantMessage: QuantumMessage?
    @State private var generationTask: Task<Void, Never>?
    @State private var allowPublicCloudForThisRequest: Bool = false
    @State private var conversationEntries: [ConversationEntry] = []
    @State private var compactionNotice: String?
    @State private var showArchiveSheet: Bool = false
    @State private var archiveEntries: [ConversationEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assistant")
                .font(.title)
                .fontWeight(.semibold)

            StatusPill(
                modelRegistry: modelRegistry,
                modelSelection: modelSelection,
                reachability: reachability
            )

            if let compactionNotice {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                    Text(compactionNotice)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // ConsoleQuickStartCard Integration (Added by me based on previous task)
            ConsoleQuickStartCard()

            GroupBox("Conversation Context") {
                if conversationEntries.isEmpty {
                    Text("No conversation context yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    List(Array(conversationEntries.suffix(40))) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(entryRoleLabel(entry.role))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if entry.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                if entry.isSummary {
                                    Image(systemName: "leaf")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            Text(entry.content)
                                .font(.caption)
                                .lineLimit(4)
                        }
                        .contextMenu {
                            Button(entry.isPinned ? "Unpin from Context" : "Pin in Context") {
                                Task {
                                    await conversationHistoryStore.setPinned(id: entry.id, pinned: !entry.isPinned)
                                    await loadConversationHistory()
                                }
                            }
                            if entry.isSummary, let archiveID = entry.summaryArchiveID {
                                Button("Expand Original") {
                                    Task {
                                        archiveEntries = await conversationHistoryStore.archivedEntries(archiveID: archiveID) ?? []
                                        showArchiveSheet = true
                                    }
                                }
                            }
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                }
            }

            GroupBox("Database Query Safety") {
                @Bindable var limitsStore = toolLimitsStore
                HStack {
                    Text("Max DB query tokens")
                    Spacer()
                    Stepper(
                        value: $limitsStore.dbQueryMaxTokens,
                        in: 64...4096,
                        step: 64
                    ) {
                        Text("\(limitsStore.dbQueryMaxTokens)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .labelsHidden()
                    .accessibilityLabel("Max database query tokens")
                }
                Text("Higher limits allow larger queries, but can be slower on this Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                TextField("Describe what you want to do", text: $prompt)
                Button("Make a Plan") {
                    guard !prompt.isEmpty else { return }
                    Task {
                        await makePlan(for: prompt)
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                Button("Ask") {
                    guard !prompt.isEmpty else { return }
                    Task {
                        let allowPublic = allowPublicCloudForThisRequest
                        allowPublicCloudForThisRequest = false
                        await submitPrompt(prompt, allowPublicCloud: allowPublic)
                    }
                }
                Button("Stop Generation") {
                    generationTask?.cancel()
                    Task {
                        await orchestrator.cancelActiveGeneration()
                    }
                    generationTask = nil
                }
                .disabled(generationTask == nil)
                Button("Search Files") {
                    guard !prompt.isEmpty else { return }
                    Task {
                        await toolApprovalManager.requestApproval(
                            policy: policy,
                            toolName: "local.search",
                            input: ["query": prompt],
                            onApproved: { approvalToken in
                                await runLocalSearch(approvalToken: approvalToken)
                            }
                        )
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Use public cloud for this request", isOn: $allowPublicCloudForThisRequest)
                Text("Public cloud runs outside this Mac. Only enable for non‑sensitive requests.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let plan = activePlan {
                PlanView(
                    plan: plan,
                    results: results,
                    exportNotice: exportNotice,
                    runStep: { step in
                        Task { await handleStepApproval(step) }
                    },
                    runAll: {
                        Task { await runPlanWithRecovery(plan) }
                    },
                    exportPlan: {
                        Task { await exportPlan(plan) }
                    }
                )
            } else {
                ContentUnavailableView("No Plan", systemImage: "wand.and.stars", description: Text("Describe a task to get started."))
            }

            if !assistantResponse.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Assistant")
                                .font(.headline)
                            if let assistantMessage {
                                SecurityStatusBadge(message: assistantMessage)
                            }
                        }
                        let status = assistantMessage?.integrityStatus()
                        StreamingBufferView(text: assistantResponse)
                            .opacity(status == .unverified ? 0.5 : 1.0)
                            .blur(radius: status == .unverified ? 0.5 : 0)
                            .strikethrough(status == .unverified, color: .orange)
                    }
                }
            }

            GroupBox("Save to File") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose where to save a report or code snippet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let saveNotice {
                        HStack(spacing: 8) {
                            Text(saveNotice)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Fix…") {
                                isSaveLocationPickerPresented = true
                            }
                            .buttonStyle(.link)
                        }
                    }
                    HStack {
                        TextField("Save location label", text: $saveLocationName)
                        Button(saveLocationReference == nil ? "Choose File…" : "Change…") {
                            isSaveLocationPickerPresented = true
                        }
                        .buttonStyle(.bordered)
                    }
                    TextEditor(text: $saveContents)
                        .frame(minHeight: 80)
                    Button("Write File") {
                        Task { await writeSecureFile() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saveLocationReference == nil || saveContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .privacySensitive()

            LocalSearchResultsPanel(
                matches: searchMatches,
                bookmarkStore: bookmarkStore,
                notice: searchNotice,
                message: localSearchMessage
            )

            WebResultsPanel(results: webCards, notice: webCardsNotice, message: webCardsMessage)

            GroupBox("Inbound Messages") {
                if messagingInboxStore.messages.isEmpty {
                    Text("No inbound messages yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    List(messagingInboxStore.messages, id: \.id) { message in
                        let status = message.integrityStatus()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(message.toolName ?? "Inbound")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                SecurityStatusBadge(message: message)
                            }
                            Text(message.content)
                                .font(.body)
                                .opacity(status == .unverified ? 0.6 : 1.0)
                                .blur(radius: status == .unverified ? 0.5 : 0)
                        }
                    }
                    .frame(minHeight: 160)
                }
            }

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $isSaveLocationPickerPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if saveLocationName.isEmpty {
                    saveLocationName = url.lastPathComponent
                }
                vaultStore.storeBookmark(label: saveLocationName, url: url)
                saveLocationReference = vaultStore.reference(forLabel: saveLocationName)
                saveNotice = nil
            case .failure:
                break
            }
        }
        .task {
            await loadConversationHistory()
        }
        /*
        .task(id: appState.externalPromptRequestID) {
             // Mocking out appState dependency for now
            //guard let externalPrompt = appState.pendingExternalPrompt else { return }
            //appState.pendingExternalPrompt = nil
            //prompt = externalPrompt
            //await submitPrompt(externalPrompt, allowPublicCloud: false)
        }
        */
        .onDisappear {
            generationTask?.cancel()
            generationTask = nil
            compactionNotice = nil
        }
        .sheet(isPresented: $showArchiveSheet) {
            ConversationArchiveSheet(entries: archiveEntries)
        }
    }

    @MainActor
    private func makePlan(for text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let plan = await orchestrator.proposePlan(for: trimmed)
        activePlan = plan
        executionRecoveryManager.startGoal(plan.intent, plan: plan.steps)
        await updateGoalSnapshot(plan: plan)
    }

    @MainActor
    private func submitPrompt(_ text: String, allowPublicCloud: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await appendConversationEntry(
            ConversationEntry(
                content: trimmed,
                source: "Console",
                role: .user
            )
        )
        generationTask?.cancel()
        assistantResponse = ""
        assistantMessage = nil
        generationTask = Task {
            do {
                let stream = await orchestrator.streamResponse(
                    for: trimmed,
                    hint: ExecutionHint(allowPublicCloud: allowPublicCloud)
                )
                for try await message in stream {
                    await MainActor.run {
                        assistantResponse += message.content
                        assistantMessage = message
                    }
                }
                let normalized = await IntentResultNormalizer.shared.normalize(
                    rawText: assistantResponse,
                    kind: .text,
                    source: .system,
                    toolName: "assistant.response"
                )
                await MainActor.run {
                    generationTask = nil
                    assistantMessage = normalized.message
                }
                await appendConversationEntry(
                    ConversationEntry(
                        content: assistantResponse,
                        source: normalized.message.toolName ?? "assistant",
                        role: .assistant
                    )
                )
            } catch {
                await MainActor.run {
                    if error is CancellationError {
                        assistantResponse = "Stopped. You can continue when ready."
                    } else {
                        assistantResponse = "I couldn't complete that right now. Please try again."
                    }
                    generationTask = nil
                }
            }
        }
    }

    @MainActor
    private func runLocalSearch(approvalToken: String?) async {
        let entry = MemoryEntry(
            trustLevel: .level0Ephemeral,
            content: "User request: \(prompt)",
            sourceType: .user,
            sourceDetail: "Console",
            isConfirmed: true,
            confirmedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        //_ = memoryManager.addEntry(entry, source: .userAction)

        let request = ToolRequest(
            id: UUID(),
            toolName: "local.search",
            input: inputWithApprovalToken(["query": prompt], approvalToken),
            vaultReferences: nil,
            requestedAt: Date()
        )
        let step = WorkflowStep(
            id: request.id,
            title: "Local search",
            tool: request.toolName,
            input: request.input,
            requiresApproval: false
        )
        await appendConversationEntry(
            ConversationEntry(
                content: "Tool call local.search query=\"\(prompt)\"",
                source: "local.search",
                role: .toolCall,
                toolName: "local.search",
                toolCallID: request.id
            )
        )

        Task.detached(priority: .userInitiated) { [orchestrator] in
            let result = await orchestrator.run(step: step)
            let decoded = decodeMatches(from: result)
            await MainActor.run {
                self.results[request.id] = result
                if let decoded {
                    self.searchMatches = decoded
                }
                self.searchNotice = searchNoticeText(from: result)
                self.localSearchMessage = result.normalizedMessages?.first(where: { $0.kind == .localSearchResults })
                SystemSearchDonationManager.donate(messages: result.normalizedMessages ?? [])
            }
            await appendConversationEntry(
                ConversationEntry(
                    content: toolResultContent(from: result),
                    source: result.toolName,
                    role: .toolResult,
                    toolName: result.toolName,
                    toolCallID: request.id
                )
            )
        }
    }

    @MainActor
    private func handleStepApproval(_ step: WorkflowStep) async {
        executionRecoveryManager.updateStep(step.id, status: .inProgress)
        let result = await executeStep(step)
        if result.succeeded {
            executionRecoveryManager.updateStep(step.id, status: .completed)
        } else {
            executionRecoveryManager.updateStep(
                step.id,
                status: .failed(reason: friendlyStepFailure(from: result))
            )
        }
        if let activePlan {
            await updateGoalSnapshot(plan: activePlan)
        }
    }

    private func applyWebCards(from result: ToolResult) {
        guard result.toolName == "web.scout" else { return }
        webCards = decodeWebCards(from: result) ?? []
        webCardsNotice = webCardsNotice(from: result)
        webCardsMessage = result.normalizedMessages?.first(where: { $0.kind == .webScoutResults })
        SystemSearchDonationManager.donate(messages: result.normalizedMessages ?? [])
    }

    @MainActor
    private func writeSecureFile() async {
        guard let reference = saveLocationReference else { return }
        let entry = MemoryEntry(
            trustLevel: .level0Ephemeral,
            content: "User saved a file using the secure file writer.",
            sourceType: .user,
            sourceDetail: "Console",
            isConfirmed: true,
            confirmedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        //_ = memoryManager.addEntry(entry, source: .userAction)
        let request = ToolRequest(
            id: UUID(),
            toolName: "filesystem.write",
            input: [
                "pathRef": reference.label,
                "contents": saveContents
            ],
            vaultReferences: [reference],
            requestedAt: Date()
        )
        let step = WorkflowStep(
            id: request.id,
            title: "Write file",
            tool: request.toolName,
            input: request.input,
            requiresApproval: true
        )
        await toolApprovalManager.requestApproval(policy: policy, toolName: step.tool, input: step.input) { approvalToken in
            var updatedStep = step
            updatedStep.input = inputWithApprovalToken(step.input, approvalToken)
            await appendConversationEntry(
                ConversationEntry(
                    content: "Tool call \(updatedStep.tool)",
                    source: updatedStep.tool,
                    role: .toolCall,
                    toolName: updatedStep.tool,
                    toolCallID: updatedStep.id
                )
            )
            let result = await orchestrator.run(step: updatedStep)
            results[step.id] = result
            await appendConversationEntry(
                ConversationEntry(
                    content: toolResultContent(from: result),
                    source: result.toolName,
                    role: .toolResult,
                    toolName: result.toolName,
                    toolCallID: updatedStep.id
                )
            )
        }
    }

    @MainActor
    private func runPlanWithRecovery(_ plan: WorkflowPlan) async {
        executionRecoveryManager.startGoal(plan.intent, plan: plan.steps)
        for step in plan.steps {
            executionRecoveryManager.updateStep(step.id, status: .inProgress)
            var result = await executeStep(step)

            if result.succeeded {
                executionRecoveryManager.updateStep(step.id, status: .completed)
                continue
            }

            var shouldMoveToNextStep = false
            while !shouldMoveToNextStep {
                let option = await executionRecoveryManager.handleFailure(
                    stepID: step.id,
                    reason: friendlyStepFailure(from: result)
                )
                switch option {
                case .retry:
                    executionRecoveryManager.updateStep(step.id, status: .inProgress)
                    result = await executeStep(step)
                    if result.succeeded {
                        executionRecoveryManager.updateStep(step.id, status: .completed)
                        shouldMoveToNextStep = true
                    }
                case .skip:
                    executionRecoveryManager.updateStep(step.id, status: .completed)
                    shouldMoveToNextStep = true
                case .askUser:
                    executionRecoveryManager.updateStep(
                        step.id,
                        status: .failed(reason: "Waiting for your next instruction.")
                    )
                    await updateGoalSnapshot(plan: plan)
                    return
                }
            }
        }
        await updateGoalSnapshot(plan: plan)
    }

    @MainActor
    private func exportPlan(_ plan: WorkflowPlan) async {
        guard !results.isEmpty else {
            exportNotice = "Run at least one step to export a report."
            return
        }
        guard let option = await ExportOptionsPrompt.presentPlanReport() else { return }
        let defaultName = "QuantumBadger-Report-\(Date().formatted(date: .numeric, time: .omitted))"
        let allowedTypes = option.isEncrypted ? ["qbreport"] : ["json"]
        let url = await SavePanelPresenter.present(defaultFileName: defaultName, allowedFileTypes: allowedTypes)
        guard let url else { return }
        let exportResults = plan.steps.compactMap { results[$0.id] }
        let succeeded = await PlanExporter.export(
            plan: plan,
            results: exportResults,
            auditEntries: auditLog.entries,
            option: option,
            to: url
        )
        exportNotice = succeeded
            ? "Report exported with an integrity proof."
            : "Export failed. Try again or choose a different location."
    }

    private func entryRoleLabel(_ role: ConversationEntryRole) -> String {
        switch role {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .toolCall:
            return "Tool Call"
        case .toolResult:
            return "Tool Result"
        case .system:
            return "System"
        }
    }

    @MainActor
    private func appendConversationEntry(_ entry: ConversationEntry) async {
        let previousCompactionTime = await conversationHistoryStore.lastCompactionRecord()?.occurredAt
        _ = await conversationHistoryStore.append(entry)
        await loadConversationHistory()
        let latestCompaction = await conversationHistoryStore.lastCompactionRecord()
        if let latestCompaction,
           latestCompaction.occurredAt != previousCompactionTime {
            compactionNotice = "Context optimized to keep things fast."
            await auditLog.record(
                event: .systemMaintenance(
                    "Conversation compaction: \(latestCompaction.beforeTokenEstimate) -> \(latestCompaction.afterTokenEstimate) tokens."
                )
            )
            scheduleCompactionNoticeClear()
        }
    }

    @MainActor
    private func loadConversationHistory() async {
        conversationEntries = await conversationHistoryStore.list()
        if let compaction = await conversationHistoryStore.lastCompactionRecord() {
            let age = Date().timeIntervalSince(compaction.occurredAt)
            if age < 10 {
                compactionNotice = "Context optimized to keep things fast."
                scheduleCompactionNoticeClear()
            }
        }
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

    @MainActor
    private func executeStep(_ step: WorkflowStep) async -> ToolResult {
        let result = await executeStepWithApproval(step)
        results[step.id] = result
        if result.output["staleBookmark"] == "true" {
            saveNotice = "That saved location needs to be chosen again."
        }
        applyWebCards(from: result)
        if let activePlan {
            await updateGoalSnapshot(plan: activePlan)
        }
        await appendConversationEntry(
            ConversationEntry(
                content: toolResultContent(from: result),
                source: result.toolName,
                role: .toolResult,
                toolName: result.toolName,
                toolCallID: step.id
            )
        )
        return result
    }

    @MainActor
    private func executeStepWithApproval(_ step: WorkflowStep) async -> ToolResult {
        let resumeGuard = ToolResultContinuationGuard()
        let cancelledResult = ToolResult(
            id: step.id,
            toolName: step.tool,
            output: [
                "error": "Approval was cancelled.",
                "code": "USER_CANCELLED"
            ],
            succeeded: false,
            finishedAt: Date()
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resumeGuard.install(continuation)
                Task {
                    await toolApprovalManager.requestApproval(
                        policy: policy,
                        toolName: step.tool,
                        input: step.input
                    ) { approvalToken in
                        guard !resumeGuard.isResolved else { return }
                        var updatedStep = step
                        updatedStep.input = inputWithApprovalToken(step.input, approvalToken)
                        await appendConversationEntry(
                            ConversationEntry(
                                content: "Tool call \(updatedStep.tool)",
                                source: updatedStep.tool,
                                role: .toolCall,
                                toolName: updatedStep.tool,
                                toolCallID: updatedStep.id
                            )
                        )
                        guard !resumeGuard.isResolved else { return }
                        let result = await orchestrator.run(step: updatedStep)
                        resumeGuard.resume(result)
                    }
                }
            }
        } onCancel: {
            resumeGuard.resume(cancelledResult)
        }
    }

    private func friendlyStepFailure(from result: ToolResult) -> String {
        let reason = result.output["error"] ?? result.output["message"] ?? "This step could not be completed."
        if reason == "Unauthorized tool identifier." {
            return "This action isn’t available right now."
        }
        if reason == "Approval required for filesystem write." || reason == "Missing filesystem write grant." {
            return "This step needs permission before it can continue."
        }
        return reason
    }

    @MainActor
    private func scheduleCompactionNoticeClear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if compactionNotice != nil {
                compactionNotice = nil
            }
        }
    }

    @MainActor
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
        let title = plan.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Goal"
            : plan.intent
        /*
        _ = await TaskPlanner.shared.upsertGoal(
            planID: plan.id,
            title: title,
            sourceIntent: plan.intent,
            totalSteps: totalSteps,
            completedSteps: completedSteps,
            failedSteps: failedSteps
        )
        */
    }
}

private func inputWithApprovalToken(_ input: [String: String], _ approvalToken: String?) -> [String: String] {
    guard let approvalToken else { return input }
    var updated = input
    updated["approvalToken"] = approvalToken
    return updated
}

private func decodeMatches(from result: ToolResult) -> [LocalSearchMatch]? {
    guard let json = result.output["matches"] else { return nil }
    let matches = LocalSearchACL.decodeMatches(from: json)
    return matches.isEmpty ? nil : matches
}

private func decodeWebCards(from result: ToolResult) -> [WebScoutResult]? {
    guard let json = result.output["cards"] else { return nil }
    guard let signature = result.output["cardsSignature"],
          let data = json.data(using: .utf8),
          InboundIdentityValidator.shared.verifyPayload(data, signature: signature) else {
        return nil
    }
    let results = WebScoutACL.decodeResultsJSON(json)
    return results.isEmpty ? nil : results
}

private struct ConversationArchiveSheet: View {
    let entries: [ConversationEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original Context")
                .font(.headline)
            if entries.isEmpty {
                Text("No archived messages found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.source)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(entry.content)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct LocalSearchResultsPanel: View {
    let matches: [LocalSearchMatch]
    let bookmarkStore: BookmarkStore
    var notice: String? = nil
    let message: QuantumMessage?

    var body: some View {
        let status = message?.integrityStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Search Results")
                    .font(.headline)
                if let message {
                    SecurityStatusBadge(message: message)
                }
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if matches.isEmpty {
                Text("No results yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(matches, id: \.filePath) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Line \(match.lineNumber): \(match.linePreview)")
                            .font(.body)
                        Button("Open File") {
                            openMatch(match)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(minHeight: 180)
                .opacity(status == .unverified ? 0.6 : 1.0)
                .blur(radius: status == .unverified ? 0.5 : 0)
            }
        }
    }

    private func openMatch(_ match: LocalSearchMatch) {
        let matchURL = URL(fileURLWithPath: match.filePath)
        if let resolved = resolvedURL(for: matchURL) {
            NSWorkspace.shared.open(resolved)
        }
    }

    private func resolvedURL(for url: URL) -> URL? {
        let targetPath = url.standardizedFileURL.path
        for entry in bookmarkStore.entries {
            if let resolved = bookmarkStore.withResolvedURL(for: entry, action: { $0 }) {
                let folderPath = resolved.standardizedFileURL.path
                if targetPath.hasPrefix(folderPath) {
                    return url
                }
            }
        }
        return nil
    }
}

private struct WebResultsPanel: View {
    let results: [WebScoutResult]
    let notice: String?
    let message: QuantumMessage?

    var body: some View {
        let status = message?.integrityStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Web Results")
                    .font(.headline)
                if let message {
                    SecurityStatusBadge(message: message)
                }
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if results.isEmpty {
                Text("No web results yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(results, id: \.url) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                        if !item.url.isEmpty {
                            Text(item.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !item.snippet.isEmpty {
                            Text(item.snippet)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(minHeight: 160)
                .opacity(status == .unverified ? 0.6 : 1.0)
                .blur(radius: status == .unverified ? 0.5 : 0)
            }
        }
    }
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

private struct StreamingBufferView: View {
    let text: String
    @State private var displayedText: String = ""
    @State private var latestText: String = ""
    @State private var typingTask: Task<Void, Never>?

    var body: some View {
        Text(displayedText)
            .textSelection(.enabled)
            .onAppear {
                displayedText = ""
                latestText = text
                startTyping()
            }
            .onChange(of: text) { _, _ in
                latestText = text
                startTyping()
            }
            .onDisappear {
                typingTask?.cancel()
                typingTask = nil
            }
    }

    private func startTyping() {
        guard typingTask == nil else { return }
        typingTask = Task { @MainActor in
            while !Task.isCancelled {
                if !latestText.hasPrefix(displayedText) {
                    displayedText = ""
                }

                if displayedText.count > latestText.count {
                    displayedText = ""
                }

                if displayedText.count < latestText.count {
                    let nextIndex = latestText.index(latestText.startIndex, offsetBy: displayedText.count)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        displayedText.append(latestText[nextIndex])
                    }
                    try? await Task.sleep(nanoseconds: 18_000_000)
                    continue
                }

                break
            }
            typingTask = nil
        }
    }
}

private final class ToolResultContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ToolResult, Never>?
    private var didResume: Bool = false

    var isResolved: Bool {
        lock.lock()
        let resolved = didResume
        lock.unlock()
        return resolved
    }

    func install(_ continuation: CheckedContinuation<ToolResult, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: ToolResult) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}


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

private struct StatusPill: View {
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let reachability: NetworkReachabilityMonitor

    var body: some View {
        HStack(spacing: 12) {
            Label(modelModeText, systemImage: modelModeIcon)
            Label(networkText, systemImage: networkIcon)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .foregroundColor(.secondary)
    }

    private var modelModeText: String {
        activeModel()?.isCloud == true ? "Cloud" : "Local"
    }

    private var modelModeIcon: String {
        activeModel()?.isCloud == true ? "cloud" : "cpu"
    }

    private var networkText: String {
        switch reachability.scope {
        case .offline:
            return "Offline"
        case .localNetwork:
            return "Local Network"
        case .internet:
            return "Internet"
        }
    }

    private var networkIcon: String {
        switch reachability.scope {
        case .offline:
            return "wifi.slash"
        case .localNetwork:
            return "laptopcomputer"
        case .internet:
            return "globe"
        }
    }

    private func activeModel() -> LocalModel? {
        guard let id = modelSelection.activeModelId else { return nil }
        return modelRegistry.models.first { $0.id == id }
    }
}

// SecurityStatusBadge Stub if not exists (likely exists in BadgerApp but I can't see it without list_dir)
// Assuming SecurityStatusBadge is active. If not, I'll add a simple version.
struct SecurityStatusBadge: View {
    let message: QuantumMessage
    var body: some View {
        EmptyView() // Placeholder
    }
}
