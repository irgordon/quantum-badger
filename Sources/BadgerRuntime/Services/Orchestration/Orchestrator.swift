import Foundation
import BadgerCore

public actor Orchestrator {
    
    // MARK: - State
    
    /// The currently active plan, if any.
    private var activePlan: WorkflowPlan?
    
    /// Secure cache for vault references (No NSLock needed in an actor).
    private var shadowVault: [String: VaultReference] = [:]
    
    // MARK: - Dependencies
    
    private let toolRuntime: ToolRuntime
    private let auditLog: AuditLog
    private let policy: PolicyEngine
    private let vaultStore: VaultStore
    private let executionManager: HybridExecutionManager
    private let messagingPolicy: MessagingPolicyStore
    
    /// The decision maker we built previously.
    private let arbitrator: IntentArbitrator
    
    // MARK: - Init
    
    public init(
        toolRuntime: ToolRuntime,
        auditLog: AuditLog,
        policy: PolicyEngine,
        vaultStore: VaultStore,
        executionManager: HybridExecutionManager,
        messagingPolicy: MessagingPolicyStore,
        arbitrator: IntentArbitrator = IntentArbitrator()
    ) {
        self.toolRuntime = toolRuntime
        self.auditLog = auditLog
        self.policy = policy
        self.vaultStore = vaultStore
        self.executionManager = executionManager
        self.messagingPolicy = messagingPolicy
        self.arbitrator = arbitrator
    }
    
    // MARK: - Core Logic
    
    /// The main entry point for user intent.
    /// Handles the "Refine vs Preempt" logic automatically.
    public func process(intent: String) async throws -> WorkflowPlan {
        
        // 1. Arbitration Check
        if let current = activePlan, current.completedAt == nil {
            let decision = try await arbitrator.evaluate(newIntent: intent, currentPlan: current.toCorePlan())
            
            switch decision {
            case .refine:
                auditLog.record(event: .planRefined(id: current.id, intent: intent))
                return try await refine(plan: current, with: intent)
                
            case .preempt:
                auditLog.record(event: .planPreempted(id: current.id, newIntent: intent))
                archive(plan: current)
                // Fall through to create new plan
            }
        }
        
        // 2. Create New Plan
        let newPlan = await generatePlan(for: intent)
        self.activePlan = newPlan
        auditLog.record(event: .planProposed(newPlan))
        return newPlan
    }
    
    // MARK: - Plan Generation
    
    private func generatePlan(for intent: String) async -> WorkflowPlan {
        // A. Fast Path: Hardcoded logic for specific commands (e.g. "Message X")
        if let fastStep = await parseMessageIntent(intent) {
            return WorkflowPlan(intent: intent, steps: [fastStep])
        }
        
        // B. Smart Path: Ask the LLM (ExecutionManager) to build the plan
        // For this example, we fallback to "Draft" logic,
        // but in production, this should call `executionManager.generatePlan(...)`
        
        let planFilename = "plan-\(UUID().uuidString.prefix(8))"
        let draftPayload = ToolCallPayload(
            toolName: "draft",
            rawArguments: """
            { "action": "save", "filename": "\(planFilename)", "content": "Goal: \(intent)" }
            """
        )
        
        let step = WorkflowStep(
            id: UUID(),
            title: "Drafting Plan",
            tool: "draft",
            input: draftPayload,
            requiresApproval: false
        )
        
        return WorkflowPlan(intent: intent, steps: [step])
    }
    
    /// Simulates modifying an existing plan.
    private func refine(plan: WorkflowPlan, with refinement: String) async throws -> WorkflowPlan {
        // In a real agent, you would ask the LLM to merge the new intent.
        // Here, we just append a step.
        var updatedPlan = plan
        // Create a generic planner update payload
        let payload = ToolCallPayload(
             toolName: "planner",
             rawArguments: "{}" // Placeholder for actual update args
        )
        
        let refinementStep = WorkflowStep(
            id: UUID(),
            title: "Refinement: \(refinement)",
            tool: "planner.update",
            input: payload,
            requiresApproval: true
        )
        updatedPlan.steps.append(refinementStep)
        self.activePlan = updatedPlan
        return updatedPlan
    }
    
    private func archive(plan: WorkflowPlan) {
        // Logic to move plan to history/SwiftData
        self.activePlan = nil
    }

    // MARK: - Execution
    
    public func runStream(step: WorkflowStep) async -> AsyncThrowingStream<String, Error> {
        // 1. Resolve Secure References
        let references = resolveVaultReferences(from: step.input)
        
        // 2. Security Check (Basic Pre-Flight)
        if step.tool == "filesystem.write" && references.isEmpty {
             return .failed(with: ToolError.securityViolation("Security reference lost."))
        }
        
        // 3. Execution
        let request = ToolRequest(
            id: step.id,
            toolName: step.tool,
            payload: step.input, // Using our generic payload
            vaultReferences: references,
            requestedAt: Date()
        )
        
        return await toolRuntime.runStream(request)
    }

    // MARK: - Vault Management
    
    private func resolveVaultReferences(from payload: ToolCallPayload) -> [VaultReference] {
        // Simple heuristic: Check if raw JSON contains known vault keys.
        // A real implementation would parse the JSON properly.
        var refs: [VaultReference] = []
        
        // Example: Look for generic vault UUID patterns or keys in the string
        // For now, we return existing cached refs if we find their labels
        for (label, ref) in shadowVault {
            if payload.rawArguments.contains(label) {
                refs.append(ref)
            }
        }
        return refs
    }
    
    public func registerVaultReference(_ ref: VaultReference) {
        shadowVault[ref.label] = ref
    }
    
    // MARK: - Helpers
    
    private func parseMessageIntent(_ intent: String) async -> WorkflowStep? {
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
        // let conversationKey = await messagingPolicy.conversationKey(for: resolvedRecipient) // Not using yet
        
        // Construct raw JSON arguments
        // In production, use JSONEncoder to ensure escaping
        let rawJson = """
        {
            "recipient": "\(resolvedRecipient)",
            "body": "\(body)"
        }
        """
        
        return WorkflowStep(
            id: UUID(),
            title: "Draft message to \(resolvedRecipient)",
            tool: "message.send",
            input: ToolCallPayload(toolName: "message.send", rawArguments: rawJson),
            requiresApproval: true
        )
    }
}

// MARK: - Adapters

extension WorkflowPlan {
    /// Convert Runtime WorkflowPlan to Core Plan for Arbitration
    func toCorePlan() -> Plan {
        // Simplified conversion for arbitration purpose
        return Plan(
            id: self.id,
            sourceIntent: self.intent,
            steps: [], // Steps not needed for semantic comparison
            status: .active,
            createdAt: self.createdAt
        )
    }
}
