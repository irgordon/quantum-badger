import SwiftUI
import BadgerCore
import BadgerRuntime

struct ConsoleContextView: View {
    let entries: [ConversationEntry]
    let conversationHistoryStore: ConversationHistoryStore
    @Binding var archiveEntries: [ConversationEntry]
    @Binding var showArchiveSheet: Bool
    let onLoadHistory: () async -> Void

    var body: some View {
        GroupBox("Conversation Context") {
            if entries.isEmpty {
                Text("No conversation context yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(Array(entries.suffix(40))) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entryRoleLabel(entry.role))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if entry.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if entry.isSummary {
                                Image(systemName: "leaf")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        Text(entry.content)
                            .font(.caption)
                            .lineLimit(4)
                    }
                    .contextMenu {
                        Button(entry.isPinned ? "Unpin from Context" : "Pin in Context") {
                            Task {
                                await conversationHistoryStore.setPinned(id: entry.id, pinned: !entry.isPinned)
                                await onLoadHistory()
                            }
                        }
                        if entry.isSummary, let archiveID = entry.summaryArchiveID {
                            Button("Expand Original") {
                                Task {
                                    archiveEntries = await conversationHistoryStore.archivedEntries(archiveID: archiveID) ?? []
                                    showArchiveSheet = true
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
        }
    }

    private func entryRoleLabel(_ role: ConversationEntryRole) -> String {
        switch role {
        case .user: return "User"
        case .assistant: return "Assistant"
        case .toolCall: return "Tool Call"
        case .toolResult: return "Tool Result"
        case .system: return "System"
        }
    }
}
