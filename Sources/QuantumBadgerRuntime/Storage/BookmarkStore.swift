import Foundation
import Observation

@Observable
final class BookmarkStore {
    private(set) var entries: [BookmarkEntry]
    private let storageURL: URL

    init(storageURL: URL = AppPaths.bookmarksURL) {
        self.storageURL = storageURL
        self.entries = JSONStore.load([BookmarkEntry].self, from: storageURL, defaultValue: [])
    }

    func addEntries(_ newEntries: [BookmarkEntry]) {
        entries.append(contentsOf: newEntries)
        persist()
    }

    func removeEntry(_ entry: BookmarkEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func withResolvedURL<T>(for entry: BookmarkEntry, perform: (URL) throws -> T) rethrows -> T? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: entry.bookmarkData,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try perform(url)
        } catch {
            return nil
        }
    }

    private func persist() {
        try? JSONStore.save(entries, to: storageURL)
    }
}

struct BookmarkEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let bookmarkData: Data

    init(id: UUID = UUID(), name: String, bookmarkData: Data) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
    }
}
