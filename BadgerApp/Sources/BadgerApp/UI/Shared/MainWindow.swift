import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Main Window View

public struct MainWindowView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    @State private var selectedTab: AppTab? = .chat
    @State private var showingOnboarding = false
    @State private var showingSettings = false
    @State private var onboardingInitialStep: OnboardingViewModel.OnboardingStep = .welcome
    
    // UI State for the Chat
    @State private var chatMessages: [ChatMessage] = [
        ChatMessage(role: .system, content: "Quantum Badger initialized. Neural Engine ready.")
    ]
    
    public enum AppTab: String, Identifiable, CaseIterable {
        case chat = "Chat"
        case history = "History"
        public var id: String { rawValue }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTab: $selectedTab,
                showingSettings: $showingSettings,
                onClearConversation: clearConversation
            )
        } detail: {
            ZStack {
                switch selectedTab {
                case .chat:
                    ChatInterfaceView(messages: $chatMessages)
                case .history:
                    HistoryView()
                case .none:
                    ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
                }
            }
            .navigationTitle(selectedTab?.rawValue ?? "Quantum Badger")
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
                .frame(minWidth: 700, minHeight: 500)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(initialStep: onboardingInitialStep)
        }
        .task {
            if !UserDefaults.standard.bool(forKey: AppDefaultsKeys.onboardingCompleted) {
                showingOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgerNewConversationRequested)) { _ in
            selectedTab = .chat
            clearConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgerShowOnboardingRequested)) { _ in
            onboardingInitialStep = .welcome
            showingOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgerShowCloudSSORequested)) { _ in
            onboardingInitialStep = .cloudSSO
            showingOnboarding = true
        }
    }
    
    private func clearConversation() {
        withAnimation {
            chatMessages = [ChatMessage(role: .system, content: "Conversation cleared.")]
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Binding var selectedTab: MainWindowView.AppTab?
    @Binding var showingSettings: Bool
    var onClearConversation: () -> Void
    
    var body: some View {
        List(selection: $selectedTab) {
            Section("Workspace") {
                NavigationLink(value: MainWindowView.AppTab.chat) {
                    Label("Chat", systemImage: "message.fill")
                }
                
                NavigationLink(value: MainWindowView.AppTab.history) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Divider()
                
                // Clear Conversation Link
                Button(action: onClearConversation) {
                    Text("Clear Conversation")
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                
                // Settings Button
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("Badger")
    }
}

// MARK: - Chat Interface (Dashboard)

struct ChatInterfaceView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Binding var messages: [ChatMessage]
    
    @State private var prompt: String = ""
    
    // Status Bar State
    @State private var activeModelName: String = "No Model Loaded"
    @State private var isLocal: Bool = true
    @State private var tokenUsage: Int = 0
    @State private var vramUsage: Double = 0
    @State private var isGenerating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Scroll Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
            
            Divider()
            
            // Input Area
            HStack(alignment: .bottom) {
                TextField("Ask anything...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.blue.opacity(prompt.isEmpty || isGenerating ? 0.3 : 1.0))
                }
                .buttonStyle(.plain)
                .disabled(prompt.isEmpty || isGenerating)
            }
            .padding()
            .background(.regularMaterial)
            
            // Status Footer (Verbose Format)
            HStack(spacing: 16) {
                // Model Indicator with Words: (●) Local - Phi-4
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(isLocal ? .green : .blue)
                    
                    Text(isLocal ? "Local - \(activeModelName)" : "Cloud - \(activeModelName)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isLocal ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .cornerRadius(4)
                .help(isLocal ? "Running locally on Neural Engine" : "Running on Secure Cloud")
                
                Spacer()
                
                // Resource Stats
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                        Text(String(format: "%.1f GB", vramUsage))
                    }
                    
                    Divider().frame(height: 10)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                        Text("\(tokenUsage) toks")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
    
    private func sendMessage() {
        guard !prompt.isEmpty else { return }
        let command = prompt
        let userMsg = ChatMessage(role: .user, content: command)
        messages.append(userMsg)
        prompt = ""
        
        Task {
            await MainActor.run { isGenerating = true }
            defer { Task { @MainActor in isGenerating = false } }
            
            do {
                let result = try await coordinator.execute(
                    command: command,
                    source: .internalApp
                )
                await MainActor.run {
                    activeModelName = result.routingDecision.targetModel
                    isLocal = result.routingDecision.isLocal
                    tokenUsage = result.output.split(separator: " ").count
                    let aiMsg = ChatMessage(role: .assistant, content: result.output)
                    messages.append(aiMsg)
                }
            } catch {
                await MainActor.run {
                    let friendly = FriendlyErrorMapper.map(error)
                    let message = friendly.suggestion ?? friendly.message
                    let aiMsg = ChatMessage(role: .assistant, content: "Execution failed: \(message)")
                    messages.append(aiMsg)
                    activeModelName = "Unavailable"
                    isLocal = true
                }
            }
        }
    }
}

// MARK: - Chat Components

struct ChatBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer() }
            
            if !isUser {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 32)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(isUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(16)
            }
            
            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
            
            if !isUser { Spacer() }
        }
    }
}

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: MessageRole
    let content: String
    
    enum MessageRole: Sendable {
        case user, assistant, system
    }
}

// MARK: - History View (Placeholder)

struct HistoryView: View {
    var body: some View {
        ContentUnavailableView("History", systemImage: "clock.arrow.circlepath", description: Text("Your past conversations will appear here"))
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
}
