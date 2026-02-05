import Foundation

final class Orchestrator {
    private let toolRuntime: ToolRuntime
    private let auditLog: AuditLog
    private let modelLoader: ModelLoader
    private let policy: PolicyEngine
    private let modelRegistry: ModelRegistry
    private let modelSelection: ModelSelectionStore
    private let vaultStore: VaultStore
    private let resourcePolicy: ResourcePolicyStore
    private let reachability: NetworkReachabilityMonitor
    private let messagingPolicy: MessagingPolicyStore
    private var shadowVault: [String: VaultReference] = [:]
    private let runtimeLock = NSLock()
    private var activeRuntime: ModelRuntime?

    init(
        toolRuntime: ToolRuntime,
        auditLog: AuditLog,
        modelLoader: ModelLoader,
        policy: PolicyEngine,
        modelRegistry: ModelRegistry,
        modelSelection: ModelSelectionStore,
        vaultStore: VaultStore,
        resourcePolicy: ResourcePolicyStore,
        reachability: NetworkReachabilityMonitor,
        messagingPolicy: MessagingPolicyStore
    ) {
        self.toolRuntime = toolRuntime
        self.auditLog = auditLog
        self.modelLoader = modelLoader
        self.policy = policy
        self.modelRegistry = modelRegistry
        self.modelSelection = modelSelection
        self.vaultStore = vaultStore
        self.resourcePolicy = resourcePolicy
        self.reachability = reachability
        self.messagingPolicy = messagingPolicy
    }

    func proposePlan(for intent: String) async -> WorkflowPlan {
        if let messagingStep = await messageStep(from: intent) {
            let plan = WorkflowPlan(
                id: UUID(),
                intent: intent,
                steps: [messagingStep],
                createdAt: Date()
            )
            auditLog.record(event: .planProposed(plan))
            return plan
        }
        let steps = [
            WorkflowStep(id: UUID(), title: "Analyze intent", tool: "analysis", input: ["intent": intent], requiresApproval: false),
            WorkflowStep(id: UUID(), title: "Prepare draft", tool: "draft", input: ["summary": "Prepare output"], requiresApproval: true)
        ]
        let plan = WorkflowPlan(id: UUID(), intent: intent, steps: steps, createdAt: Date())
        auditLog.record(event: .planProposed(plan))
        return plan
    }

    func run(step: WorkflowStep) async -> ToolResult {
        let references = vaultReferences(from: step.input)
        if step.tool == "filesystem.write", references == nil {
            return ToolResult(
                id: step.id,
                toolName: step.tool,
                output: ["error": "Security reference lost. Please re-select the destination."],
                succeeded: false,
                finishedAt: Date()
            )
        }
        let request = ToolRequest(
            id: step.id,
            toolName: step.tool,
            input: step.input,
            vaultReferences: references,
            requestedAt: Date()
        )
        return await toolRuntime.run(request)
    }

    func vaultReference(for label: String) -> VaultReference? {
        if let existing = shadowVault[label] {
            return existing
        }
        guard let reference = vaultStore.reference(forLabel: label) else { return nil }
        shadowVault[label] = reference
        return reference
    }

    func generateResponse(for prompt: String) async -> Result<String, InferenceError> {
        if resourcePolicy.memoryPressure != .normal {
            return .failure(.runtimeError("Memory pressure is high. Try again when your Mac is less busy."))
        }
        let model = activeModel()
        let decision = await policy.evaluatePrompt(prompt, model: model)
        guard decision.isAllowed else {
            return .failure(.runtimeError(decision.reason))
        }

        do {
            auditLog.record(event: .modelPrompted(decision.redactedPrompt))
            let modelRuntime = await MainActor.run { modelLoader.loadActiveRuntime() }
            let timeoutSeconds = max(10, model?.expectedLatencySeconds ?? 10)
            let response = try await withTimeout(seconds: timeoutSeconds) {
                try await modelRuntime.generateResponse(for: decision.redactedPrompt)
            }
            return .success(response)
        } catch let error as InferenceError {
            return .failure(error)
        } catch {
            return .failure(.runtimeError(error.localizedDescription))
        }
    }

