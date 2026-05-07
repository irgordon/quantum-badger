import Foundation
import Testing
import SwiftUI
import Security
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

// MARK: - Mocks

final class MockStorageProvider: StorageProvider, @unchecked Sendable {
    var storedItems: [String: Any] = [:]
    var shouldThrowError: Bool = false

    func store(query: [String : Any]) throws {
        if shouldThrowError { throw KeyManagerError.saveFailed(-1) }
        let service = query[kSecAttrService as String] as? String ?? "default"
        storedItems[service] = query[kSecValueData as String]
    }

    func fetch(query: [String : Any]) throws -> AnyObject {
        if shouldThrowError { throw KeyManagerError.retrievalFailed(-1) }

        // Handle token exists check which sets kSecReturnData to false
        let returnData = query[kSecReturnData as String] as? Bool ?? true

        let service = query[kSecAttrService as String] as? String ?? "default"
        if let data = storedItems[service] {
            return returnData ? (data as AnyObject) : (true as AnyObject)
        }
        throw KeyManagerError.itemNotFound
    }

    func delete(query: [String : Any]) throws {
        if shouldThrowError { throw KeyManagerError.deletionFailed(-1) }
        let service = query[kSecAttrService as String] as? String ?? "default"
        if storedItems.removeValue(forKey: service) == nil {
            throw KeyManagerError.itemNotFound
        }
    }
}

final class MockKeyProvider: KeyProvider, @unchecked Sendable {
    var available: Bool = true

    func isAvailable() -> Bool { available }

    func generateKey(attributes: [String : Any]) throws -> SecKey {
        throw KeyManagerError.keyGenerationFailed
    }
}

// MARK: - OnboardingViewModel Tests

@Suite("OnboardingViewModel Tests")
struct OnboardingViewModelTests {

    @MainActor
    func makeViewModel() -> (OnboardingViewModel, KeyManager, MockStorageProvider, MockKeyProvider) {
        // Clear UserDefaults before each test for isolation
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppDefaultsKeys.onboardingCompleted)
        defaults.removeObject(forKey: AppDefaultsKeys.legacyHasCompletedOnboarding)
        defaults.removeObject(forKey: "privacyPolicyAccepted")
        defaults.removeObject(forKey: "safeModeDefault")

