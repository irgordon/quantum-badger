import Foundation
import Testing
import SwiftUI
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

@Suite("Cloud Accounts Settings Tests")
struct CloudAccountsSettingsTests {
    
    @Test("Provider status creation")
    func testProviderStatus() async throws {
        let status = ProviderStatus(
            provider: .anthropic,
            isConnected: true,
            isAuthenticated: true,
            lastTested: Date(),
            testResult: .success(latency: 0.5)
        )
        
        #expect(status.provider == .anthropic)
        #expect(status.isConnected == true)
        #expect(status.isAuthenticated == true)
        #expect(status.displayStatus == "Connected")
    }
    
    @Test("Provider status display states")
    func testProviderStatusDisplay() async throws {
        let authenticated = ProviderStatus(provider: .openAI, isConnected: true, isAuthenticated: true)
        #expect(authenticated.displayStatus == "Connected")
        
        let connectedOnly = ProviderStatus(provider: .openAI, isConnected: true, isAuthenticated: false)
        #expect(connectedOnly.displayStatus == "Auth Required")
        
        let notConnected = ProviderStatus(provider: .openAI, isConnected: false, isAuthenticated: false)
        #expect(notConnected.displayStatus == "Not Connected")
    }
    
    @Test("Cloud provider display names")
    func testProviderDisplayNames() async throws {
        #expect(CloudProvider.anthropic.displayName == "Anthropic")
        #expect(CloudProvider.openAI.displayName == "OpenAI")
        #expect(CloudProvider.google.displayName == "Google")
        #expect(CloudProvider.applePCC.displayName == "Apple PCC")
    }
    
    @Test("Cloud provider icon names")
    func testProviderIcons() async throws {
        #expect(CloudProvider.anthropic.iconName == "a.circle.fill")
        #expect(CloudProvider.openAI.iconName == "o.circle.fill")
        #expect(CloudProvider.google.iconName == "g.circle.fill")
        #expect(CloudProvider.applePCC.iconName == "apple.logo")
    }
    
    @Test("Cloud provider brand colors")
    func testProviderBrandColors() async throws {
        #expect(CloudProvider.anthropic.brandColor == .orange)
        #expect(CloudProvider.openAI.brandColor == .green)
        #expect(CloudProvider.google.brandColor == .blue)
        #expect(CloudProvider.applePCC.brandColor == .gray)
    }
    
    @Test("Cloud provider dashboard URLs")
    func testProviderDashboardURLs() async throws {
        let anthropicURL = CloudProvider.anthropic.dashboardURL
        #expect(anthropicURL.absoluteString.contains("anthropic.com"))
        
        let openAIURL = CloudProvider.openAI.dashboardURL
        #expect(openAIURL.absoluteString.contains("openai.com"))
        
        let googleURL = CloudProvider.google.dashboardURL
        #expect(googleURL.absoluteString.contains("google.com"))
    }
    
    @Test("Cloud provider API key instructions")
    func testProviderInstructions() async throws {
        let anthropicInstructions = CloudProvider.anthropic.apiKeyInstructions
        #expect(anthropicInstructions.count == 4)
        #expect(anthropicInstructions[0].contains("Anthropic"))
        
        let openAIInstructions = CloudProvider.openAI.apiKeyInstructions
        #expect(openAIInstructions.count == 4)
        #expect(openAIInstructions[0].contains("OpenAI"))
    }
    
    @Test("Cloud accounts view model initialization")
    func testViewModelInit() async throws {
        let viewModel = CloudAccountsViewModel()
        #expect(viewModel.providerStatuses.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.showError == false)
    }
    
    @Test("Cloud accounts auth error creation")
    func testAuthError() async throws {
        let error = CloudAccountsViewModel.AuthError(
            message: "Test error",
            recoverySuggestion: "Try again",
            isRetryable: true
        )
        
        #expect(error.message == "Test error")
        #expect(error.recoverySuggestion == "Try again")
        #expect(error.isRetryable == true)
    }
    
    @Test("Settings section enum")
    func testSettingsSection() async throws {
        let sections = AppSettingsView.SettingsSection.allCases
        #expect(sections.count == 4)
        #expect(sections.contains(.general))
        #expect(sections.contains(.cloudAccounts))
        #expect(sections.contains(.privacy))
        #expect(sections.contains(.advanced))
        
        #expect(AppSettingsView.SettingsSection.general.icon == "gear")
        #expect(AppSettingsView.SettingsSection.cloudAccounts.icon == "cloud")
        #expect(AppSettingsView.SettingsSection.privacy.icon == "lock.shield")
        #expect(AppSettingsView.SettingsSection.advanced.icon == "gearshape.2")
    }
}

@Suite("Provider Status Test Result Tests")
struct ProviderStatusTestResultTests {
    
    @Test("Test result success")
    func testTestResultSuccess() async throws {
        let result = ProviderStatus.TestResult.success(latency: 0.45)
        
        if case .success(let latency) = result {
            #expect(latency == 0.45)
        } else {
            #expect(Bool(false))
        }
    }
    
    @Test("Test result failure")
    func testTestResultFailure() async throws {
        let result = ProviderStatus.TestResult.failure(message: "Network error")
        
        if case .failure(let message) = result {
            #expect(message == "Network error")
        } else {
            #expect(Bool(false))
        }
    }
}

@Suite("Cloud Provider Extension Tests")
struct CloudProviderExtensionTests {
    
    @Test("All providers have valid URLs")
    func testAllProviderURLs() async throws {
        for provider in [CloudProvider.anthropic, .openAI, .google, .applePCC] {
            let url = provider.dashboardURL
            #expect(url.scheme != nil)
            #expect(url.host != nil)
        }
    }
    
    @Test("All providers have instructions")
    func testAllProviderInstructions() async throws {
        for provider in [CloudProvider.anthropic, .openAI, .google] {
            let instructions = provider.apiKeyInstructions
            #expect(!instructions.isEmpty)
        }
    }
    
    @Test("Apple PCC has device auth instructions")
    func testApplePCCInstructions() async throws {
        let instructions = CloudProvider.applePCC.apiKeyInstructions
        #expect(instructions.count == 1)
        #expect(instructions[0].contains("device"))
    }
}