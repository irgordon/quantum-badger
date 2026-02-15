import Foundation
import SwiftUI
import AuthenticationServices
import BadgerCore
import BadgerRuntime

// MARK: - Onboarding View Model

@MainActor
@Observable
public final class OnboardingViewModel: NSObject, ObservableObject {
    
    // MARK: - Onboarding Steps
    
    public enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case privacyPolicy = 1
        case localModels = 2
        case cloudSSO = 3
        case completion = 4
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to Quantum Badger"
            case .privacyPolicy: return "Privacy & Security"
            case .localModels: return "Local AI Models"
            case .cloudSSO: return "Cloud Services"
            case .completion: return "You're All Set"
            }
        }
        
        var description: String {
            switch self {
            case .welcome:
                return "Your sovereign AI assistant. Private by design, powerful by default."
            case .privacyPolicy:
                return "Your data never leaves your device unless you explicitly choose cloud inference."
            case .localModels:
                return "Download AI models to run entirely on your Mac. No internet required."
            case .cloudSSO:
                return "Optionally connect cloud providers for advanced capabilities."
            case .completion:
                return "You're ready to experience truly private AI assistance."
            }
        }
    }
    
    // MARK: - Properties
    
    public var currentStep: OnboardingStep = .welcome
    public var canProceedToNextStep: Bool = true
    
    // Privacy Step
    public var hasAcceptedPrivacyPolicy: Bool = false
    public var enableSafeModeByDefault: Bool = false
    
    // Local Models Step
    public var selectedModelsToDownload: Set<ModelClass> = []
    public var recommendedModel: ModelClass = .qwen25
    
    // Cloud SSO Step
    public var connectedProviders: Set<CloudProvider> = []
    public var isAuthenticating: Bool = false
    public var currentAuthenticatingProvider: CloudProvider?
    
    // Completion
    public var onboardingCompleted: Bool = false
    
    // Errors
    public var currentError: OnboardingError?
    public var showError: Bool = false
    
    private let keyManager: KeyManager
    private let modelsViewModel: ModelsViewModel
    private var webAuthSession: ASWebAuthenticationSession?
    
    // MARK: - Errors
    
    public enum OnboardingError: LocalizedError {
        case authenticationFailed(provider: CloudProvider, reason: String)
        case tokenStorageFailed
        case privacyPolicyRequired
        case networkError
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .authenticationFailed(let provider, let reason):
                return "Couldn't connect to \(provider.rawValue): \(reason)"
            case .tokenStorageFailed:
                return "Failed to securely save your credentials"
            case .privacyPolicyRequired:
                return "Please accept the privacy policy to continue"
            case .networkError:
                return "Network connection issue. Please try again."
            case .cancelled:
                return "Authentication was cancelled"
            }
        }
        
        public var recoverySuggestion: String? {
            switch self {
            case .authenticationFailed:
                return "Please check your internet connection and try again."
            case .tokenStorageFailed:
                return "There may be an issue with Keychain access. Try restarting the app."
            case .privacyPolicyRequired:
                return "You must accept the privacy policy to use Quantum Badger."
            case .networkError:
                return "Check your Wi-Fi connection and try again."
            case .cancelled:
                return "You can skip this step and connect later in Settings."
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        keyManager: KeyManager = KeyManager(),
        modelsViewModel: ModelsViewModel = ModelsViewModel()
    ) {
        self.keyManager = keyManager
        self.modelsViewModel = modelsViewModel
        super.init()
        
        // Check if onboarding is already complete
        checkOnboardingStatus()
    }
    
    // MARK: - Navigation
    
    public func nextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        
        // Validate current step before proceeding
        if !validateCurrentStep() {
            return
        }
        
        currentStep = next
        updateCanProceed()
    }
    
    public func previousStep() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
        updateCanProceed()
    }
    
    public func skipToStep(_ step: OnboardingStep) {
        currentStep = step
        updateCanProceed()
    }
    
    private func validateCurrentStep() -> Bool {
        switch currentStep {
        case .privacyPolicy:
            if !hasAcceptedPrivacyPolicy {
                showError(.privacyPolicyRequired)
                return false
            }
            return true
        default:
            return true
        }
    }
    
    private func updateCanProceed() {
        switch currentStep {
        case .welcome:
            canProceedToNextStep = true
        case .privacyPolicy:
            canProceedToNextStep = hasAcceptedPrivacyPolicy
        case .localModels:
            canProceedToNextStep = true // Optional
        case .cloudSSO:
            canProceedToNextStep = true // Optional
        case .completion:
            canProceedToNextStep = true
        }
    }
    
    // MARK: - Privacy Step
    
    public func acceptPrivacyPolicy() {
        hasAcceptedPrivacyPolicy = true
        updateCanProceed()
        
        // Save preference
        UserDefaults.standard.set(true, forKey: "privacyPolicyAccepted")
    }
    
    // MARK: - Local Models Step
    
    public func toggleModelSelection(_ modelClass: ModelClass) {
        if selectedModelsToDownload.contains(modelClass) {
            selectedModelsToDownload.remove(modelClass)
        } else {
            selectedModelsToDownload.insert(modelClass)
        }
    }
    
    public func selectRecommendedModel() {
        selectedModelsToDownload.insert(recommendedModel)
    }
    
    // MARK: - Cloud SSO Step
    
    public func authenticateWithProvider(_ provider: CloudProvider) {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        currentAuthenticatingProvider = provider
        
        switch provider {
        case .openAI:
            authenticateWithOpenAI()
        case .anthropic:
            authenticateWithAnthropic()
        case .google:
            authenticateWithGoogle()
        case .applePCC:
            // Apple PCC uses device authentication
            connectedProviders.insert(provider)
            isAuthenticating = false
        }
    }
    
    private func authenticateWithOpenAI() {
        guard let clientId = configuredOAuthClientID(for: .openAI) else {
            showError(.authenticationFailed(provider: .openAI, reason: "OpenAI SSO is not configured. Add OPENAI_OAUTH_CLIENT_ID to app configuration."))
            return
        }
        let redirectUri = "com.quantumbadger://oauth/callback"
        let scope = "api"
        
        guard let authURL = URL(string: "https://platform.openai.com/auth?client_id=\(clientId)&redirect_uri=\(redirectUri)&scope=\(scope)&response_type=code") else {
            showError(.authenticationFailed(provider: .openAI, reason: "Invalid URL"))
            return
        }
        
        startWebAuthSession(url: authURL, callbackURLScheme: "com.quantumbadger", provider: .openAI)
    }
    
    private func authenticateWithAnthropic() {
        guard let clientId = configuredOAuthClientID(for: .anthropic) else {
            showError(.authenticationFailed(provider: .anthropic, reason: "Anthropic SSO is not configured. Add ANTHROPIC_OAUTH_CLIENT_ID to app configuration."))
            return
        }
        let redirectUri = "com.quantumbadger://oauth/callback"
        
        guard let authURL = URL(string: "https://console.anthropic.com/oauth/authorize?client_id=\(clientId)&redirect_uri=\(redirectUri)&response_type=code") else {
            showError(.authenticationFailed(provider: .anthropic, reason: "Invalid URL"))
            return
        }
        
        startWebAuthSession(url: authURL, callbackURLScheme: "com.quantumbadger", provider: .anthropic)
    }
    
    private func authenticateWithGoogle() {
        guard let clientId = configuredOAuthClientID(for: .google) else {
            showError(.authenticationFailed(provider: .google, reason: "Google SSO is not configured. Add GOOGLE_OAUTH_CLIENT_ID to app configuration."))
            return
        }
        let redirectUri = "com.quantumbadger://oauth/callback"
        let scope = "https://www.googleapis.com/auth/generative-language.retriever"
        
        guard let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientId)&redirect_uri=\(redirectUri)&scope=\(scope)&response_type=code") else {
            showError(.authenticationFailed(provider: .google, reason: "Invalid URL"))
            return
        }
        
        startWebAuthSession(url: authURL, callbackURLScheme: "com.quantumbadger", provider: .google)
    }
    
    private func startWebAuthSession(url: URL, callbackURLScheme: String, provider: CloudProvider) {
        let completionHandler = makeWebAuthCompletionHandler(provider: provider)
        webAuthSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackURLScheme,
            completionHandler: completionHandler
        )
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = true
        
        webAuthSession?.start()
    }
    
    nonisolated private func makeWebAuthCompletionHandler(
        provider: CloudProvider
    ) -> @Sendable (URL?, (any Error)?) -> Void {
        { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.handleWebAuthenticationResult(
                    callbackURL: callbackURL,
                    error: error,
                    provider: provider
                )
            }
        }
    }
    
    private func configuredOAuthClientID(for provider: CloudProvider) -> String? {
        let key: String
        switch provider {
        case .openAI:
            key = "OPENAI_OAUTH_CLIENT_ID"
        case .anthropic:
            key = "ANTHROPIC_OAUTH_CLIENT_ID"
        case .google:
            key = "GOOGLE_OAUTH_CLIENT_ID"
        case .applePCC:
            return nil
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "quantum-badger-client" else {
            return nil
        }
        return trimmed
    }
    
    private func handleWebAuthenticationResult(
        callbackURL: URL?,
        error: Error?,
        provider: CloudProvider
    ) {
        isAuthenticating = false
        currentAuthenticatingProvider = nil
        
        if let error {
            let nsError = error as NSError
            if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                showError(.cancelled)
            } else {
                showError(.authenticationFailed(provider: provider, reason: error.localizedDescription))
            }
            return
        }
        
        guard let callbackURL else {
            showError(.authenticationFailed(provider: provider, reason: "No callback URL"))
            return
        }
        
        Task { @MainActor in
            await handleAuthenticationCallback(url: callbackURL, provider: provider)
        }
    }
    
    private func handleAuthenticationCallback(url: URL, provider: CloudProvider) async {
        // Extract authorization code from URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            showError(.authenticationFailed(provider: provider, reason: "Invalid response"))
            return
        }
        
        // Exchange code for token (simplified - in production, do this server-side)
        let token = "oauth_\(code)_\(provider.rawValue.lowercased())"
        
        // Store token in Keychain
        do {
            try await keyManager.storeToken(token, for: provider)
            connectedProviders.insert(provider)
        } catch {
            showError(.tokenStorageFailed)
        }
    }
    
    public func disconnectProvider(_ provider: CloudProvider) {
        Task {
            try? await keyManager.deleteToken(for: provider)
            connectedProviders.remove(provider)
        }
    }
    
    // MARK: - Completion
    
    public func completeOnboarding() {
        // Save settings
        UserDefaults.standard.set(true, forKey: AppDefaultsKeys.onboardingCompleted)
        // Legacy compatibility for older app gating key.
        UserDefaults.standard.set(true, forKey: AppDefaultsKeys.legacyHasCompletedOnboarding)
        UserDefaults.standard.set(enableSafeModeByDefault, forKey: "safeModeDefault")
        
        // Start model downloads if selected
        for modelClass in selectedModelsToDownload {
            if let modelInfo = modelsViewModel.availableModels.first(where: { $0.modelClass == modelClass }) {
                Task {
                    await modelsViewModel.downloadModel(modelInfo)
                }
            }
        }
        
        onboardingCompleted = true
    }
    
    private func checkOnboardingStatus() {
        let defaults = UserDefaults.standard
        let completed = defaults.bool(forKey: AppDefaultsKeys.onboardingCompleted)
            || defaults.bool(forKey: AppDefaultsKeys.legacyHasCompletedOnboarding)
        if completed {
            defaults.set(true, forKey: AppDefaultsKeys.onboardingCompleted)
            defaults.set(true, forKey: AppDefaultsKeys.legacyHasCompletedOnboarding)
        }
        onboardingCompleted = completed
        
        if completed {
            hasAcceptedPrivacyPolicy = defaults.bool(forKey: "privacyPolicyAccepted")
        }
    }
    
    // MARK: - Error Handling
    
    private func showError(_ error: OnboardingError) {
        currentError = error
        showError = true
    }
    
    public func dismissError() {
        showError = false
        currentError = nil
    }
    
    // MARK: - Helper Methods
    
    public func canSkipStep(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .privacyPolicy, .completion:
            return false
        case .localModels, .cloudSSO:
            return true
        }
    }
    
    public var progressPercentage: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

@MainActor
private enum WindowFinder {
    static var currentAnchor: ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSWindow()
    }
}

extension OnboardingViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                WindowFinder.currentAnchor
            }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    WindowFinder.currentAnchor
                }
            }
        }
    }
}