        let storage = MockStorageProvider()
        let keyProv = MockKeyProvider()
        let keyManager = KeyManager(keyProvider: keyProv, storageProvider: storage)
        let modelsViewModel = ModelsViewModel()
        let viewModel = OnboardingViewModel(keyManager: keyManager, modelsViewModel: modelsViewModel)
        return (viewModel, keyManager, storage, keyProv)
    }

    @Test("Initial state")
    @MainActor
    func testInitialState() async {
        let (viewModel, _, _, _) = makeViewModel()

        #expect(viewModel.currentStep == .welcome)
        #expect(viewModel.canProceedToNextStep == true)
        #expect(viewModel.hasAcceptedPrivacyPolicy == false)
        #expect(viewModel.onboardingCompleted == false)
        #expect(viewModel.selectedModelsToDownload.isEmpty)
        #expect(viewModel.showError == false)
    }

    @Test("Navigation flow")
    @MainActor
    func testNavigationFlow() async {
        let (viewModel, _, _, _) = makeViewModel()

        // Welcome -> Privacy Policy
        viewModel.nextStep()
        #expect(viewModel.currentStep == .privacyPolicy)

        // Privacy Policy -> (Next blocked without acceptance)
        viewModel.nextStep()
        #expect(viewModel.currentStep == .privacyPolicy)
        #expect(viewModel.showError == true)

        // Privacy Policy -> Local Models (after acceptance)
        viewModel.acceptPrivacyPolicy()
        viewModel.nextStep()
        #expect(viewModel.currentStep == .localModels)

        // Local Models -> Cloud SSO
        viewModel.nextStep()
        #expect(viewModel.currentStep == .cloudSSO)

        // Cloud SSO -> Completion
        viewModel.nextStep()
        #expect(viewModel.currentStep == .completion)

        // Completion -> (Finishes onboarding)
        viewModel.nextStep()
        #expect(viewModel.onboardingCompleted == true)
    }

    @Test("Navigation previous step")
    @MainActor
    func testNavigationPreviousStep() async {
        let (viewModel, _, _, _) = makeViewModel()

        viewModel.skipToStep(.localModels)
        #expect(viewModel.currentStep == .localModels)

        viewModel.previousStep()
        #expect(viewModel.currentStep == .privacyPolicy)

        viewModel.previousStep()
        #expect(viewModel.currentStep == .welcome)

        // Already at first step, should not change
        viewModel.previousStep()
        #expect(viewModel.currentStep == .welcome)
    }

    @Test("Skip to step")
    @MainActor
    func testSkipToStep() async {
        let (viewModel, _, _, _) = makeViewModel()

        viewModel.skipToStep(.cloudSSO)
        #expect(viewModel.currentStep == .cloudSSO)

        viewModel.skipToStep(.welcome)
        #expect(viewModel.currentStep == .welcome)
    }

    @Test("Accept privacy policy")
    @MainActor
    func testAcceptPrivacyPolicy() async {
        let (viewModel, _, _, _) = makeViewModel()

        viewModel.skipToStep(.privacyPolicy)
        #expect(viewModel.canProceedToNextStep == false)

        viewModel.acceptPrivacyPolicy()
        #expect(viewModel.hasAcceptedPrivacyPolicy == true)
        #expect(viewModel.canProceedToNextStep == true)

        #expect(UserDefaults.standard.bool(forKey: "privacyPolicyAccepted") == true)
    }

    @Test("Model selection")
    @MainActor
    func testModelSelection() async {
        let (viewModel, _, _, _) = makeViewModel()

        let model: ModelClass = .phi4
        viewModel.toggleModelSelection(model)
        #expect(viewModel.selectedModelsToDownload.contains(model))

        viewModel.toggleModelSelection(model)
        #expect(!viewModel.selectedModelsToDownload.contains(model))

        viewModel.selectRecommendedModel()
        #expect(viewModel.selectedModelsToDownload.contains(viewModel.recommendedModel))
    }

    @Test("Onboarding completion")
    @MainActor
    func testOnboardingCompletion() async {
        let (viewModel, _, _, _) = makeViewModel()

        viewModel.completeOnboarding()
        #expect(viewModel.onboardingCompleted == true)
        #expect(UserDefaults.standard.bool(forKey: AppDefaultsKeys.onboardingCompleted) == true)
    }

    @Test("Helper properties")
    @MainActor
    func testHelperProperties() async {
        let (viewModel, _, _, _) = makeViewModel()

        // Progress percentage
        viewModel.skipToStep(.welcome)
        #expect(viewModel.progressPercentage == 0.0)

        viewModel.skipToStep(.completion)
        #expect(viewModel.progressPercentage == 1.0)

        // Can skip step
        #expect(viewModel.canSkipStep(.welcome) == false)
        #expect(viewModel.canSkipStep(.privacyPolicy) == false)
        #expect(viewModel.canSkipStep(.localModels) == true)
        #expect(viewModel.canSkipStep(.cloudSSO) == true)
        #expect(viewModel.canSkipStep(.completion) == false)
    }

    @Test("Error handling")
    @MainActor
    func testErrorHandling() async {
        let (viewModel, _, _, _) = makeViewModel()

        // Trigger validation error
        viewModel.skipToStep(.privacyPolicy)
        viewModel.nextStep()

        #expect(viewModel.showError == true)
        #expect(viewModel.currentError != nil)

        viewModel.dismissError()
        #expect(viewModel.showError == false)
        #expect(viewModel.currentError == nil)
    }
}
