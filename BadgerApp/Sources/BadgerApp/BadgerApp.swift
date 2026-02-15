import Foundation
import SwiftUI
import BadgerCore
import BadgerRuntime

public enum AppDefaultsKeys {
    public static let onboardingCompleted = "onboardingCompleted"
    public static let legacyHasCompletedOnboarding = "hasCompletedOnboarding"
}

extension Notification.Name {
    static let badgerNewConversationRequested = Notification.Name("badger.newConversationRequested")
    static let badgerShowOnboardingRequested = Notification.Name("badger.showOnboardingRequested")
    static let badgerShowCloudSSORequested = Notification.Name("badger.showCloudSSORequested")
}

// MARK: - BadgerApp Entry Point & API

public enum BadgerApp {
    public static let version = "1.0.0"
    
    /// Initializes the core runtime services.
    /// Must be called early in the app lifecycle.
    public static func initialize() async throws {
        // Ensure Runtime is ready
        try await BadgerRuntime.initialize()
        
        // Clean up old temporary files from formatting tasks
        let formatter = ResponseFormatter()
        try await formatter.cleanupOldFiles()
        
        print("BadgerApp v\(version) initialized")
    }
}

// MARK: - Type Exports (Unified Surface)

// Coordinators & Context
public typealias BadgerAppCoordinator = AppCoordinator
public typealias BadgerExecutionContext = ExecutionContext
public typealias BadgerCommandExecutionResult = CommandExecutionResult
public typealias BadgerFormattedOutput = FormattedOutput

// Intents & Commands
public typealias BadgerProcessRemoteCommand = ProcessRemoteCommand
public typealias BadgerGetSystemStatus = GetSystemStatus
public typealias BadgerAskQuestion = AskQuestion
public typealias BadgerCommandSourceParameter = CommandSourceParameter
// Note: AppShortcuts is defined in AppShortcuts.swift

// Formatting
public typealias BadgerResponseFormatter = ResponseFormatter
public typealias BadgerFormatDetectionResult = FormatDetectionResult

// Search
public typealias BadgerSearchIndexer = SearchIndexer
public typealias BadgerIndexedItem = IndexedItem
public typealias BadgerSearchResult = SearchResult

// Services & Runtime
public typealias BadgerWebBrowserService = WebBrowserService
public typealias BadgerFetchedContent = FetchedContent
public typealias BadgerBrowserSecurityPolicy = BrowserSecurityPolicy

// Privacy
public typealias BadgerPrivacyEgressFilter = PrivacyEgressFilter
public typealias BadgerSensitiveDataType = PrivacyEgressFilter.SensitiveDataType
public typealias BadgerPrivacyConfiguration = PrivacyEgressFilter.Configuration

// Router
public typealias BadgerShadowRouter = ShadowRouter
public typealias BadgerIntentAnalysisResult = IntentAnalysisResult
public typealias BadgerIntentCategory = IntentCategory
public typealias BadgerSafetyFlag = SafetyFlag
public typealias BadgerRoutingContext = RoutingContext

// Execution
public typealias BadgerHybridExecutionManager = HybridExecutionManager
public typealias BadgerHybridExecutionResult = HybridExecutionResult
public typealias BadgerExecutionConfiguration = ExecutionConfiguration
public typealias BadgerExecutionPhase = ExecutionPhase
public typealias BadgerExecutionProgress = ExecutionProgress

// Note: Unified Inference types are internal implementation details

// View Models
public typealias BadgerDashboardViewModel = DashboardViewModel
public typealias BadgerModelsViewModel = ModelsViewModel
public typealias BadgerOnboardingViewModel = OnboardingViewModel
public typealias BadgerCloudAccountsViewModel = CloudAccountsViewModel

// UI Views
public typealias BadgerDashboardView = DashboardView
public typealias BadgerModelsView = ModelsView
public typealias BadgerOnboardingView = OnboardingView
public typealias BadgerMainWindowView = MainWindowView
public typealias BadgerAppSettingsView = AppSettingsView
public typealias BadgerCloudAccountsSettingsView = CloudAccountsSettingsView

// Error Handling
public typealias BadgerFriendlyErrorMapper = FriendlyErrorMapper
public typealias BadgerFriendlyErrorView = FriendlyErrorView

// MARK: - Convenience Methods

extension BadgerApp {
    
    /// Quick entry point for Shortcuts/Siri integration.
    /// Uses the shared coordinator to execute commands.
    @MainActor
    public static func processCommand(
        _ command: String,
        source: ExecutionContext.CommandSource = .shortcuts
    ) async throws -> String {
        let coordinator = AppCoordinator.shared
        let result = try await coordinator.execute(command: command, source: source)
        return result.output
    }
    
    /// Process with file output option for automation.
    @MainActor
    public static func processCommandWithFile(
        _ command: String,
        source: ExecutionContext.CommandSource = .shortcuts
    ) async throws -> (text: String, fileURL: URL?) {
        let coordinator = AppCoordinator.shared
        let result = try await coordinator.execute(command: command, source: source)
        return (result.output, result.formattedOutput?.fileURL)
    }
}

// MARK: - App Structure

@main
@MainActor
public struct QuantumBadgerApp: App {
    
    /// The shared app coordinator, initialized as StateObject for proper lifecycle management
    @StateObject private var coordinator = AppCoordinator.shared
    
    /// Track if user has completed onboarding
    @AppStorage(AppDefaultsKeys.onboardingCompleted) private var hasCompletedOnboarding = false
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainWindowView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(coordinator)
            .task {
                // Bootstrap the runtime asynchronously when the window appears
                do {
                    try await BadgerApp.initialize()
                } catch {
                    print("CRITICAL BOOTSTRAP FAILURE: \(error)")
                    // In production, show error UI to user
                }
            }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Quantum Badger") {
                    // Show about panel
                }
            }
            
            CommandMenu("Quantum Badger") {
                Button("New Conversation") {
                    NotificationCenter.default.post(name: .badgerNewConversationRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Run Onboarding Again") {
                    NotificationCenter.default.post(name: .badgerShowOnboardingRequested, object: nil)
                }
                
                Button("Process Selected Text") {
                    // Process from clipboard
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Show Dashboard") {
                    // Navigate to dashboard
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Show Models") {
                    // Navigate to models
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Divider()
                
                Button("Toggle Safe Mode") {
                    Task {
                        // Toggle safe mode via coordinator
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        
        // Settings Window
        Settings {
            AppSettingsView()
                .frame(minWidth: 700, minHeight: 500)
                .environmentObject(coordinator)
        }
    }
}
