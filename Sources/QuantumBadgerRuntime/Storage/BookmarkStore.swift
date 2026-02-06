import Foundation
import Observation

@Observable
final class BookmarkStore {
    private(set) var entries: [BookmarkEntry]
    private let storageURL: URL
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.bookmarksURL) {
        self.storageURL = storageURL
        self.entries = []
        loadAsync()
    }

    func addEntries(_ newEntries: [BookmarkEntry]) {
        didMutate = true
        entries.append(contentsOf: newEntries)
        persist()
    }

    func removeEntry(_ entry: BookmarkEntry) {
        didMutate = true
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

    private func loadAsync() {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let loaded = JSONStore.load([BookmarkEntry].self, from: storageURL, defaultValue: [])
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.entries = loaded
            }
        }
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
