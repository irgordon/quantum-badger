import Foundation

struct LocalSearchMatch: Codable, Sendable {
    let filePath: String
    @Coerced var lineNumber: Int
    let linePreview: String
}

enum LocalSearchStopReason: String, Codable {
    case completed
    case limitReached
    case cancelled
}

struct LocalSearchRunResult {
    let count: Int
    let stopReason: LocalSearchStopReason
}

enum LocalSearchTool {
    static func run(
        query: String,
        bookmarkStore: BookmarkStore,
        maxMatches: Int = 100,
        maxFileBytes: Int = 2_000_000
    ) -> [LocalSearchMatch] {
        var matches: [LocalSearchMatch] = []
        _ = runStreaming(
            query: query,
            bookmarkStore: bookmarkStore,
            maxMatches: maxMatches,
            maxFileBytes: maxFileBytes
        ) { match in
            matches.append(match)
            return true
        }
        return matches
    }

    static func runStreaming(
        query: String,
        bookmarkStore: BookmarkStore,
        maxMatches: Int = 100,
        maxFileBytes: Int = 2_000_000,
        onMatch: (LocalSearchMatch) -> Bool
    ) -> LocalSearchRunResult {
        let loweredQuery = query.lowercased()
        var matchCount = 0
        var stopReason: LocalSearchStopReason = .completed

        for entry in bookmarkStore.entries {
            if Task.isCancelled {
                stopReason = .cancelled
                break
            }
            _ = bookmarkStore.withResolvedURL(for: entry) { folderURL in
                let enumerator = FileManager.default.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                while let url = enumerator?.nextObject() as? URL {
                    if Task.isCancelled {
                        stopReason = .cancelled
                        break
                    }
                    if matchCount >= maxMatches {
                        stopReason = .limitReached
                        break
                    }
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true else { continue }
                    let size = values.fileSize ?? 0
                    if size > maxFileBytes { continue }
                    autoreleasepool {
                        guard let data = try? Data(contentsOf: url),
                              let content = String(data: data, encoding: .utf8) else { return }

                        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                        for (index, line) in lines.enumerated() {
                            if Task.isCancelled {
                                stopReason = .cancelled
                                return
                            }
                            if matchCount >= maxMatches {
                                stopReason = .limitReached
                                return
                            }
                            if line.lowercased().contains(loweredQuery) {
                                let preview = line.prefix(160)
                                let match = LocalSearchMatch(
                                    filePath: url.path,
                                    lineNumber: index + 1,
                                    linePreview: String(preview)
                                )
                                matchCount += 1
                                if !onMatch(match) {
                                    stopReason = .limitReached
                                    return
                                }
                            }
                        }
                    }
                    if stopReason == .cancelled {
                        break
                    }
                }
            }
        }

        return LocalSearchRunResult(count: matchCount, stopReason: stopReason)
    }
}
