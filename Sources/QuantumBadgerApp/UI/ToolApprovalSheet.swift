import SwiftUI
import Observation
import QuantumBadgerRuntime

@MainActor
@Observable
final class ToolApprovalManager {
    var pendingContext: ToolApprovalContext?
    private let webFilterStore: WebFilterStore?

    init(webFilterStore: WebFilterStore? = nil) {
        self.webFilterStore = webFilterStore
    }

    func clearPending() {
        if let pending = pendingContext {
            Task { await pending.cancel() }
        }
        pendingContext = nil
    }

    func requestApproval(
        policy: PolicyEngine,
        toolName: String,
        input: [String: String],
        onApproved: @escaping @MainActor (_ approvalToken: String?) async -> Void
    ) async {
        let contract = ToolCatalog.contract(for: toolName)
        let requiresApproval = contract?.riskLevel == .medium || contract?.riskLevel == .high
        if !requiresApproval {
            await onApproved(nil)
            return
        }
        if await policy.isToolSessionGranted(toolName) {
            await onApproved(nil)
            return
        }

        var contextInput = input
        if toolName == "web.scout", contextInput["strictMode"] == nil {
            if let webFilterStore {
                contextInput["strictMode"] = webFilterStore.strictModeEnabled ? "true" : "false"
            }
        }

        pendingContext = ToolApprovalContext(
            toolName: toolName,
            contract: contract,
            input: contextInput,
            approveOnce: {
                let resourceKey = contextInput["pathRef"] ?? contextInput["connectionRef"]
                let token = await policy.issueApprovalToken(toolName: toolName, resourceKey: resourceKey)
                await onApproved(token)
                self.pendingContext = nil
            },
            approveSession: {
                await policy.grantToolSession(toolName)
                await onApproved(nil)
                self.pendingContext = nil
            },
            cancel: {
                await onApproved(nil)
                self.pendingContext = nil
            }
        )
    }
}

struct ToolApprovalContext: Identifiable {
    let id = UUID()
    let toolName: String
    let contract: ToolContract?
    let input: [String: String]
    let approveOnce: @MainActor () async -> Void
    let approveSession: @MainActor () async -> Void
    let cancel: @MainActor () async -> Void
}

struct ToolApprovalSheet: View {
    let context: ToolApprovalContext
    private let authManager = AuthenticationManager()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow this action?")
                .font(.title3)
                .fontWeight(.semibold)

            Text(primaryDescription)
                .font(.body)

            GroupBox("Details") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Impact:")
                        Text(riskText)
                            .fontWeight(.semibold)
                            .foregroundColor(riskColor)
                    }
                    if context.toolName == "message.send" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recipient: \(context.input["recipient"] ?? "Unknown")")
                            if let key = context.input["conversationKey"], !key.isEmpty {
                                Text("Conversation: \(key)")
                            }
                            Text("Message:")
                            Text(context.input["body"] ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(5)
                                .privacySensitive()
                        }
                    }
                    if context.toolName == "web.scout" {
                        HStack(spacing: 8) {
                            Text("Query: \(context.input["query"] ?? "Unknown")")
                            if context.input["strictMode"] == "true" {
                                Text("Strict Mode active")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                            }
                        }
                    }
                    ForEach(scopes, id: \.self) { scope in
                        Text("Scope: \(scope)")
                    }
                }
                .font(.caption)
            }

            HStack {
                Button("Allow Once") {
                    Task { await approveOnce() }
                }
                .buttonStyle(.borderedProminent)
                if allowsSessionApproval {
                    Button("Allow for Session") {
                        Task { await context.approveSession() }
                    }
                    .buttonStyle(.bordered)
                }
                Button("Cancel") {
                    Task { await context.cancel() }
                }
                .buttonStyle(.bordered)
            }

            if context.toolName == "filesystem.write" {
                Text("This action always requires confirmation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var primaryDescription: String {
        switch context.toolName {
        case "local.search":
            return "Quantum Badger will search only the folders you’ve allowed."
        case "filesystem.write":
            return "Quantum Badger wants to make changes to files you select."
        case "message.send":
            return "Quantum Badger will draft a message using your trusted contacts."
        case "web.scout":
            return "Quantum Badger will browse approved websites and summarize the results."
        default:
            return "Quantum Badger needs your permission to run this action."
        }
    }

    private var riskText: String {
        switch context.contract?.riskLevel {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        default:
            return "Low"
        }
    }

    private var riskColor: Color {
        switch context.contract?.riskLevel {
        case .high:
            return .red
        case .medium:
            return .orange
        default:
            return .secondary
        }
    }

    private var allowsSessionApproval: Bool {
        context.contract?.riskLevel != .high
    }

    private var scopes: [String] {
        guard let scopes = context.contract?.scopes, !scopes.isEmpty else {
            return ["No additional access beyond this action."]
        }
        return scopes.map { scopeDescription(for: $0) }
    }

    private func scopeDescription(for scope: String) -> String {
        switch scope {
        case "files.read":
            return "Read files inside the folders you chose"
        case "bookmarks.only":
            return "Only inside folders you’ve already approved"
        case "files.write":
            return "Change files you select"
        case "user.selected":
            return "Only in locations you choose"
        default:
            return scope
        }
    }

    

    @MainActor
    private func approveOnce() async {
        if context.contract?.riskLevel == .high {
            do {
                _ = try await authManager.authenticate(reason: "Confirm this secure action.")
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        await context.approveOnce()
    }
}
