import SwiftUI
import BadgerCore
import BadgerRuntime
import BadgerRemote

struct WebResultsPanel: View {
    let results: [WebScoutResult]
    let notice: String?
    let message: QuantumMessage?

    var body: some View {
        let status = message?.integrityStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Web Results")
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
            if results.isEmpty {
                Text("No web results yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List(results, id: \.url) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                        if !item.url.isEmpty {
                            Text(item.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !item.snippet.isEmpty {
                            Text(item.snippet)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(minHeight: 160)
                .opacity(status == .unverified ? 0.6 : 1.0)
                .blur(radius: status == .unverified ? 0.5 : 0)
            }
        }
    }
}
