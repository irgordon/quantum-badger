import SwiftUI
import BadgerCore
import BadgerRuntime
import Observation

struct ConsoleView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: ConsoleViewModel?

    @State private var showArchiveSheet: Bool = false
    @State private var archiveEntries: [ConversationEntry] = []

    var body: some View {
        Group {
            if let vm {
                content(vm: vm)
            } else {
                ProgressView()
                    .task {
                        let viewModel = ConsoleViewModel(appState: appState)
                        self.vm = viewModel
                        await viewModel.loadConversationHistory()
                    }
            }
        }
    }

    @ViewBuilder
    private func content(vm: ConsoleViewModel) -> some View {
        @Bindable var vm = vm
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Assistant")
                .font(.title)
                .fontWeight(.semibold)

            StatusPill(
                modelRegistry: appState.modelCapabilities.catalog,
                modelSelection: appState.modelCapabilities.selectionStore,
                reachability: appState.reachability
            )

            if let notice = vm.compactionNotice {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").foregroundColor(.green)
                    Text(notice).font(.caption).foregroundColor(.secondary)
                }
            }

            ConsoleQuickStartCard()

            ConsoleContextView(
                entries: vm.conversationEntries,
                conversationHistoryStore: appState.conversationHistoryStore,
                archiveEntries: $archiveEntries,
                showArchiveSheet: $showArchiveSheet,
                onLoadHistory: { await vm.loadConversationHistory() }
            )

            GroupBox("Database Query Safety") {
                @Bindable var limitsStore = appState.toolLimitsStore
                HStack {
                    Text("Max DB query tokens")
                    Spacer()
                    Stepper(value: $limitsStore.dbQueryMaxTokens, in: 64...4096, step: 64) {
                        Text("\(limitsStore.dbQueryMaxTokens)")
                    }.labelsHidden()
                }
            }

            ConsoleInputView(
                prompt: $vm.prompt,
                allowPublicCloud: $vm.allowPublicCloudForThisRequest,
                isGenerating: vm.isGenerating,
                onMakePlan: { Task { await vm.makePlan() } },
                onAsk: { Task { await vm.submitPrompt() } },
                onStop: { vm.stopGeneration() },
                onSearchFiles: { Task { await vm.runLocalSearch() } }
            )

            if let plan = vm.activePlan {
                PlanView(
                    plan: plan,
                    results: vm.results,
                    exportNotice: vm.exportNotice,
                    runStep: { step in
                         Task { await vm.runStep(step) }
                    },
                    runAll: {
                         Task { await vm.runPlan() }
                    },
                    exportPlan: {
                         vm.exportPlan()
                    }
                )
            } else {
                ContentUnavailableView("No Plan", systemImage: "wand.and.stars", description: Text("Describe a task to get started."))
            }

            if !vm.assistantResponse.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Assistant").font(.headline)
                            if let msg = vm.assistantMessage {
                                SecurityStatusBadge(message: msg)
                            }
                        }
                        StreamingBufferView(text: vm.assistantResponse)
                    }
                }
            }
            
            WebResultsPanel(
                results: vm.webCards,
                notice: vm.webCardsNotice,
                message: vm.webCardsMessage
            )
            
            LocalSearchResultsPanel(
                matches: vm.searchMatches,
                bookmarkStore: appState.storageCapabilities.vaultStore, // Assuming VaultStore conforms or has bookmark features
                notice: vm.searchNotice,
                message: vm.localSearchMessage
            )

            SecureFileSaverView(
                locationName: $vm.saveLocationName,
                contents: $vm.saveContents,
                locationReference: $vm.saveLocationReference,
                notice: $vm.saveNotice,
                isPickerPresented: $vm.isSaveLocationPickerPresented,
                onWriteFile: { Task { await vm.writeSecureFile() } }
            )
        }
        .padding()
        .fileImporter(
            isPresented: $vm.isSaveLocationPickerPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                 if vm.saveLocationName.isEmpty { vm.saveLocationName = url.lastPathComponent }
                 vm.vaultStore.storeBookmark(label: vm.saveLocationName, url: url)
                 vm.saveLocationReference = vm.vaultStore.reference(forLabel: vm.saveLocationName)
            }
        }
        .onDisappear {
            vm.stopGeneration()
        }
    }
}
