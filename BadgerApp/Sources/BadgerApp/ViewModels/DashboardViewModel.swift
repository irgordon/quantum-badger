import Foundation
import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Dashboard View Model

@MainActor
@Observable
public final class DashboardViewModel {
    
    // MARK: - Router Flow State
    
    public enum RouterFlowState: Equatable {
        case idle
        case receivingInput
        case sanitizing
        case analyzingIntent(progress: Double)
        case makingDecision
        case executingLocal(model: String)
        case executingCloud(provider: String)
        case completed(result: String)
        case error(message: String)
        
        var displayName: String {
            switch self {
            case .idle: return "Ready"
            case .receivingInput: return "Receiving Input..."
            case .sanitizing: return "Sanitizing..."
            case .analyzingIntent: return "Analyzing Intent..."
            case .makingDecision: return "Making Decision..."
            case .executingLocal(let model): return "Running Local (\(model))..."
            case .executingCloud(let provider): return "Using Cloud (\(provider))..."
            case .completed: return "Completed"
            case .error(let message): return "Error: \(message)"
            }
        }
        
        var isActive: Bool {
            switch self {
            case .idle, .completed, .error: return false
            default: return true
            }
        }
        
        var progress: Double {
            switch self {
            case .idle: return 0
            case .receivingInput: return 0.1
            case .sanitizing: return 0.2
            case .analyzingIntent(let p): return 0.2 + (p * 0.3)
            case .makingDecision: return 0.5
            case .executingLocal, .executingCloud: return 0.6
            case .completed: return 1.0
            case .error: return 1.0
            }
        }
    }
    
    // MARK: - Properties
    
    public var routerFlowState: RouterFlowState = .idle
    public var currentInput: String = ""
    public var currentOutput: String = ""
    
    // System Status
    public var vramStatus: VRAMStatus?
    public var thermalStatus: ThermalStatus?
    public var isSafeMode: Bool = false
    
    // Decision Tree Visualization
    public var lastDecision: RouterDecision?
    public var lastIntentAnalysis: IntentAnalysisResult?
    public var lastSanitizationResult: SanitizationResult?
    
    // History
    public var recentDecisions: [DecisionRecord] = []
    
    private let shadowRouter: ShadowRouter
    private let vramMonitor: VRAMMonitor
    private let thermalGuard: ThermalGuard
    private let policyManager: SecurityPolicyManager
    
    private var updateTimer: Timer?
    
    // MARK: - Types
    
    public struct DecisionRecord: Identifiable, Equatable {
        public let id = UUID()
        public let timestamp: Date
        public let input: String
        public let decision: RouterDecision
        public let executionTime: TimeInterval
        
        public var formattedTime: String {
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }
    }
    
    // MARK: - Initialization
    
    public init(
        shadowRouter: ShadowRouter = ShadowRouter(),
        vramMonitor: VRAMMonitor = VRAMMonitor(),
        thermalGuard: ThermalGuard = ThermalGuard(),
        policyManager: SecurityPolicyManager = SecurityPolicyManager()
    ) {
        self.shadowRouter = shadowRouter
        self.vramMonitor = vramMonitor
        self.thermalGuard = thermalGuard
        self.policyManager = policyManager
        
        Task {
            await startMonitoring()
        }
    }
    
    // MARK: - System Monitoring
    
    public func startMonitoring() async {
        // Initial update
        await updateSystemStatus()
        
        // Start timer for updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateSystemStatus()
            }
        }
    }
    
    public func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateSystemStatus() async {
        vramStatus = await vramMonitor.getCurrentStatus()
        thermalStatus = await thermalGuard.getCurrentStatus()
        isSafeMode = await policyManager.getPolicy().executionPolicy == .safeMode
    }
    
    // MARK: - Router Flow Execution
    
    public func processInput(_ input: String) async {
        guard !input.isEmpty else { return }
        
        let startTime = Date()
        currentInput = input
        
        // Step 1: Receiving Input
        routerFlowState = .receivingInput
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms visual delay
        
        // Step 2: Sanitizing
        routerFlowState = .sanitizing
        let sanitizer = InputSanitizer()
        let sanitizationResult = sanitizer.sanitize(input)
        lastSanitizationResult = sanitizationResult
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Step 3: Analyzing Intent (simulated progress)
        routerFlowState = .analyzingIntent(progress: 0.0)
        
        // Simulate progress updates
        for progress in stride(from: 0.0, to: 1.0, by: 0.25) {
            routerFlowState = .analyzingIntent(progress: progress)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Step 4: Making Decision
        routerFlowState = .makingDecision
        
        do {
            let decision = try await shadowRouter.route(prompt: sanitizationResult.sanitized)
            lastDecision = decision
            
            // Step 5: Executing
            switch decision {
            case .local(let modelClass):
                routerFlowState = .executingLocal(model: modelClass.rawValue)
                currentOutput = "[Local execution with \(modelClass.rawValue)]"
                
            case .cloud(let provider, let model):
                routerFlowState = .executingCloud(provider: provider.rawValue)
                currentOutput = "[Cloud execution via \(provider.rawValue) / \(model)]"
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Completed
            routerFlowState = .completed(result: currentOutput)
            
            // Add to history
            let record = DecisionRecord(
                timestamp: Date(),
                input: String(input.prefix(50)),
                decision: decision,
                executionTime: Date().timeIntervalSince(startTime)
            )
            recentDecisions.insert(record, at: 0)
            if recentDecisions.count > 10 {
                recentDecisions = Array(recentDecisions.prefix(10))
            }
            
        } catch {
            routerFlowState = .error(message: error.localizedDescription)
        }
    }
    
    public func reset() {
        routerFlowState = .idle
        currentInput = ""
        currentOutput = ""
    }
    
    // MARK: - Helper Methods
    
    public var vramDisplayText: String {
        guard let vram = vramStatus else { return "Unknown" }
        let availableGB = Double(vram.availableVRAM) / (1024 * 1024 * 1024)
        let totalGB = Double(vram.recommendedMaxWorkingSetSize) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB / %.1f GB", availableGB, totalGB)
    }
    
    public var vramUsagePercentage: Double {
        guard let vram = vramStatus else { return 0 }
        return vram.usageRatio
    }
    
    public var thermalDisplayText: String {
        guard let thermal = thermalStatus else { return "Unknown" }
        return thermal.state.rawValue
    }
    
    public var thermalColor: Color {
        guard let thermal = thermalStatus else { return .gray }
        switch thermal.state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
}
