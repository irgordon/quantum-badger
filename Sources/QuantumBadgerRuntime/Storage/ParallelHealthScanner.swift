import Foundation

struct PayloadScanReport: Codable {
    let hashedCount: Int
    let unreadableCount: Int
    let unreadableIds: [String]
    let combinedHash: String
}

enum ParallelHealthScanner {
    static func scanPayloads(directory: URL = AppPaths.auditPayloadsDirectory) async -> PayloadScanReport {
        let payloads = payloadFiles(in: directory)
        if payloads.isEmpty {
            return PayloadScanReport(hashedCount: 0, unreadableCount: 0, unreadableIds: [], combinedHash: "")
        }

        var hashes: [(String, Data)] = []
        hashes.reserveCapacity(payloads.count)
        var unreadable = 0
        var unreadableIds: [String] = []

        // Determinism: sort inputs before TaskGroup to keep the combined hash stable across hardware.
        let orderedPayloads = payloads.sorted { $0.lastPathComponent < $1.lastPathComponent }
        await withTaskGroup(of: (String, Data?).self) { group in
            for file in orderedPayloads {
                group.addTask {
                    let hash = Hashing.sha256File(file)
                    return (file.lastPathComponent, hash)
                }
            }

            for await result in group {
                if let digest = result.1 {
                    hashes.append((result.0, digest))
                } else {
                    unreadable += 1
                    unreadableIds.append(result.0)
                }
            }
        }

        hashes.sort { $0.0 < $1.0 }
        var combined = Data()
        for (name, digest) in hashes {
            combined.append(contentsOf: name.utf8)
            combined.append(digest)
        }
        let combinedHash = combined.isEmpty ? "" : Hashing.sha256(combined)
        return PayloadScanReport(
            hashedCount: hashes.count,
            unreadableCount: unreadable,
            unreadableIds: unreadableIds.sorted(),
            combinedHash: combinedHash
        )
    }

    private static func payloadFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "payload" {
                files.append(fileURL)
            }
        }
        return files
    }
}
