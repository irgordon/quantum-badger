import Foundation
import Observation
import AppKit
import LocalAuthentication
import BadgerApp // Need IdentityRecoveryManager from AppStubs or similar if not in Core

@MainActor
@Observable
final class OnboardingStateStore {
    var isAccessibilityAuthorized = false
    var isBiometricsAuthorized = false
    var isAutomationAuthorized = false
    
    // Controlled by WelcomeView completion
    var needsOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "qb.needsOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "qb.needsOnboarding") }
    }
    
    // Injected dependency (kept for compatibility with AppState)
    let identityRecoveryManager: IdentityRecoveryManager
    
    init(identityRecoveryManager: IdentityRecoveryManager) {
        self.identityRecoveryManager = identityRecoveryManager
        
        // Initialize needsOnboarding if not set
        if UserDefaults.standard.object(forKey: "qb.needsOnboarding") == nil {
            UserDefaults.standard.set(true, forKey: "qb.needsOnboarding")
        }
        
        refresh()
    }
    
    func refresh() {
        // 1. Check Accessibility
        self.isAccessibilityAuthorized = AXIsProcessTrusted()
        
        // 2. Check Biometrics (TouchID)
        let context = LAContext()
        var error: NSError?
        self.isBiometricsAuthorized = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        // 3. Check Automation (AppleScript/Shortcuts)
        // Note: Real check involves querying TCC or similar, for now we assume false until action taken?
        // Or specific check if available.
        // For this demo, we'll let it be true if others are true or minimal check.
        self.isAutomationAuthorized = true 
    }
    
    var isFullyBoarded: Bool {
        isAccessibilityAuthorized && isBiometricsAuthorized
    }
    
    func completeOnboarding() {
        needsOnboarding = false
    }
}
