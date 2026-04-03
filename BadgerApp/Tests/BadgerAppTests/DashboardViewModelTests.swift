import Foundation
import Testing
import SwiftUI
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

// MARK: - Mocks

final class MockShadowRouter: ShadowRouterProtocol {
    var routeResult: RouterDecision = .local(.phi4)
    var shouldThrow: Bool = false

    func route(prompt: String) async throws -> RouterDecision {
        if shouldThrow {
            throw ShadowRouterError.routingFailed("Mock error")
        }
        return routeResult
    }

    func quickRoute(prompt: String) async throws -> RouterDecision {
        return routeResult
    }
}

final class MockVRAMMonitor: VRAMMonitorProtocol {
    var status = VRAMStatus(recommendedMaxWorkingSetSize: 8 * 1024 * 1024 * 1024, currentAllocatedSize: 2 * 1024 * 1024 * 1024)

    func isAvailable() async -> Bool { true }
    func getCurrentStatus() async -> VRAMStatus { status }
    func getRecommendedMaxWorkingSetSize() async -> UInt64 { status.recommendedMaxWorkingSetSize }
    func canFitModel(requiredBytes: UInt64) async -> Bool { true }
    func getRecommendedQuantization() async throws -> QuantizationLevel { .q4 }
    func estimateMaxModelSize() async -> UInt64 { 4 * 1024 * 1024 * 1024 }
    func startMonitoring(callback: @escaping @Sendable (VRAMStatus) -> Void) async {}
    func stopMonitoring() async {}
    func recommendModelClass() async -> ModelClass { .phi4 }
    func getOptimalBatchSize() async -> Int { 1 }
}

final class MockThermalGuard: ThermalGuardProtocol {
    var status = ThermalStatus(state: .nominal, timestamp: Date())

    func getCurrentStatus() async -> ThermalStatus { status }
    func isUnderThermalStress() async -> Bool { false }
    func shouldThrottle() async -> Bool { false }
    func shouldSuspend() async -> Bool { false }
    func getRecommendedAction() async -> ThermalAction { .proceed }
    func getStateHistory() async -> [ThermalStateChange] { [] }
    func getThermalState() async -> SystemState.ThermalState { status.state }
    func createSystemState(ramAvailable: UInt64, ramTotal: UInt64, batteryState: SystemState.BatteryState, batteryLevel: Double?) async -> SystemState {
        SystemState(ramAvailable: ramAvailable, ramTotal: ramTotal, thermalState: status.state, batteryState: batteryState, batteryLevel: batteryLevel, cpuUtilization: 0)
    }
    func startMonitoring() async {}
    func stopMonitoring() async {}
    func checkThermalState() async {}
    func addDelegate(_ delegate: ThermalMonitorDelegate) async -> UUID { UUID() }
    func removeDelegate(_ id: UUID) async {}
}

final class MockSecurityPolicyManager: SecurityPolicyManagerProtocol {
    var policy = SecurityPolicy()

    func getPolicy() async -> SecurityPolicy { policy }
    func updatePolicy(_ policy: SecurityPolicy) async { self.policy = policy }
    func enableLockdown() async { policy = policy.enableLockdown() }
    func disableLockdown() async { policy = policy.disableLockdown() }
    func canPerformRemoteOperations() async -> Bool { policy.allowsRemoteOperations }
}

// MARK: - RouterFlowState Tests

@Suite("RouterFlowState Tests")
struct RouterFlowStateTests {

    @Test("Display Name mapping")
    func testDisplayNames() {
        #expect(DashboardViewModel.RouterFlowState.idle.displayName == "Ready")
        #expect(DashboardViewModel.RouterFlowState.receivingInput.displayName == "Receiving Input...")
        #expect(DashboardViewModel.RouterFlowState.sanitizing.displayName == "Sanitizing...")
        #expect(DashboardViewModel.RouterFlowState.analyzingIntent(progress: 0.5).displayName == "Analyzing Intent...")
        #expect(DashboardViewModel.RouterFlowState.makingDecision.displayName == "Making Decision...")
        #expect(DashboardViewModel.RouterFlowState.executingLocal(model: "Phi-4").displayName == "Running Local (Phi-4)...")
        #expect(DashboardViewModel.RouterFlowState.executingCloud(provider: "Anthropic").displayName == "Using Cloud (Anthropic)...")
        #expect(DashboardViewModel.RouterFlowState.completed(result: "Done").displayName == "Completed")
        #expect(DashboardViewModel.RouterFlowState.error(message: "Fail").displayName == "Error: Fail")
    }

    @Test("Is Active status")
    func testIsActive() {
        #expect(DashboardViewModel.RouterFlowState.idle.isActive == false)
        #expect(DashboardViewModel.RouterFlowState.receivingInput.isActive == true)
        #expect(DashboardViewModel.RouterFlowState.sanitizing.isActive == true)
        #expect(DashboardViewModel.RouterFlowState.analyzingIntent(progress: 0.5).isActive == true)
        #expect(DashboardViewModel.RouterFlowState.makingDecision.isActive == true)
        #expect(DashboardViewModel.RouterFlowState.executingLocal(model: "Phi-4").isActive == true)
        #expect(DashboardViewModel.RouterFlowState.executingCloud(provider: "Anthropic").isActive == true)
        #expect(DashboardViewModel.RouterFlowState.completed(result: "Done").isActive == false)
        #expect(DashboardViewModel.RouterFlowState.error(message: "Fail").isActive == false)
    }

