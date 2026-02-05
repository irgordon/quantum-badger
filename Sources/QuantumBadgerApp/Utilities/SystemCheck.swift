import Foundation
import os

struct SystemCheckResult {
    let hasEnoughMemory: Bool
    let hasEnoughDisk: Bool
    let memoryGB: Int
    let diskGB: Int
}

enum SystemCheck {
    static func evaluate(minMemoryGB: Int = 16, minDiskGB: Int = 20) -> SystemCheckResult {
        let memoryBytes = availableMemoryBytes()
        let memoryGB = Int(memoryBytes / 1_000_000_000)

        let diskGB: Int
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            diskGB = Int(available / 1_000_000_000)
        } else {
            diskGB = 0
        }

        return SystemCheckResult(
            hasEnoughMemory: memoryGB >= minMemoryGB,
            hasEnoughDisk: diskGB >= minDiskGB,
            memoryGB: memoryGB,
            diskGB: diskGB
        )
    }

    private static func availableMemoryBytes() -> UInt64 {
        if #available(macOS 14, *) {
            return os_proc_available_memory()
        }
        return ProcessInfo.processInfo.physicalMemory
    }
}
