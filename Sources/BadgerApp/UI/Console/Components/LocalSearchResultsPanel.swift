import SwiftUI
import BadgerCore
import BadgerRuntime

struct LocalSearchResultsPanel: View {
    let matches: [LocalSearchMatch]
    let bookmarkStore: BookmarkStore
    var notice: String? = nil
    let message: QuantumMessage?

    var body: some View {
        let status = message?.integrityStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Search Results")
                    .font(.headline)
                if let message {
                    SecurityStatusBadge(message: message)
                }
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if matches.isEmpty {
                Text("No results yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(matches, id: \.filePath) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Line \(match.lineNumber): \(match.linePreview)")
                            .font(.body)
                        Button("Open File") {
                            openMatch(match)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(minHeight: 180)
                .opacity(status == .unverified ? 0.6 : 1.0)
                .blur(radius: status == .unverified ? 0.5 : 0)
            }
        }
    }

    private func openMatch(_ match: LocalSearchMatch) {
         let matchURL = URL(fileURLWithPath: match.filePath)
        if let resolved = resolvedURL(for: matchURL) {
            NSWorkspace.shared.open(resolved)
        }
    }

    private func resolvedURL(for url: URL) -> URL? {
        let targetPath = url.standardizedFileURL.path
        for entry in bookmarkStore.entries {
            if let resolved = bookmarkStore.withResolvedURL(for: entry, action: { $0 }) {
                let folderPath = resolved.standardizedFileURL.path
                if targetPath.hasPrefix(folderPath) {
                    return url
                }
            }
        }
        return nil
    }
}
