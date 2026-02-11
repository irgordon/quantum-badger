import SwiftUI
import AppKit
import LocalAuthentication

struct WelcomeView: View {
    @Bindable var store: OnboardingStateStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                if let icon = NSImage(named: "AppIcon") {
                     Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.secondary)
                }
                
                Text("Welcome to Quantum Badger")
                    .font(.system(size: 28, weight: .bold))
                
                Text("To function as a Sovereign Agent, I need a few keys to your Mac's workshop. Your data never leaves this machine.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            }
            .padding(.vertical, 40)
            
            // Permission List
            ScrollView {
                VStack(spacing: 16) {
                    PermissionPrimerRow(
                        title: "Biometric Security",
                        icon: "lock.shield.fill",
                        description: "Used to unlock your Vault and authorize sensitive actions like sending messages or modifying files.",
                        isAuthorized: store.isBiometricsAuthorized
                    ) {
                        requestBiometrics()
                    }
                    
                    PermissionPrimerRow(
                        title: "Accessibility",
                        icon: "hand.raised.fill",
                        description: "Allows the agent to perceive the active window and provide context-aware assistance.",
                        isAuthorized: store.isAccessibilityAuthorized
                    ) {
                        openSystemAccessibility()
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Check Status") {
                    store.refresh()
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Start Using Badger") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.isFullyBoarded)
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 650)
    }
    
    // MARK: - Actions
    
    private func requestBiometrics() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Quantum Badger needs Touch ID to secure your local Vault.") { success, _ in
            Task { @MainActor in store.refresh() }
        }
    }
    
    private func openSystemAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        
        // In 2026, we might want to poll for a few seconds to see if the user enabled it
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            Task { @MainActor in
                store.refresh()
                if store.isAccessibilityAuthorized { timer.invalidate() }
            }
        }
    }
    
    private func completeOnboarding() {
        // Log the onboarding completion to the Audit Log
        // auditLog.record(event: .systemMaintenance("User completed security onboarding."))
        
        store.completeOnboarding()
    }
}

struct PermissionPrimerRow: View {
    let title: String
    let icon: String
    let description: String
    let isAuthorized: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isAuthorized ? .green : .blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !isAuthorized {
                    Button(action: action) {
                        Text("Enable Access")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                } else {
                    Label("Authorized", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption.bold())
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}
