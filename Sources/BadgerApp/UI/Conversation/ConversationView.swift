import SwiftUI
import BadgerCore
import BadgerRuntime

struct ConversationView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Message List
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(coordinator.conversationHistory, id: \.version) { entry in
                            MessageBubble(entry: entry)
                        }
                    }
                    .padding()
                }
                .onChange(of: coordinator.conversationHistory.count) { _ in
                    if let last = coordinator.conversationHistory.last {
                        withAnimation {
                            proxy.scrollTo(last.version, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Onboarding Card
            ConsoleQuickStartCard()
            
            // MARK: - Input Area
            
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask Quantum Badger...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        submit()
                    }
                
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command) // Cmd+Enter to send
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(coordinator.selectedModel?.name ?? "Quantum Badger")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ModelStatusIndicator()
            }
        }
    }
    
    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        coordinator.submitTextCommand(text)
        inputText = ""
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let entry: QuantumMessage
    
    var isUser: Bool { entry.source == .user }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer() }
            
            if !isUser {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack {
                    if !isUser {
                        Text(roleName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Integrity Badge (Cryptographic Visibility)
                    if !isUser {
                        integrityBadge
                    }
                    
                    // Kind Badge
                    if entry.kind != .text {
                        kindBadge
                    }
                }
                
                Text(entry.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(bubbleColor)
                    .foregroundStyle(textColor)
                    .cornerRadius(12)
                
                // Render Tool Outputs
                if let matches = entry.localMatches, !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(matches.prefix(3), id: \.path) { match in
                            Text("📄 \(URL(fileURLWithPath: match.path).lastPathComponent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
            
            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            
            if !isUser { Spacer() }
        }
    }
    
    @ViewBuilder
    var integrityBadge: some View {
        switch entry.integrityStatus() {
        case .verified:
            Image(systemName: "checkmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .help("Content verified by Secure Enclave")
        case .unverified:
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .help("Content signature invalid or missing")
        case .identityUnavailable:
            Image(systemName: "xmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.gray)
                .help("Identity root unavailable")
        }
    }
    
    @ViewBuilder
    var kindBadge: some View {
        switch entry.kind {
        case .toolError:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .toolNotice:
            Image(systemName: "info.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .localSearchResults:
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .webScoutResults:
            Image(systemName: "globe")
                .font(.caption2)
                .foregroundStyle(.cyan)
        default:
            EmptyView()
        }
    }
    
    var iconName: String {
        switch entry.source {
        case .assistant: return "brain.head.profile"
        case .system: return "gearshape.fill"
        case .summary: return "doc.text.fill"
        case .tool: return "hammer.fill"
        default: return "questionmark.circle"
        }
    }
    
    var iconColor: Color {
        switch entry.source {
        case .assistant: return .accentColor
        case .system: return .orange
        case .summary: return .purple
        case .tool: return .blue
        default: return .secondary
        }
    }
    
    var bubbleColor: Color {
        // Different color for errors
        if entry.kind == .toolError { return Color.red.opacity(0.1) }
        return isUser ? .accentColor : Color(nsColor: .controlBackgroundColor)
    }
    
    var textColor: Color {
        isUser ? .white : .primary
    }
    
    var roleName: String {
        switch entry.source {
        case .assistant: return "Badger"
        case .system: return "System"
        case .summary: return "Summary"
        case .tool: return entry.toolName ?? "Tool"
        default: return ""
        }
    }
}

// MARK: - Status Indicator

struct ModelStatusIndicator: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            Text(coordinator.systemStatus.activeModelLocation == .local ? "Local" : "Cloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("Inference Location")
    }
}
