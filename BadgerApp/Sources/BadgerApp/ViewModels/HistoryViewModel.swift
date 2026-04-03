import Foundation
import SwiftUI
import BadgerCore

// MARK: - History View Model

@MainActor
@Observable
public final class HistoryViewModel {

    // MARK: - Properties

    public var historyItems: [IndexedItem] = []
    public var searchResults: [SearchResult] = []
    public var searchText: String = ""
    public var isSearching: Bool = false
    public var isLoading: Bool = false

    private let coordinator: AppCoordinator

    // MARK: - Initialization

    public init(coordinator: AppCoordinator = .shared) {
        self.coordinator = coordinator
    }

    // MARK: - Actions

    /// Load recent history items
    public func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        historyItems = await coordinator.getRecentHistory(limit: 50)
    }

    /// Perform a search for historical interactions
    public func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true
        isLoading = true
        defer { isLoading = false }

        do {
            searchResults = try await coordinator.searchHistory(query: searchText)
        } catch {
            print("Search failed: \(error.localizedDescription)")
            searchResults = []
        }
    }

    /// Clear the current search
    public func clearSearch() {
        searchText = ""
        isSearching = false
        searchResults = []
    }

    /// Delete an interaction from history
    public func deleteInteraction(id: String) async {
        // Since AppCoordinator doesn't currently expose a delete method,
        // this is a placeholder. In a real app, you would add this to AppCoordinator.
        historyItems.removeAll { $0.id == id }
        searchResults.removeAll { $0.id == id }
    }
}
