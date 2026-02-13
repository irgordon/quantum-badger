import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Dashboard View

public struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var inputText: String = ""
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // System Status Cards
                systemStatusSection
                
                // Router Decision Tree Visualization
                decisionTreeSection
                
                // Test Input Section
                testInputSection
                
                // Recent Decisions
                recentDecisionsSection
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
        .navigationTitle("Dashboard")
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Shadow Router")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            
            Text("Real-time routing decisions and system status")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - System Status
    
    private var systemStatusSection: some View {
        HStack(spacing: 16) {
            // VRAM Card
            SystemStatusCard(
                title: "VRAM",
                value: viewModel.vramDisplayText,
                icon: "memorychip",
                color: vramColor,
                progress: viewModel.vramUsagePercentage
            )
            
            // Thermal Card
            SystemStatusCard(
                title: "Thermal",
                value: viewModel.thermalDisplayText,
                icon: "thermometer",
                color: viewModel.thermalColor,
                progress: nil
            )
            
            // Safe Mode Card
            SystemStatusCard(
                title: "Mode",
                value: viewModel.isSafeMode ? "Safe" : "Balanced",
                icon: viewModel.isSafeMode ? "lock.shield" : "shield",
                color: viewModel.isSafeMode ? .orange : .green,
                progress: nil
            )
        }
    }
    
    private var vramColor: Color {
        guard let status = viewModel.vramStatus else { return .gray }
        let ratio = status.usageRatio
        if ratio < 0.5 { return .green }
        if ratio < 0.75 { return .yellow }
        return .red
    }
    
    // MARK: - Decision Tree
    
    private var decisionTreeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Router Decision Tree")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.routerFlowState.isActive {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Flow Visualization
            DecisionFlowView(state: viewModel.routerFlowState)
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gradientForState(viewModel.routerFlowState))
                        .frame(width: geometry.size.width * viewModel.routerFlowState.progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.routerFlowState.progress)
                }
            }
            .frame(height: 8)
            
            // Status Text
            HStack {
                Image(systemName: statusIconForState(viewModel.routerFlowState))
                    .foregroundStyle(statusColorForState(viewModel.routerFlowState))
                
                Text(viewModel.routerFlowState.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if case .completed = viewModel.routerFlowState {
                    Text("Done")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Test Input
    
    private var testInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Routing")
                .font(.headline)
            
            TextField("Enter a prompt to see routing...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            
            HStack {
                Button("Reset") {
                    viewModel.reset()
                    inputText = ""
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.routerFlowState == .idle)
                
                Spacer()
                
                Button("Process") {
                    Task {
                        await viewModel.processInput(inputText)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.isEmpty || viewModel.routerFlowState.isActive)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Recent Decisions
    
    private var recentDecisionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Decisions")
                    .font(.headline)
                
                Spacer()
                
                Text("\(viewModel.recentDecisions.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if viewModel.recentDecisions.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Decisions", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Process a prompt to see routing decisions here")
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.recentDecisions) { record in
                        DecisionRecordRow(record: record)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helpers
    
    private func gradientForState(_ state: DashboardViewModel.RouterFlowState) -> LinearGradient {
        switch state {
        case .error:
            return LinearGradient(colors: [.red, .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        case .completed:
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.blue, .purple.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    private func statusIconForState(_ state: DashboardViewModel.RouterFlowState) -> String {
        switch state {
        case .idle: return "circle"
        case .receivingInput: return "arrow.down.circle"
        case .sanitizing: return "shield.checkered"
        case .analyzingIntent: return "brain.head.profile"
        case .makingDecision: return "arrow.triangle.branch"
        case .executingLocal: return "cpu"
        case .executingCloud: return "cloud"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private func statusColorForState(_ state: DashboardViewModel.RouterFlowState) -> Color {
        switch state {
        case .idle: return .secondary
        case .error: return .red
        case .completed: return .green
        default: return .blue
        }
    }
}

// MARK: - Supporting Views

struct SystemStatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let progress: Double?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Spacer()
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DecisionFlowView: View {
    let state: DashboardViewModel.RouterFlowState
    
    var body: some View {
        HStack(spacing: 0) {
            flowStep(
                icon: "text.quote",
                label: "Input",
                isActive: state != .idle,
                isCurrent: state == .receivingInput
            )
            
            flowArrow(isActive: state != .idle && state != .receivingInput)
            
            flowStep(
                icon: "shield.checkered",
                label: "Sanitize",
                isActive: state == .sanitizing || isAfterSanitizing(state),
                isCurrent: state == .sanitizing
            )
            
            flowArrow(isActive: isAfterSanitizing(state) && state != .sanitizing)
            
            flowStep(
                icon: "brain.head.profile",
                label: "Analyze",
                isActive: isAnalyzingOrAfter(state),
                isCurrent: state == .analyzingIntent
            )
            
            flowArrow(isActive: isAfterAnalysis(state))
            
            flowStep(
                icon: "arrow.triangle.branch",
                label: "Decide",
                isActive: isDecidingOrAfter(state),
                isCurrent: state == .makingDecision
            )
            
            flowArrow(isActive: isExecuting(state))
            
            flowStep(
                icon: isLocalExecution(state) ? "cpu" : "cloud",
                label: isLocalExecution(state) ? "Local" : "Cloud",
                isActive: isExecutingOrCompleted(state),
                isCurrent: isExecuting(state)
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    private func flowStep(icon: String, label: String, isActive: Bool, isCurrent: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .background(isActive ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isActive ? .blue : .secondary)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isCurrent ? Color.blue : Color.clear, lineWidth: 2)
                )
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func flowArrow(isActive: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(isActive ? .blue : .secondary.opacity(0.3))
            .frame(width: 20)
    }
    
    // Helper functions
    private func isAfterSanitizing(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .sanitizing, .analyzingIntent, .makingDecision, .executingLocal, .executingCloud, .completed, .error:
            return true
        default:
            return false
        }
    }
    
    private func isAnalyzingOrAfter(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .analyzingIntent, .makingDecision, .executingLocal, .executingCloud, .completed, .error:
            return true
        default:
            return false
        }
    }
    
    private func isAfterAnalysis(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .makingDecision, .executingLocal, .executingCloud, .completed, .error:
            return true
        default:
            return false
        }
    }
    
    private func isDecidingOrAfter(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .makingDecision, .executingLocal, .executingCloud, .completed, .error:
            return true
        default:
            return false
        }
    }
    
    private func isExecuting(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .executingLocal, .executingCloud:
            return true
        default:
            return false
        }
    }
    
    private func isExecutingOrCompleted(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        switch state {
        case .executingLocal, .executingCloud, .completed:
            return true
        default:
            return false
        }
    }
    
    private func isLocalExecution(_ state: DashboardViewModel.RouterFlowState) -> Bool {
        if case .executingLocal = state { return true }
        return false
    }
}

struct DecisionRecordRow: View {
    let record: DashboardViewModel.DecisionRecord
    
    var body: some View {
        HStack(spacing: 12) {
            // Decision Icon
            Image(systemName: record.decision.isLocal ? "cpu" : "cloud")
                .foregroundStyle(record.decision.isLocal ? .green : .blue)
                .frame(width: 32, height: 32)
                .background((record.decision.isLocal ? Color.green : Color.blue).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(record.input)
                    .lineLimit(1)
                    .font(.subheadline)
                
                HStack(spacing: 4) {
                    Text(record.decision.targetModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("·")
                        .foregroundStyle(.secondary)
                    
                    Text(record.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(String(format: "%.2fs", record.executionTime))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .frame(minWidth: 800, minHeight: 600)
}
