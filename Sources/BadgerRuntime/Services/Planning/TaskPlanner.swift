import Foundation
import BadgerCore

// MARK: - Task Goal Record (Internal Planner State)

/// The planner's internal goal record with full tracking fields.
/// Distinct from `BadgerCore.TaskGoal` (AppEntity) which is the Spotlight-facing type.
public enum TaskGoalStatus: String, Codable, Sendable {
    case active
    case completed
    case failed
}

public struct TaskGoalRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var sourceIntent: String
    public var status: TaskGoalStatus
    public var completionPercentage: Double
    public var totalSteps: Int
    public var completedSteps: Int
    public var failedSteps: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        sourceIntent: String,
        status: TaskGoalStatus,
        completionPercentage: Double,
        totalSteps: Int,
        completedSteps: Int,
        failedSteps: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceIntent = sourceIntent
        self.status = status
        self.completionPercentage = completionPercentage
        self.totalSteps = totalSteps
        self.completedSteps = completedSteps
        self.failedSteps = failedSteps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convert to a BadgerCore `TaskGoal` for Spotlight indexing.
    public func toAppEntity() -> TaskGoal {
        TaskGoal(
            id: id,
            title: title,
            status: status.rawValue,
            createdAt: createdAt
        )
    }
}

// MARK: - Task Planner Actor

public actor TaskPlanner: TaskGoalProvider {
    public static let shared = TaskPlanner()

    private var goals: [TaskGoalRecord] = []
    private let storageURL: URL
    private var goalUpdatedHandler: (@Sendable (TaskGoalRecord) async -> Void)?

    public init(storageURL: URL = AppPaths.taskGoalsURL) {
        self.storageURL = storageURL
        self.goals = JSONStore.loadOptional([TaskGoalRecord].self, from: storageURL) ?? []
    }

    public func configureGoalUpdateHandler(
        _ handler: @escaping @Sendable (TaskGoalRecord) async -> Void
    ) {
        goalUpdatedHandler = handler
    }

    @discardableResult
    public func upsertGoal(
        planID: UUID,
        title: String,
        sourceIntent: String,
        totalSteps: Int,
        completedSteps: Int,
        failedSteps: Int
    ) -> TaskGoalRecord {
        let safeTotal = max(1, totalSteps)
        let safeCompleted = max(0, min(completedSteps, safeTotal))
        let safeFailed = max(0, min(failedSteps, safeTotal))
        let progress = min(1.0, max(0.0, Double(safeCompleted) / Double(safeTotal)))

        let status: TaskGoalStatus
        if safeCompleted >= safeTotal {
            status = .completed
        } else if safeFailed > 0 {
            status = .failed
        } else {
            status = .active
        }

        let now = Date()
        if let index = goals.firstIndex(where: { $0.id == planID }) {
            goals[index].title = title
            goals[index].sourceIntent = sourceIntent
            goals[index].totalSteps = safeTotal
            goals[index].completedSteps = safeCompleted
            goals[index].failedSteps = safeFailed
            goals[index].completionPercentage = progress
            goals[index].status = status
            goals[index].updatedAt = now
            persist()
            let updated = goals[index]
            notifyGoalUpdated(updated)
            return updated
        }

        let goal = TaskGoalRecord(
            id: planID,
            title: title,
            sourceIntent: sourceIntent,
            status: status,
            completionPercentage: progress,
            totalSteps: safeTotal,
            completedSteps: safeCompleted,
            failedSteps: safeFailed,
            createdAt: now,
            updatedAt: now
        )
        goals.append(goal)
        goals.sort { $0.updatedAt > $1.updatedAt }
        persist()
        notifyGoalUpdated(goal)
        return goal
    }

    public func fetchGoals(ids: [UUID]) -> [TaskGoalRecord] {
        let idSet = Set(ids)
        if idSet.isEmpty { return [] }
        return goals.filter { idSet.contains($0.id) }
    }

    // MARK: - TaskGoalProvider Conformance (BadgerCore)

    public func activeGoals() async -> [TaskGoal] {
        activeGoalRecords(limit: 20).map { $0.toAppEntity() }
    }

    public func goals(matching query: String) async -> [TaskGoal] {
        searchGoals(query: query, limit: 20).map { $0.toAppEntity() }
    }

    public func goals(for ids: [UUID]) async -> [TaskGoal] {
        fetchGoals(ids: ids).map { $0.toAppEntity() }
    }

    // MARK: - Internal Query API

    public func activeGoalRecords(limit: Int = 20) -> [TaskGoalRecord] {
        Array(
            goals
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(1, limit))
        )
    }

    public func searchGoals(query: String, limit: Int = 20) -> [TaskGoalRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return activeGoalRecords(limit: limit) }
        return Array(
            goals
                .filter { goal in
                    goal.title.lowercased().contains(trimmed)
                    || goal.sourceIntent.lowercased().contains(trimmed)
                    || goal.status.rawValue.lowercased().contains(trimmed)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(max(1, limit))
        )
    }

    public func allGoals() -> [TaskGoalRecord] {
        goals.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        persist()
    }

    public func reset() {
        goals.removeAll()
        persist()
    }

    public func forcePersist() {
        persist()
    }

    private func notifyGoalUpdated(_ goal: TaskGoalRecord) {
        guard let goalUpdatedHandler else { return }
        Task {
            await goalUpdatedHandler(goal)
        }
    }

    private func persist() {
        do {
            try JSONStore.save(goals, to: storageURL)
        } catch {
            print("Failed to persist task goals: \(error.localizedDescription)")
        }
    }
}
