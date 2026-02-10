import Foundation
import BackgroundTasks
import SwiftUI
import BadgerRuntime // Assuming NPUAffinityManager is here

struct ScoutIntent: Identifiable, Sendable {
    let id = UUID()
    let perform: @Sendable () async -> Void

    func performScout() async {
        await perform()
    }
}

@MainActor
final class BackgroundScoutCoordinator: ObservableObject {
    static let shared = BackgroundScoutCoordinator()

    private let scoutTaskID = "com.quantumbadger.scout.processing"
    private var pendingScouts: [ScoutIntent] = []

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: scoutTaskID,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Execute on Main Actor as tasks need coordination
            Task { @MainActor in
                self.executeBackgroundScout(task: processingTask)
            }
        }
    }

    func enqueueScout(_ scout: ScoutIntent) {
        pendingScouts.append(scout)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            scheduleBackgroundScout()
        case .active:
            cancelBackgroundTasks()
        default:
            break
        }
    }

    func executeBackgroundScout(task: BGProcessingTask) {
        task.expirationHandler = {
            // NPUAffinityManager might need to be called here
            // Assuming NPUAffinityManager is available
            NPUAffinityManager.shared.emergencyStop()
        }

        Task {
            do {
                try await NPUAffinityManager.shared.executeWithAffinity(kind: .scout) {
                    for scout in self.pendingScouts {
                        await scout.performScout()
                    }
                }
                self.pendingScouts.removeAll()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func scheduleBackgroundScout() {
        let request = BGProcessingTaskRequest(identifier: scoutTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background scout: \(error)")
        }
    }

    private func cancelBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: scoutTaskID)
    }
}

// Stub for NPUAffinityManager if missing
// Ideally should be in Runtime
/*
class NPUAffinityManager {
    static let shared = NPUAffinityManager()
    enum AffinityKind { case scout }
    func emergencyStop() {}
    func executeWithAffinity(kind: AffinityKind, block: () async -> Void) async throws {
        await block()
    }
}
*/
