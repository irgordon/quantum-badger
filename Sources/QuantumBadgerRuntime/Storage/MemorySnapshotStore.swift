import Foundation

struct MemorySnapshotArtifact: Codable {
    let refId: String
    let storeFilename: String?
    let observationFilename: String
    let summaryFilename: String
}

final class MemorySnapshotStore {
    private let directoryURL: URL
    private let fileManager = FileManager.default

    init(directoryURL: URL = AppPaths.memorySnapshotsDirectory) {
        self.directoryURL = directoryURL
    }

    func storeSnapshot(
        storeURL: URL?,
        observationURL: URL,
        summaryURL: URL,
        snapshotId: UUID
    ) -> MemorySnapshotArtifact? {
        let refId = snapshotId.uuidString
        let snapshotDir = directoryURL.appendingPathComponent(refId, isDirectory: true)
        do {
            if !fileManager.fileExists(atPath: snapshotDir.path) {
                try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            }
        } catch {
            AppLogger.storage.error("Failed to create snapshot directory: \(error.localizedDescription, privacy: .private)")
            return nil
        }

        let observationFilename = observationURL.lastPathComponent
        let summaryFilename = summaryURL.lastPathComponent
        copyFile(from: observationURL, to: snapshotDir.appendingPathComponent(observationFilename))
        copyFile(from: summaryURL, to: snapshotDir.appendingPathComponent(summaryFilename))

        var storeFilename: String?
        if let storeURL {
            storeFilename = storeURL.lastPathComponent
            copyFile(from: storeURL, to: snapshotDir.appendingPathComponent(storeFilename ?? storeURL.lastPathComponent))
            copySQLiteSidecars(for: storeURL, to: snapshotDir)
        }

        return MemorySnapshotArtifact(
            refId: refId,
            storeFilename: storeFilename,
            observationFilename: observationFilename,
            summaryFilename: summaryFilename
        )
    }

    func restoreSnapshot(
        refId: String,
        storeURL: URL?,
        observationURL: URL,
        summaryURL: URL,
        storeFilename: String?
    ) -> Bool {
        let snapshotDir = directoryURL.appendingPathComponent(refId, isDirectory: true)
        guard fileManager.fileExists(atPath: snapshotDir.path) else { return false }

        let observationSource = snapshotDir.appendingPathComponent(observationURL.lastPathComponent)
        let summarySource = snapshotDir.appendingPathComponent(summaryURL.lastPathComponent)
        copyFile(from: observationSource, to: observationURL)
        copyFile(from: summarySource, to: summaryURL)

        if let storeURL, let storeFilename {
            let storeSource = snapshotDir.appendingPathComponent(storeFilename)
            copyFile(from: storeSource, to: storeURL)
            restoreSQLiteSidecars(for: storeURL, from: snapshotDir)
        }
        return true
    }

    func deleteSnapshots(except keepIds: Set<String>) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return 0 }

        var removed = 0
        for case let fileURL as URL in enumerator {
            let id = fileURL.lastPathComponent
            if keepIds.contains(id) { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            do {
                try fileManager.removeItem(at: fileURL)
                removed += 1
            } catch {
                AppLogger.storage.error("Failed to remove snapshot directory: \(error.localizedDescription, privacy: .private)")
            }
        }
        return removed
    }

    private func copyFile(from source: URL, to destination: URL) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            AppLogger.storage.error("Failed to copy snapshot file: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func copySQLiteSidecars(for storeURL: URL, to snapshotDir: URL) {
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        if fileManager.fileExists(atPath: walURL.path) {
            copyFile(from: walURL, to: snapshotDir.appendingPathComponent(walURL.lastPathComponent))
        }
        if fileManager.fileExists(atPath: shmURL.path) {
            copyFile(from: shmURL, to: snapshotDir.appendingPathComponent(shmURL.lastPathComponent))
        }
    }

    private func restoreSQLiteSidecars(for storeURL: URL, from snapshotDir: URL) {
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walSource = snapshotDir.appendingPathComponent(walURL.lastPathComponent)
        let shmSource = snapshotDir.appendingPathComponent(shmURL.lastPathComponent)
        copyFile(from: walSource, to: walURL)
        copyFile(from: shmSource, to: shmURL)
    }
}
