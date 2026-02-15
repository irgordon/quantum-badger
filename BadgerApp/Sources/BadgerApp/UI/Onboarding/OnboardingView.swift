import SwiftUI
import AuthenticationServices
import BadgerCore
import BadgerRuntime

// MARK: - Onboarding View

public struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    private let initialStep: OnboardingViewModel.OnboardingStep
    @Environment(\.dismiss) private var dismiss
    
    public init(initialStep: OnboardingViewModel.OnboardingStep = .welcome) {
        self.initialStep = initialStep
        _viewModel = StateObject(wrappedValue: OnboardingViewModel())
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Progress Bar
            ProgressView(value: viewModel.progressPercentage)
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .padding(.top)
            
            // Content
            TabView(selection: $viewModel.currentStep) {
                WelcomeStep(viewModel: viewModel)
                    .tag(OnboardingViewModel.OnboardingStep.welcome)
                
                PrivacyStep(viewModel: viewModel)
                    .tag(OnboardingViewModel.OnboardingStep.privacyPolicy)
                
                LocalModelsStep(viewModel: viewModel)
                    .tag(OnboardingViewModel.OnboardingStep.localModels)
                
                CloudSSOStep(viewModel: viewModel)
                    .tag(OnboardingViewModel.OnboardingStep.cloudSSO)
                
                CompletionStep(viewModel: viewModel, dismiss: dismiss)
                    .tag(OnboardingViewModel.OnboardingStep.completion)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut, value: viewModel.currentStep)
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.currentError
        ) { error in
            Button("OK") {
                viewModel.dismissError()
            }
            Button("Skip This Step", role: .cancel) {
                viewModel.nextStep()
            }
        } message: { error in
            Text(error.localizedDescription)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if viewModel.currentStep != initialStep {
                viewModel.skipToStep(initialStep)
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(radius: 20)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 12) {
                Text("Welcome to Quantum Badger")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                
                Text("Your sovereign AI assistant")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "lock.shield", color: .green, text: "Privacy-first: Your data stays on your device")
                FeatureRow(icon: "cpu", color: .blue, text: "Local AI: Run models directly on your Mac")
                FeatureRow(icon: "arrow.triangle.branch", color: .purple, text: "Smart Routing: Automatic local/cloud selection")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Navigation
            HStack {
                Spacer()
                
                Button("Get Started") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Spacer()
            }
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Privacy Step

struct PrivacyStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Privacy & Security")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Your data never leaves your device unless you explicitly choose cloud inference.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Privacy Features
            VStack(alignment: .leading, spacing: 16) {
                PrivacyFeatureRow(
                    icon: "text.badge.checkmark",
                    title: "Input Sanitization",
                    description: "Automatic PII and malicious code detection"
                )
                
                PrivacyFeatureRow(
                    icon: "key.fill",
                    title: "Secure Keychain",
                    description: "Cloud tokens stored in Secure Enclave"
                )
                
                PrivacyFeatureRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Audit Logging",
                    description: "Tamper-evident logs of all activity"
                )
                
                PrivacyFeatureRow(
                    icon: "network.badge.shield.half.filled",
                    title: "Zero Data Retention",
                    description: "No conversation data stored on servers"
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Safe Mode Toggle
            Toggle(isOn: $viewModel.enableSafeModeByDefault) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Safe Mode by Default")
                        .font(.subheadline)
                    Text("Always use cloud inference for maximum security")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Accept Privacy Policy
            HStack {
                Image(systemName: viewModel.hasAcceptedPrivacyPolicy ? "checkmark.square.fill" : "square")
                    .foregroundStyle(viewModel.hasAcceptedPrivacyPolicy ? .green : .secondary)
                    .font(.title3)
                    .onTapGesture {
                        viewModel.acceptPrivacyPolicy()
                    }
                
                Text("I accept the Privacy Policy and Terms of Service")
                    .font(.subheadline)
                
                Spacer()
            }
            .padding()
            .background(viewModel.hasAcceptedPrivacyPolicy ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                viewModel.acceptPrivacyPolicy()
            }
            
            Spacer()
            
            // Navigation
            HStack {
                Button("Back") {
                    viewModel.previousStep()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Continue") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceedToNextStep)
            }
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Local Models Step

struct LocalModelsStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "cpu.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Local AI Models")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Download models to run AI entirely on your Mac. No internet required after download.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Recommended Model
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recommended")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(viewModel.recommendedModel.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "cpu")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Qwen 2.5")
                            .font(.headline)
                        Text("7B parameters • 4.5 GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Great balance of speed and capability")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(viewModel.selectedModelsToDownload.contains(viewModel.recommendedModel) ? "Selected" : "Select") {
                        viewModel.selectRecommendedModel()
                    }
                    .buttonStyle(.automatic)
                    .disabled(viewModel.selectedModelsToDownload.contains(viewModel.recommendedModel))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Skip Option
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                
                Text("You can download models later in Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            // Navigation
            HStack {
                Button("Back") {
                    viewModel.previousStep()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Skip") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderless)
                
                Button("Continue") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Cloud SSO Step

struct CloudSSOStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "cloud.fill")
                .font(.system(size: 80))
                .foregroundStyle(.purple)
            
            VStack(spacing: 8) {
                Text("Cloud Services (Optional)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Connect providers for advanced capabilities when local models aren't sufficient.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Provider List
            VStack(spacing: 12) {
                ProviderRow(
                    name: "Anthropic",
                    description: "Claude 3.5 Sonnet & Haiku",
                    icon: "a.circle.fill",
                    color: .orange,
                    isConnected: viewModel.connectedProviders.contains(CloudProvider.anthropic),
                    isAuthenticating: viewModel.currentAuthenticatingProvider == CloudProvider.anthropic,
                    onConnect: { viewModel.authenticateWithProvider(.anthropic) }
                )
                
                ProviderRow(
                    name: "OpenAI",
                    description: "GPT-4o & GPT-4o-mini",
                    icon: "o.circle.fill",
                    color: .green,
                    isConnected: viewModel.connectedProviders.contains(CloudProvider.openAI),
                    isAuthenticating: viewModel.currentAuthenticatingProvider == CloudProvider.openAI,
                    onConnect: { viewModel.authenticateWithProvider(.openAI) }
                )
                
                ProviderRow(
                    name: "Google",
                    description: "Gemini 1.5 Pro & Flash",
                    icon: "g.circle.fill",
                    color: .blue,
                    isConnected: viewModel.connectedProviders.contains(.google),
                    isAuthenticating: viewModel.currentAuthenticatingProvider == .google,
                    onConnect: { viewModel.authenticateWithProvider(.google) }
                )
            }
            
            // Security Note
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.green)
                
                Text("Tokens are securely stored in the Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            // Navigation
            HStack {
                Button("Back") {
                    viewModel.previousStep()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Skip") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderless)
                
                Button("Continue") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Completion Step

struct CompletionStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success Animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 140, height: 140)
                
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                
                Text("Quantum Badger is ready to help you privately.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Summary
            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(
                    icon: viewModel.hasAcceptedPrivacyPolicy ? "checkmark.circle.fill" : "circle",
                    text: "Privacy Policy Accepted",
                    isComplete: viewModel.hasAcceptedPrivacyPolicy
                )
                
                SummaryRow(
                    icon: viewModel.selectedModelsToDownload.isEmpty ? "circle" : "checkmark.circle.fill",
                    text: "\(viewModel.selectedModelsToDownload.count) model(s) selected for download",
                    isComplete: !viewModel.selectedModelsToDownload.isEmpty
                )
                
                SummaryRow(
                    icon: viewModel.connectedProviders.isEmpty ? "circle" : "checkmark.circle.fill",
                    text: "\(viewModel.connectedProviders.count) cloud provider(s) connected",
                    isComplete: !viewModel.connectedProviders.isEmpty
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Spacer()
            
            // Finish Button
            Button("Start Using Quantum Badger") {
                viewModel.completeOnboarding()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ProviderRow: View {
    let name: String
    let description: String
    let icon: String
    let color: Color
    let isConnected: Bool
    let isAuthenticating: Bool
    let onConnect: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Connected")
                }
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            } else if isAuthenticating {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SummaryRow: View {
    let icon: String
    let text: String
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isComplete ? .green : .secondary)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isComplete ? .primary : .secondary)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