    @Test("Progress calculation")
    func testProgress() {
        #expect(DashboardViewModel.RouterFlowState.idle.progress == 0.0)
        #expect(DashboardViewModel.RouterFlowState.receivingInput.progress == 0.1)
        #expect(DashboardViewModel.RouterFlowState.sanitizing.progress == 0.2)
        #expect(DashboardViewModel.RouterFlowState.analyzingIntent(progress: 0.0).progress == 0.2)
        #expect(DashboardViewModel.RouterFlowState.analyzingIntent(progress: 1.0).progress == 0.5)
        #expect(DashboardViewModel.RouterFlowState.makingDecision.progress == 0.5)
        #expect(DashboardViewModel.RouterFlowState.executingLocal(model: "Phi-4").progress == 0.6)
        #expect(DashboardViewModel.RouterFlowState.completed(result: "Done").progress == 1.0)
        #expect(DashboardViewModel.RouterFlowState.error(message: "Fail").progress == 1.0)
    }
}

// MARK: - DashboardViewModel Tests

@Suite("DashboardViewModel Tests")
struct DashboardViewModelTests {

    @MainActor
    func makeViewModel() -> (DashboardViewModel, MockShadowRouter, MockVRAMMonitor, MockThermalGuard, MockSecurityPolicyManager) {
        let router = MockShadowRouter()
        let vram = MockVRAMMonitor()
        let thermal = MockThermalGuard()
        let policy = MockSecurityPolicyManager()
        let viewModel = DashboardViewModel(
            shadowRouter: router,
            vramMonitor: vram,
            thermalGuard: thermal,
            policyManager: policy
        )
        return (viewModel, router, vram, thermal, policy)
    }

    @Test("Initial state")
    @MainActor
    func testInitialState() async {
        let (viewModel, _, _, _, _) = makeViewModel()

        #expect(viewModel.routerFlowState == .idle)
        #expect(viewModel.currentInput == "")
        #expect(viewModel.currentOutput == "")
        #expect(viewModel.recentDecisions.isEmpty)
    }

    @Test("Reset functionality")
    @MainActor
    func testReset() async {
        let (viewModel, _, _, _, _) = makeViewModel()

        viewModel.currentInput = "Test"
        viewModel.currentOutput = "Result"
        viewModel.routerFlowState = .completed(result: "Result")

        viewModel.reset()

        #expect(viewModel.routerFlowState == .idle)
        #expect(viewModel.currentInput == "")
        #expect(viewModel.currentOutput == "")
    }

    @Test("System status display helpers")
    @MainActor
    func testSystemStatusHelpers() async {
        let (viewModel, _, _, _, _) = makeViewModel()

        // VRAM
        viewModel.vramStatus = VRAMStatus(recommendedMaxWorkingSetSize: 16 * 1024 * 1024 * 1024, currentAllocatedSize: 4 * 1024 * 1024 * 1024)
        #expect(viewModel.vramDisplayText.contains("8.0 GB / 16.0 GB"))
        #expect(viewModel.vramUsagePercentage == 0.25)

        // Thermal
        viewModel.thermalStatus = ThermalStatus(state: .nominal, timestamp: Date())
        #expect(viewModel.thermalDisplayText == "Nominal")
        #expect(viewModel.thermalColor == .green)

        viewModel.thermalStatus = ThermalStatus(state: .critical, timestamp: Date())
        #expect(viewModel.thermalColor == .red)
    }

    @Test("Process input ignores empty strings")
    @MainActor
    func testProcessInputEmpty() async {
        let (viewModel, _, _, _, _) = makeViewModel()

        await viewModel.processInput("")
        #expect(viewModel.routerFlowState == .idle)
    }

    @Test("Process input success flow")
    @MainActor
    func testProcessInputSuccess() async {
        let (viewModel, router, _, _, _) = makeViewModel()
        router.routeResult = .local(.phi4)

        // Use a Task to monitor state transitions if needed, but for now we'll check the end state
        await viewModel.processInput("Hello World")

        #expect(viewModel.currentInput == "Hello World")
        if case .completed(let result) = viewModel.routerFlowState {
            #expect(result.contains("Local execution with Phi-4"))
        } else {
            Issue.record("Expected completed state, got \(viewModel.routerFlowState)")
        }

        #expect(viewModel.recentDecisions.count == 1)
        #expect(viewModel.recentDecisions[0].input == "Hello World")
    }

    @Test("Process input error flow")
    @MainActor
    func testProcessInputError() async {
        let (viewModel, router, _, _, _) = makeViewModel()
        router.shouldThrow = true

        await viewModel.processInput("Cause Error")

        if case .error(let message) = viewModel.routerFlowState {
            #expect(message == "Mock error")
        } else {
            Issue.record("Expected error state, got \(viewModel.routerFlowState)")
        }
    }
}
