import SwiftUI
import BadgerCore

// MARK: - History View

public struct HistoryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var viewModel: HistoryViewModel

    public init(coordinator: AppCoordinator = .shared) {
        _viewModel = State(initialValue: HistoryViewModel(coordinator: coordinator))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBar

            // Content
            Group {
                if viewModel.isLoading {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isSearching {
                    if viewModel.searchResults.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else {
                        searchResultsList
                    }
                } else if viewModel.historyItems.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your past conversations will appear here.")
                    )
                } else {
                    recentHistoryList
                }
            }
        }
        .task {
            await viewModel.loadHistory()
        }
        .navigationTitle("History")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search history...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await viewModel.performSearch() }
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
        .background(.bar)
    }

    // MARK: - Lists

    private var searchResultsList: some View {
        List {
            ForEach(viewModel.searchResults) { result in
                HistoryItemRow(
                    query: result.query,
                    response: result.response,
                    timestamp: result.timestamp,
                    source: result.source
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var recentHistoryList: some View {
        List {
            Section("Recent Conversations") {
                ForEach(viewModel.historyItems) { item in
                    HistoryItemRow(
                        query: item.query,
                        response: item.response,
                        timestamp: item.timestamp,
                        source: item.source,
                        category: item.category
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteInteraction(id: item.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Supporting Views

struct HistoryItemRow: View {
    let query: String
    let response: String
    let timestamp: Date
    let source: ExecutionContext.CommandSource
    var category: IndexedItem.InteractionCategory? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Category/Source Icon
                Image(systemName: iconForCategoryOrSource)
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                    .frame(width: 20)

                Text(query)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(response)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(source.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .cornerRadius(4)

                if let category = category {
                    Text(category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconForCategoryOrSource: String {
        if let category = category {
            switch category {
            case .question: return "questionmark.circle"
            case .code: return "cpu"
            case .creative: return "pencil.and.outline"
            case .analysis: return "chart.bar.xaxis"
            case .summary: return "text.alignleft"
            case .general: return "message"
            }
        }

        switch source {
        case .siri: return "waveform"
        case .shortcuts: return "command"
        case .internalApp: return "app.badge"
        default: return "message"
        }
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environmentObject(AppCoordinator.shared)
        .frame(width: 500, height: 600)
}
