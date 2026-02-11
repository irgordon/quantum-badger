import SwiftUI
import BadgerCore

struct HistorySidebar: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        List {
            Section("Current Session") {
                Button {
                    // Start new logic if we had one
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                
                Button {
                    coordinator.archiveConversation()
                } label: {
                    Label("Archive Session", systemImage: "archivebox")
                }
            }
            
            if !coordinator.conversationArchives.isEmpty {
                Section("History") {
                    ForEach(coordinator.conversationArchives) { archive in
                        Button {
                            coordinator.loadArchive(archive.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(archive.summary)
                                    .font(.body)
                                Text(archive.date.formatted(date: .numeric, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
