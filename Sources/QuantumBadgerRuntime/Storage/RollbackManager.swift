import Foundation
import SwiftData

struct RollbackResult {
    let succeeded: Bool
    let requiresRestart: Bool
    let message: String
}

final class RollbackManager {
    private let snapshotStore: MemorySnapshotStore
    private let modelContext: ModelContext
    private let auditLog: AuditLog
    private let observationURL: URL
    private let summaryURL: URL

    init(
        snapshotStore: MemorySnapshotStore,
        modelContext: ModelContext,
        auditLog: AuditLog,
        observationURL: URL = AppPaths.memoryObservationURL,
        summaryURL: URL = AppPaths.memorySummaryURL
    ) {
        self.snapshotStore = snapshotStore
        self.modelContext = modelContext
        self.auditLog = auditLog
        self.observationURL = observationURL
        self.summaryURL = summaryURL
    }

    @MainActor
    func rollback(to snapshotId: UUID, using snapshots: [MemorySnapshot]) -> RollbackResult {
        guard let storeURL = modelContext.container.configurations.first?.url else {
            return RollbackResult(succeeded: false, requiresRestart: false, message: "No persistent store URL available.")
        }

        guard let targetIndex = snapshots.firstIndex(where: { $0.id == snapshotId }) else {
            return RollbackResult(succeeded: false, requiresRestart: false, message: "Snapshot not found.")
        }

        let eligible = snapshots[0...targetIndex].reversed()
        guard let artifactSnapshot = eligible.first(where: { $0.storeFileRef != nil }) else {
            return RollbackResult(succeeded: false, requiresRestart: false, message: "No stored snapshot files available.")
        }

        guard let refId = artifactSnapshot.storeFileRef else {
            return RollbackResult(succeeded: false, requiresRestart: false, message: "Snapshot reference missing.")
        }

        do {
            try modelContext.save()
        } catch {
            // Best-effort flush; rollback can still proceed.
        }
        modelContext.rollback()

        let restored = snapshotStore.restoreSnapshot(
            refId: refId,
            storeURL: storeURL,
            observationURL: observationURL,
            summaryURL: summaryURL,
            storeFilename: artifactSnapshot.storeFilename
        )

        if restored {
            auditLog.record(event: .memoryRollback(snapshotId: snapshotId))
            return RollbackResult(
                succeeded: true,
                requiresRestart: true,
                message: "Snapshot restored. Restart required to reload memory state."
            )
        }

        return RollbackResult(succeeded: false, requiresRestart: false, message: "Failed to restore snapshot files.")
    }
}
