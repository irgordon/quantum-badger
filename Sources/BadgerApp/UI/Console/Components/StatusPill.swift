import SwiftUI
import BadgerCore
import BadgerRuntime
import BadgerRemote

struct StatusPill: View {
    let modelRegistry: ModelCatalog
    let modelSelection: ModelSelectionStore
    let reachability: NetworkReachabilityMonitor

    var body: some View {
        HStack(spacing: 12) {
            Label(modelModeText, systemImage: modelModeIcon)
            Label(networkText, systemImage: networkIcon)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .foregroundColor(.secondary)
    }

    private var modelModeText: String {
        activeModel()?.isCloud == true ? "Cloud" : "Local"
    }

    private var modelModeIcon: String {
        activeModel()?.isCloud == true ? "cloud" : "cpu"
    }

    private var networkText: String {
        switch reachability.scope {
        case .offline:
            return "Offline"
        case .localNetwork:
            return "Local Network"
        case .internet:
            return "Internet"
        }
    }

    private var networkIcon: String {
        switch reachability.scope {
        case .offline:
            return "wifi.slash"
        case .localNetwork:
            return "laptopcomputer"
        case .internet:
            return "globe"
        }
    }

    private func activeModel() -> ModelDescriptor? {
        guard let id = modelSelection.activeModelId else { return nil }
        return modelRegistry.models.first { $0.id == id }
    }
}
