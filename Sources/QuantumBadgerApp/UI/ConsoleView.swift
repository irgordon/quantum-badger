import SwiftUI
import AppKit
import QuantumBadgerRuntime

struct ConsoleView: View {
    let orchestrator: Orchestrator
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let reachability: NetworkReachabilityMonitor
    let memoryManager: MemoryManager
    let bookmarkStore: BookmarkStore
    let vaultStore: VaultStore
    let auditLog: AuditLog
    let policy: PolicyEngine
    let toolApprovalManager: ToolApprovalManager
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
    @State private var generationTask: Task<Void, Never>?

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

            HStack {
                TextField("Describe what you want to do", text: $prompt)
                Button("Make a Plan") {
                    guard !prompt.isEmpty else { return }
                    Task {
                        activePlan = await orchestrator.proposePlan(for: prompt)
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                Button("Ask") {
                    guard !prompt.isEmpty else { return }
                    Task {
                        generationTask?.cancel()
                        assistantResponse = ""
                        generationTask = Task {
                            do {
                                for try await chunk in orchestrator.streamResponse(for: prompt) {
                                    await MainActor.run {
                                        assistantResponse += chunk
                                    }
                                }
                                await MainActor.run {
                                    generationTask = nil
                                }
                            } catch {
                                await MainActor.run {
                                    assistantResponse = "Error: \(error)"
                                    generationTask = nil
                                }
                            }
                        }
                    }
                }
                Button("Stop Generation") {
                    generationTask?.cancel()
                    orchestrator.cancelActiveGeneration()
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

            if let plan = activePlan {
                PlanView(
                    plan: plan,
                    results: results,
                    exportNotice: exportNotice,
                    runStep: { step in
                        Task { await handleStepApproval(step) }
                    },
                    exportPlan: {
                        Task { await exportPlan(plan) }
                    }
                )
            } else {
                ContentUnavailableView("No Plan", systemImage: "wand.and.stars", description: Text("Describe a task to get started."))
            }

            if !assistantResponse.isEmpty {
                GroupBox("Assistant") {
                    StreamingBufferView(text: assistantResponse)
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

            LocalSearchResultsPanel(matches: searchMatches, bookmarkStore: bookmarkStore, notice: searchNotice)

            WebResultsPanel(results: webCards, notice: webCardsNotice)

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
        _ = memoryManager.addEntry(entry)

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

        Task.detached(priority: .userInitiated) { [orchestrator] in
            let result = await orchestrator.run(step: step)
            let decoded = decodeMatches(from: result)
            await MainActor.run {
                self.results[request.id] = result
                if let decoded {
                    self.searchMatches = decoded
                }
                self.searchNotice = searchNoticeText(from: result)
            }
        }
    }

    @MainActor
    private func handleStepApproval(_ step: WorkflowStep) async {
        await toolApprovalManager.requestApproval(policy: policy, toolName: step.tool, input: step.input) { approvalToken in
            var updatedStep = step
            updatedStep.input = inputWithApprovalToken(step.input, approvalToken)
            let result = await orchestrator.run(step: updatedStep)
            results[step.id] = result
            if result.output["staleBookmark"] == "true" {
                saveNotice = "That saved location needs to be chosen again."
            }
            applyWebCards(from: result)
        }
    }

    private func applyWebCards(from result: ToolResult) {
        guard result.toolName == "web.scout" else { return }
        if let cards = decodeWebCards(from: result) {
            webCards = cards
        } else {
            webCards = []
        }
        webCardsNotice = webCardsNotice(from: result)
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
        _ = memoryManager.addEntry(entry)
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
            let result = await orchestrator.run(step: updatedStep)
            results[step.id] = result
        }
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
    let results = WebScoutACL.decodeResultsJSON(json)
    return results.isEmpty ? nil : results
}

private struct LocalSearchResultsPanel: View {
    let matches: [LocalSearchMatch]
    let bookmarkStore: BookmarkStore
    var notice: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Results")
                .font(.headline)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Web Results")
                .font(.headline)
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
    if result.succeeded {
        return "Here are the web results I found."
    }
    return "Web results couldn’t be loaded. Try again or adjust your web settings."
}

private struct StreamingBufferView: View {
    let text: String
    @State private var displayedText: String = ""
    @State private var typingTask: Task<Void, Never>?

    var body: some View {
        Text(displayedText)
            .textSelection(.enabled)
            .onAppear {
                displayedText = ""
                startTyping()
            }
            .onChange(of: text) { _, _ in
                startTyping()
            }
            .onDisappear {
                typingTask?.cancel()
            }
    }

    private func startTyping() {
        typingTask?.cancel()
        let target = text
        typingTask = Task { @MainActor in
            if displayedText.count > target.count {
                displayedText = ""
            }
            let startIndex = displayedText.count
            if startIndex >= target.count {
                return
            }
            let characters = Array(target)
            for index in startIndex..<characters.count {
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    displayedText.append(characters[index])
                }
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
        }
    }
}


struct PlanView: View {
    let plan: WorkflowPlan
    let results: [UUID: ToolResult]
    let exportNotice: String?
    let runStep: (WorkflowStep) -> Void
    let exportPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.headline)
                Spacer()
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.windowBackgroundColor)))
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
                .fill(Color(.windowBackgroundColor))
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
