import SwiftData
import Foundation
import BadgerCore
import BadgerRuntime

// MARK: - Models

@Model
final class PersistedPlan {
    // We use a String primary key to match the UUID of the struct exactly
    @Attribute(.unique) public var id: UUID
    public var intent: String
    public var createdAt: Date
    public var completedAt: Date?
    
    // Relationship: One Plan has many Steps. 
    // Delete the plan -> Delete the steps.
    @Relationship(deleteRule: .cascade, inverse: \PersistedStep.plan)
    public var steps: [PersistedStep] = []
    
    init(from plan: WorkflowPlan) {
        self.id = plan.id
        self.intent = plan.intent
        self.createdAt = plan.createdAt
        self.completedAt = plan.completedAt
    }
    
    /// Updates the mutable fields from a struct snapshot
    func update(from plan: WorkflowPlan) {
        self.completedAt = plan.completedAt
        // Steps are handled individually to avoid thrashing the database
    }
}

@Model
final class PersistedStep {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var tool: String
    public var statusRaw: String // Store enum as String
    
    // Flattened Payload for storage
    public var inputJSON: String
    
    // Flattened Result
    public var resultJSON: String?
    public var resultSucceeded: Bool?
    public var resultDate: Date?
    
    public var requiresApproval: Bool
    
    public var plan: PersistedPlan?
    
    init(from step: WorkflowStep) {
        self.id = step.id
        self.title = step.title
        self.tool = step.tool
        self.statusRaw = step.status.rawValue
        self.inputJSON = step.input.rawArguments
        self.requiresApproval = step.requiresApproval
        
        if let res = step.result {
            self.resultJSON = res.rawOutput
            self.resultSucceeded = res.succeeded
            self.resultDate = res.finishedAt
        }
    }
    
    func update(from step: WorkflowStep) {
        self.statusRaw = step.status.rawValue
        if let res = step.result {
            self.resultJSON = res.rawOutput
            self.resultSucceeded = res.succeeded
            self.resultDate = res.finishedAt
        }
    }
}

// MARK: - Conversion Logic

extension PersistedPlan {
    /// Converts the database object back to a Sendable Struct
    var toStruct: WorkflowPlan {
        // Sort steps by index or creation time? 
        // Ideally we add an 'index' field, but for now we trust the array order.
        let stepStructs = self.steps.map { $0.toStruct }
        
        return WorkflowPlan(
            id: self.id,
            intent: self.intent,
            steps: stepStructs,
            createdAt: self.createdAt,
            completedAt: self.completedAt
        )
    }
}

extension PersistedStep {
    var toStruct: WorkflowStep {
        let status = WorkflowStepStatus(rawValue: self.statusRaw) ?? .pending
        
        var result: ToolResult? = nil
        if let json = self.resultJSON, let succeeded = self.resultSucceeded, let date = self.resultDate {
            result = ToolResult(
                id: UUID(), // We don't persist result ID currently, generate new
                stepId: self.id,
                toolName: self.tool,
                rawOutput: json,
                succeeded: succeeded,
                finishedAt: date
            )
        }
        
        return WorkflowStep(
            id: self.id,
            title: self.title,
            tool: self.tool,
            input: ToolCallPayload(toolName: self.tool, rawArguments: self.inputJSON),
            requiresApproval: self.requiresApproval,
            status: status,
            result: result
        )
    }
}

// MARK: - Service

@MainActor
public class HistoryService: ObservableObject {
    private let container: ModelContainer
    private let context: ModelContext
    
    public init() {
        do {
            self.container = try ModelContainer(for: PersistedPlan.self, PersistedStep.self)
            self.context = container.mainContext
        } catch {
            fatalError("Failed to init SwiftData: \(error)")
        }
    }
    
    // MARK: - Saving
    
    /// Saves or Updates a plan.
    public func save(_ plan: WorkflowPlan) {
        // 1. Check if it exists
        let id = plan.id
        let descriptor = FetchDescriptor<PersistedPlan>(predicate: #Predicate { $0.id == id })
        
        do {
            let existing = try context.fetch(descriptor).first
            
            if let existingPlan = existing {
                // UPDATE existing
                existingPlan.update(from: plan)
                
                // Update steps intelligently
                for stepStruct in plan.steps {
                    if let existingStep = existingPlan.steps.first(where: { $0.id == stepStruct.id }) {
                        existingStep.update(from: stepStruct)
                    } else {
                        // New step added during execution?
                        let newStep = PersistedStep(from: stepStruct)
                        existingPlan.steps.append(newStep) // Relationship handles context insert
                    }
                }
            } else {
                // INSERT new
                let newPlan = PersistedPlan(from: plan)
                // Create sub-objects
                for step in plan.steps {
                    let newStep = PersistedStep(from: step)
                    newPlan.steps.append(newStep)
                }
                context.insert(newPlan)
            }
            
            // Commit to disk
            try context.save()
            print("💾 Saved Plan: \(plan.intent)")
            
        } catch {
            print("❌ Failed to save plan: \(error)")
        }
    }
    
    // MARK: - Fetching
    
    public func fetchRecent() -> [WorkflowPlan] {
        let descriptor = FetchDescriptor<PersistedPlan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            let persisted = try context.fetch(descriptor)
            return persisted.map { $0.toStruct }
        } catch {
            print("❌ Fetch failed: \(error)")
            return []
        }
    }
}
