import Foundation
import BadgerCore
import MLX // Assuming ExecutionManager uses MLX and we might need types
import BadgerRuntime // Ensure we can access types

final class Orchestrator {
    private enum VaultInputKey {
        static let pathRef = "pathRef"
        static let connectionRef = "connectionRef"
        static let allowlist: Set<String> = [pathRef, connectionRef]
    }

    private let toolRuntime: ToolRuntime
    private let auditLog: AuditLog
    private let policy: PolicyEngine
    private let vaultStore: VaultStore
    private let reachability: NetworkReachabilityMonitor
    private let messagingPolicy: MessagingPolicyStore
    private let executionManager: HybridExecutionManager
    private let shadowVaultLock = NSLock()
    private var shadowVault: [String: VaultReference] = [:]

    init(
        toolRuntime: ToolRuntime,
        auditLog: AuditLog,
        policy: PolicyEngine,
        vaultStore: VaultStore,
        reachability: NetworkReachabilityMonitor,
        messagingPolicy: MessagingPolicyStore,
        executionManager: HybridExecutionManager
    ) {
        self.toolRuntime = toolRuntime
        self.auditLog = auditLog
        self.policy = policy
        self.vaultStore = vaultStore
        self.reachability = reachability
        self.messagingPolicy = messagingPolicy
        self.executionManager = executionManager
    }

    func proposePlan(for intent: String) async -> WorkflowPlan {
        if let messagingStep = await messageStep(from: intent) {
            let plan = WorkflowPlan(
                id: UUID(),
                intent: intent,
                steps: [messagingStep],
                createdAt: Date()
            )
            _ = await TaskPlanner.shared.upsertGoal(
                planID: plan.id,
                title: intent.isEmpty ? "Untitled Goal" : intent,
                sourceIntent: intent,
                totalSteps: max(1, plan.steps.count),
                completedSteps: 0,
                failedSteps: 0
            )
            auditLog.record(event: .planProposed(plan))
            return plan
        }
        let planFilename = "plan-\(UUID().uuidString.prefix(8))"
        let steps = [
            WorkflowStep(
                id: UUID(),
                title: "Create plan draft",
                tool: "draft",
                input: [
                    "action": "save",
                    "filename": planFilename,
                    "content": "Plan goal: \(intent)\n\n1. Clarify objective\n2. Gather inputs\n3. Execute safely"
                ],
                requiresApproval: true
            ),
            WorkflowStep(
                id: UUID(),
                title: "Review plan draft",
                tool: "draft",
                input: [
                    "action": "read",
                    "filename": planFilename
                ],
                requiresApproval: false
            )
        ]
        let plan = WorkflowPlan(id: UUID(), intent: intent, steps: steps, createdAt: Date())
        _ = await TaskPlanner.shared.upsertGoal(
            planID: plan.id,
            title: intent.isEmpty ? "Untitled Goal" : intent,
            sourceIntent: intent,
            totalSteps: max(1, plan.steps.count),
            completedSteps: 0,
            failedSteps: 0
        )
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
        shadowVaultLock.lock()
        let cached = shadowVault[label]
        shadowVaultLock.unlock()
        if let cached {
            return cached
        }

        guard let reference = vaultStore.reference(forLabel: label) else { return nil }
        shadowVaultLock.lock()
        shadowVault[label] = reference
        shadowVaultLock.unlock()
        return reference
    }

    func generateResponse(for prompt: String, hint: ExecutionHint = .default) async -> Result<String, InferenceError> {
        await executionManager.generateResponse(for: prompt, hint: hint)
    }

    func streamResponse(for prompt: String, hint: ExecutionHint = .default) -> AsyncThrowingStream<QuantumMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let stream = executionManager.streamResponse(for: prompt, hint: hint)
                do {
                    for try await message in stream {
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancelActiveGeneration() {
        executionManager.cancelActiveGeneration()
    }

    func warmUpIfPossible() async {
        await executionManager.warmUpIfPossible()
    }

    private func vaultReferences(from input: [String: String]) -> [VaultReference]? {
        let labels = input
            .filter { VaultInputKey.allowlist.contains($0.key) }
            .map { $0.value }
        var references: [VaultReference] = []
        for label in labels {
            if let reference = vaultReference(for: label) {
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

// Stub for missing type if not in core, though executionManager likely uses it.
// Assuming QuantumMessage is needed.
struct QuantumMessage: Sendable {
    let id = UUID()
    let content: String
    let sender: Sender
    enum Sender { case user, system, assistant }
}

enum ExecutionHint {
    case `default`
}

enum InferenceError: Error {
    case cancelled
    case unknown
}

// Stub extension for execution manager if methods missing
extension HybridExecutionManager {
    func generateResponse(for prompt: String, hint: ExecutionHint) async -> Result<String, InferenceError> {
        // Stub implementation
        return .success("[Generated response stub]")
    }
    
    func streamResponse(for prompt: String, hint: ExecutionHint) -> AsyncThrowingStream<QuantumMessage, Error> {
        return AsyncThrowingStream { continuation in
            continuation.yield(QuantumMessage(content: "Stream stub", sender: .assistant))
            continuation.finish()
        }
    }
}
