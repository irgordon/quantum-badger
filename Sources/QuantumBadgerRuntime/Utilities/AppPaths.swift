import Foundation

enum AppPaths {
    static var appSupportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("QuantumBadger", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                AppLogger.storage.error("Failed to create app support directory: \(error.localizedDescription, privacy: .private)")
            }
        }
        return dir
    }

    static var modelsURL: URL {
        appSupportDirectory.appendingPathComponent("models.json")
    }

    static var modelsChecksumURL: URL {
        appSupportDirectory.appendingPathComponent("models.checksum")
    }

    static var modelsBackupURL: URL {
        appSupportDirectory.appendingPathComponent("models.backup.json")
    }

    static var modelsBackupChecksumURL: URL {
        appSupportDirectory.appendingPathComponent("models.backup.checksum")
    }

    static var resourcePolicyURL: URL {
        appSupportDirectory.appendingPathComponent("resource-policy.json")
    }

    static var vaultURL: URL {
        appSupportDirectory.appendingPathComponent("vault.dat")
    }

    static var auditLogURL: URL {
        appSupportDirectory.appendingPathComponent("audit.log")
    }

    static var auditPayloadsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("audit-payloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                AppLogger.storage.error("Failed to create audit payload directory: \(error.localizedDescription, privacy: .private)")
            }
        }
        return dir
    }

    static var networkPolicyURL: URL {
        appSupportDirectory.appendingPathComponent("network-policy.json")
    }

    static var modelSelectionURL: URL {
        appSupportDirectory.appendingPathComponent("model-selection.json")
    }

    static var memoryURL: URL {
        appSupportDirectory.appendingPathComponent("memory.dat")
    }

    static var bookmarksURL: URL {
        appSupportDirectory.appendingPathComponent("bookmarks.json")
    }

    static var memoryObservationURL: URL {
        appSupportDirectory.appendingPathComponent("memory-observations.json")
    }

    static var memorySummaryURL: URL {
        appSupportDirectory.appendingPathComponent("memory-summaries.json")
    }

    static var memorySnapshotsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("memory-snapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                AppLogger.storage.error("Failed to create memory snapshot directory: \(error.localizedDescription, privacy: .private)")
            }
        }
        return dir
    }

    static var messagingPolicyURL: URL {
        appSupportDirectory.appendingPathComponent("messaging-policy.json")
    }

    static var webFilterURL: URL {
        appSupportDirectory.appendingPathComponent("web-filters.json")
    }

    static var toolLimitsURL: URL {
        appSupportDirectory.appendingPathComponent("tool-limits.json")
    }
}