    func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if resourcePolicy.memoryPressure != .normal {
                    continuation.finish(throwing: InferenceError.runtimeError("Memory pressure is high. Try again when your Mac is less busy."))
                    return
                }
                let model = activeModel()
                let decision = await policy.evaluatePrompt(prompt, model: model)
                guard decision.isAllowed else {
                    continuation.finish(throwing: InferenceError.runtimeError(decision.reason))
                    return
                }

                auditLog.record(event: .modelPrompted(decision.redactedPrompt))
                let modelRuntime = await MainActor.run { modelLoader.loadActiveRuntime() }
                setActiveRuntime(modelRuntime)
                let stream = modelRuntime.streamResponse(for: decision.redactedPrompt)
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                clearActiveRuntime(modelRuntime)
            }
        }
    }

    func cancelActiveGeneration() {
        runtimeLock.lock()
        let runtime = activeRuntime
        runtimeLock.unlock()
        runtime?.cancelGeneration()
    }

    private func setActiveRuntime(_ runtime: ModelRuntime) {
        runtimeLock.lock()
        activeRuntime = runtime
        runtimeLock.unlock()
    }

    private func clearActiveRuntime(_ runtime: ModelRuntime) {
        runtimeLock.lock()
        if activeRuntime?.modelName == runtime.modelName {
            activeRuntime = nil
        }
        runtimeLock.unlock()
    }

    func warmUpIfPossible() async {
        await MainActor.run {
            Task { await modelLoader.warmUpActiveRuntime() }
        }
    }

    private func activeModel() -> LocalModel? {
        guard let id = modelSelection.effectiveModelId(
            isReachable: reachability.isReachable,
            registry: modelRegistry
        ) else { return nil }
        return modelRegistry.models.first { $0.id == id }
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask {
                do {
                    return .success(try await operation())
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .failure(InferenceError.timeout)
            }

            var lastError: Error?
            for _ in 0..<2 {
                if let result = await group.next() {
                    switch result {
                    case .success(let value):
                        group.cancelAll()
                        return value
                    case .failure(let error):
                        lastError = error
                    }
                }
            }
            throw lastError ?? InferenceError.timeout
        }
    }

    private func vaultReferences(from input: [String: String]) -> [VaultReference]? {
        let allowlist = ["pathRef", "connectionRef"]
        let labels = input
            .filter { allowlist.contains($0.key) }
            .map { $0.value }
        var references: [VaultReference] = []
        for label in labels {
            if let existing = shadowVault[label] {
                references.append(existing)
                continue
            }
            if let reference = vaultStore.reference(forLabel: label) {
                shadowVault[label] = reference
                references.append(reference)
            }
        }
        return references.isEmpty ? nil : references
    }

    private func messageStep(from intent: String) async -> WorkflowStep? {
        let lowered = intent.lowercased()
        guard lowered.contains("message ") || lowered.contains("text ") else { return nil }
        let parts = intent.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let rawRecipient = parts[0]
            .replacingOccurrences(of: "message", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "text", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawRecipient.isEmpty, !body.isEmpty else { return nil }
        let resolvedRecipient = await messagingPolicy.resolveRecipient(rawRecipient) ?? rawRecipient
        let conversationKey = await messagingPolicy.conversationKey(for: resolvedRecipient)
        var input: [String: String] = ["recipient": resolvedRecipient, "body": body]
        if let conversationKey {
            input["conversationKey"] = conversationKey
        }
        return WorkflowStep(
            id: UUID(),
            title: "Draft message to \(resolvedRecipient)",
            tool: "message.send",
            input: input,
            requiresApproval: true
        )
    }
}

struct WorkflowPlan: Identifiable, Codable {
    let id: UUID
    let intent: String
    var steps: [WorkflowStep]
    let createdAt: Date
}

struct WorkflowStep: Identifiable, Codable {
    let id: UUID
    var title: String
    var tool: String
    var input: [String: String]
    var requiresApproval: Bool
}
