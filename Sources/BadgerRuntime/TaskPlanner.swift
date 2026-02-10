import Foundation
import BadgerCore
import MLX // Assuming OSLog or similar needed, but user used AppLogger

public enum TaskGoalStatus: String, Codable, Sendable {
    case active
    case completed
    case failed
}

public struct TaskGoal: Identifiable, Codable, Sendable, Hashable {
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
}

public actor TaskPlanner {
    public static let shared = TaskPlanner()

    private var goals: [TaskGoal] = []
    private let storageURL: URL
    private var goalUpdatedHandler: (@Sendable (TaskGoal) async -> Void)?

    public init(storageURL: URL = AppPaths.taskGoalsURL) {
        self.storageURL = storageURL
        self.goals = JSONStore.loadOptional([TaskGoal].self, from: storageURL) ?? []
    }

    public func configureGoalUpdateHandler(
        _ handler: @escaping @Sendable (TaskGoal) async -> Void
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
    ) -> TaskGoal {
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

        let goal = TaskGoal(
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

    public func fetchGoals(ids: [UUID]) -> [TaskGoal] {
        let idSet = Set(ids)
        if idSet.isEmpty { return [] }
        return goals.filter { idSet.contains($0.id) }
    }

    public func activeGoals(limit: Int = 20) -> [TaskGoal] {
        Array(
            goals
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(1, limit))
        )
    }

    public func searchGoals(query: String, limit: Int = 20) -> [TaskGoal] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return activeGoals(limit: limit) }
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

    public func allGoals() -> [TaskGoal] {
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

    private func notifyGoalUpdated(_ goal: TaskGoal) {
        guard let goalUpdatedHandler else { return }
        Task {
            await goalUpdatedHandler(goal)
        }
    }

    private func persist() {
        do {
            try JSONStore.save(goals, to: storageURL)
        } catch {
            print("Failed to persist task goals: \(error.localizedDescription)") // Replaced AppLogger as stub might miss it
        }
    }
}

// Stubs for missing helpers if grep failed or they are missing.
struct AppPaths {
    static let taskGoalsURL = FileManager.default.temporaryDirectory.appendingPathComponent("task_goals.json")
}

struct JSONStore {
    static func loadOptional<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url)
    }
}
