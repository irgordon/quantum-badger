import SwiftUI
import QuantumBadgerRuntime

struct MemoryTimelineView: View {
    let memoryManager: MemoryManager
    private let authManager = AuthenticationManager()

    @State private var entries: [MemoryEntry] = []
    @State private var selectedTrustLevel: MemoryTrustLevel?
    @State private var selectedProposal: MemoryEntry?
    @State private var showInspector: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Timeline")
                .font(.headline)

            if let issue = memoryManager.recoveryIssue {
                GroupBox("Memory Vault Needs Attention") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recoveryText(for: issue))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Reset Memory Vault") {
                            showResetConfirm = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            GroupBox("Pending Proposals") {
                if memoryManager.pendingProposals.isEmpty {
                    Text("No pending proposals right now.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(memoryManager.pendingProposals) { proposal in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(proposal.content)
                                .font(.body)
                            HStack {
                                Button("Review") {
                                    selectedProposal = proposal
                                    showInspector = true
                                }
                                .buttonStyle(.bordered)
                                Button("Store as Observation") {
                                    _ = memoryManager.storeProposalAsObservation(proposal)
                                    refreshTimeline()
                                }
                                .buttonStyle(.bordered)
                                Button("Dismiss") {
                                    memoryManager.dismissProposal(proposal)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Divider()
                    }
                }
            }

            Picker("Filter", selection: $selectedTrustLevel) {
                Text("All levels").tag(MemoryTrustLevel?.none)
                ForEach(MemoryTrustLevel.allCases) { level in
                    Text(level.displayName).tag(MemoryTrustLevel?.some(level))
                }
            }
            .pickerStyle(.menu)

            if entries.isEmpty {
                ContentUnavailableView(
                    "No memory yet",
                    systemImage: "brain",
                    description: Text("Quantum Badger learns as you work. Try searching for files or asking a question to see memories appear here.")
                )
            } else {
                List(filteredEntries) { entry in
                    MemoryRow(entry: entry)
                }
                .frame(minHeight: 220)
                .privacySensitive()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .task { await loadTimeline() }
        .sheet(isPresented: $showInspector) {
            if let proposal = selectedProposal {
                MemoryProposalInspectorView(
                    entry: proposal,
                    memoryManager: memoryManager,
                    authManager: authManager,
                    onComplete: {
                        showInspector = false
                        refreshTimeline()
                    }
                )
            }
        }
        .confirmationDialog(
            "Reset Memory Vault?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Memory Vault", role: .destructive) {
                memoryManager.resetVault()
                refreshTimeline()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases all stored memories on this Mac. This cannot be undone.")
        }
    }

    private func loadTimeline() async {
        entries = await memoryManager.loadTimelineEntries()
    }

    private func refreshTimeline() {
        Task { await loadTimeline() }
    }

    private func recoveryText(for issue: MemoryRecoveryIssue) -> String {
        switch issue {
        case .keyUnavailable:
            return "Your memory vault key is unavailable. Resetting will clear encrypted memory so Quantum Badger can start fresh."
        case .decryptionFailed:
            return "Memory entries couldn’t be decrypted. Resetting clears encrypted memory so Quantum Badger can start fresh."
        }
    }

    private var filteredEntries: [MemoryEntry] {
        guard let selectedTrustLevel else { return entries }
        return entries.filter { $0.trustLevel == selectedTrustLevel }
    }
}

private struct MemoryRow: View {
    let entry: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.trustLevel.displayName)
                    .font(.caption)
                    .foregroundColor(color)
                Spacer()
                Text(entry.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(entry.content)
                .font(.body)
            Text("Source: \(entry.sourceDetail)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch entry.trustLevel {
        case .level1UserAuthored:
            return .blue
        case .level2UserConfirmed, .level3Observational:
            return .yellow
        case .level4Summary:
            return .purple
        case .level5External:
            return .mint
        case .level0Ephemeral:
            return .gray
        }
    }
}

private struct MemoryProposalInspectorView: View {
    let entry: MemoryEntry
    let memoryManager: MemoryManager
    let authManager: AuthenticationManager
    let onComplete: @MainActor () -> Void

    @State private var editedContent: String
    @State private var errorMessage: String?

    init(
        entry: MemoryEntry,
        memoryManager: MemoryManager,
        authManager: AuthenticationManager,
        onComplete: @MainActor @escaping () -> Void
    ) {
        self.entry = entry
        self.memoryManager = memoryManager
        self.authManager = authManager
        self.onComplete = onComplete
        _editedContent = State(initialValue: entry.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Memory")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Edit this suggestion before saving it as a fact.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $editedContent)
                .frame(minHeight: 120)

            HStack {
                Button("Confirm as Fact") {
                    Task { await confirmAsFact() }
                }
                .buttonStyle(.borderedProminent)

                Button("Store as Observation") {
                    let updated = updatedEntry(trustLevel: .level3Observational)
                    _ = memoryManager.storeProposalAsObservation(updated)
                    Task { await onComplete() }
                }
                .buttonStyle(.bordered)

                Button("Dismiss") {
                    memoryManager.dismissProposal(entry)
                    Task { await onComplete() }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
    }

    @MainActor
    private func confirmAsFact() async {
        do {
            _ = try await authManager.authenticate(reason: "Secure this information in your memory vault.")
            let updated = updatedEntry(trustLevel: .level2UserConfirmed)
            let result = memoryManager.promoteProposalToConfirmed(updated)
            switch result {
            case .success:
                await onComplete()
            case .needsConfirmation, .failed:
                errorMessage = "Unable to secure the memory. Please try again."
            }
        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
        }
    }

    private func updatedEntry(trustLevel: MemoryTrustLevel) -> MemoryEntry {
        MemoryEntry(
            id: entry.id,
            trustLevel: trustLevel,
            content: editedContent.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceType: entry.sourceType,
            sourceDetail: entry.sourceDetail,
            createdAt: entry.createdAt,
            isConfirmed: true,
            confirmedAt: Date(),
            expiresAt: entry.expiresAt
        )
    }
}
