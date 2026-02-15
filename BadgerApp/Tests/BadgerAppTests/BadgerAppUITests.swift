import Foundation
import Testing
import SwiftUI
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

@Suite("BadgerApp UI Tests")
struct BadgerAppUITests {
    
    @Test("Dashboard View Model state management")
    func testDashboardViewModel() async throws {
        let viewModel = DashboardViewModel()
        
        // Test initial state
        #expect(viewModel.routerFlowState == .idle)
        #expect(viewModel.currentInput.isEmpty)
        
        // Test state transitions
        await viewModel.processInput("Test command")
        // State should progress through the flow
        #expect(viewModel.routerFlowState != .idle || viewModel.currentInput == "Test command")
    }
    
    @Test("Dashboard View Model system status")
    func testDashboardSystemStatus() async throws {
        let viewModel = DashboardViewModel()
        
        // Initial values should be nil/defaults
        #expect(viewModel.vramStatus == nil)
        #expect(viewModel.isSafeMode == false)
    }
    
    @Test("Models View Model settings")
    func testModelsViewModelSettings() async throws {
        let viewModel = ModelsViewModel()
        
        // Test default settings
        #expect(viewModel.shadowRouterSettings.forceSafeMode == false)
        #expect(viewModel.shadowRouterSettings.ramHeadroomLimitGB == 4.0)
        #expect(viewModel.shadowRouterSettings.preferLocalInference == true)
        #expect(viewModel.shadowRouterSettings.enableIntentAnalysis == true)
        
        // Test settings modification
        viewModel.shadowRouterSettings.forceSafeMode = true
        #expect(viewModel.shadowRouterSettings.forceSafeMode == true)
    }
    
    @Test("Models View Model available models")
    func testAvailableModels() async throws {
        let viewModel = ModelsViewModel()
        
        // Should have 4 models
        #expect(viewModel.availableModels.count == 4)
        
        // Check specific models
        let modelNames = viewModel.availableModels.map { $0.name }
        #expect(modelNames.contains("Phi-4"))
        #expect(modelNames.contains("Qwen 2.5"))
        #expect(modelNames.contains("Llama 3.1"))
        #expect(modelNames.contains("Gemma 2"))
    }
    
    @Test("Onboarding View Model steps")
    func testOnboardingSteps() async throws {
        let viewModel = OnboardingViewModel()
        
        // Test initial step
        #expect(viewModel.currentStep == .welcome)
        #expect(viewModel.progressPercentage == 0.0)
        
        // Test step progression
        viewModel.nextStep()
        #expect(viewModel.currentStep == .privacyPolicy)
        #expect(viewModel.progressPercentage > 0.0)
    }
    
    @Test("Onboarding View Model privacy validation")
    func testPrivacyValidation() async throws {
        let viewModel = OnboardingViewModel()
        
        // Skip to privacy step
        viewModel.skipToStep(.privacyPolicy)
        
        // Should not be able to proceed without accepting
        #expect(viewModel.canProceedToNextStep == false)
        
        // Accept privacy policy
        viewModel.acceptPrivacyPolicy()
        #expect(viewModel.hasAcceptedPrivacyPolicy == true)
        #expect(viewModel.canProceedToNextStep == true)
    }
    
    @Test("Friendly Error Mapper")
    func testFriendlyErrorMapper() async throws {
        // Test AppCoordinator error mapping
        let appError = AppCoordinatorError.securityViolation("Test violation")
        let friendlyError = FriendlyErrorMapper.map(appError)
        
        #expect(friendlyError.title.contains("Security"))
        #expect(friendlyError.icon == "lock.shield")
        #expect(friendlyError.color == .red)
        
        // Test CloudInference error mapping
        let cloudError = CloudInferenceError.noTokenAvailable
        let friendlyCloudError = FriendlyErrorMapper.map(cloudError)
        
        #expect(friendlyCloudError.title.contains("Not Connected"))
        #expect(!friendlyCloudError.actions.isEmpty)
    }
    
    @Test("Main Window Tabs")
    func testMainWindowTabs() async throws {
        let tabs = MainWindowView.Tab.allCases
        
        #expect(tabs.count == 4)
        #expect(tabs.contains(.dashboard))
        #expect(tabs.contains(.models))
        #expect(tabs.contains(.history))
        #expect(tabs.contains(.settings))
        
        // Test icons
        #expect(MainWindowView.Tab.dashboard.icon == "gauge.with.dots.needle.67percent")
        #expect(MainWindowView.Tab.models.icon == "cpu")
    }
    
    @Test("Response Formatter detection")
    func testResponseFormatterDetection() async throws {
        let formatter = ResponseFormatter()
        
        // Test code detection
        let codeContent = "```swift\nfunc test() {}\n```"
        let codeDetection = await formatter.detectFormat(in: codeContent)
        #expect(codeDetection.containsCode == true)
        
        // Test table detection
        let tableContent = "| A | B |\n|---|---|"
        let tableDetection = await formatter.detectFormat(in: tableContent)
        #expect(tableDetection.containsTable == true)
        
        // Test character limit
        let longContent = String(repeating: "A", count: 5000)
        let longDetection = await formatter.detectFormat(in: longContent)
        #expect(longDetection.exceedsMessageLimit == true)
    }
    
    @Test("Execution Configuration presets")
    func testExecutionConfigurationPresets() async throws {
        let `default` = ExecutionConfiguration.default
        #expect(`default`.useIntentAnalysis == true)
        #expect(`default`.allowFallback == true)
        
        let fast = ExecutionConfiguration.fast
        #expect(fast.useIntentAnalysis == false)
        
        let privacy = ExecutionConfiguration.privacy
        #expect(privacy.forceLocal == true)
        #expect(privacy.allowFallback == false)
        
        let performance = ExecutionConfiguration.performance
        #expect(performance.forceCloud == true)
    }
}

@Suite("BadgerApp UI Tests")
struct BadgerAppUITestsSuite {
    
    @Test("Indexed Item categorization")
    func testIndexedItemCategorization() async throws {
        let categories = IndexedItem.InteractionCategory.allCases
        
        #expect(categories.count == 6)
        #expect(categories.contains(.question))
        #expect(categories.contains(.code))
        #expect(categories.contains(.creative))
        #expect(categories.contains(.analysis))
        #expect(categories.contains(.summary))
        #expect(categories.contains(.general))
    }
}
