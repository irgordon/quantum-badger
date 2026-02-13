import Foundation

// MARK: - Risk Level

/// Represents the risk assessment level for operations
public enum RiskLevel: String, Sendable, Codable, CaseIterable {
    case standard = "Standard"
    case advanced = "Advanced"
}

// MARK: - Execution Policy

/// Defines the execution behavior of the AI assistant
public enum ExecutionPolicy: String, Sendable, Codable, CaseIterable {
    /// All inference offloaded to Private Cloud Compute (PCC)
    case safeMode = "SafeMode"
    /// Intelligent routing between local and cloud based on complexity
    case balanced = "Balanced"
    /// Prioritizes local inference for maximum privacy
    case performance = "Performance"
}

// MARK: - Security Policy

/// Central security configuration for the Quantum Badger system.
/// This struct is Sendable and immutable to ensure thread-safety across concurrent contexts.
public struct SecurityPolicy: Sendable, Codable, Equatable {
    
    /// The current risk assessment level
    public let riskLevel: RiskLevel
    
    /// The execution policy governing local vs cloud inference
    public let executionPolicy: ExecutionPolicy
    
    /// Emergency kill-switch that disables all remote operations when true
    public let isLockdown: Bool
    
    /// Timestamp when the policy was created/updated
    public let timestamp: Date
    
    /// The risk level before lockdown was enabled (for restoration)
    private let preLockdownRiskLevel: RiskLevel?
    
    /// The execution policy before lockdown was enabled (for restoration)
    private let preLockdownExecutionPolicy: ExecutionPolicy?
    
    /// Creates a new SecurityPolicy instance
    /// - Parameters:
    ///   - riskLevel: The risk assessment level (default: .standard)
    ///   - executionPolicy: The execution policy (default: .balanced)
    ///   - isLockdown: Emergency kill-switch state (default: false)
    ///   - preLockdownRiskLevel: The risk level before lockdown (for internal use)
    ///   - preLockdownExecutionPolicy: The execution policy before lockdown (for internal use)
    public init(
        riskLevel: RiskLevel = .standard,
        executionPolicy: ExecutionPolicy = .balanced,
        isLockdown: Bool = false,
        preLockdownRiskLevel: RiskLevel? = nil,
        preLockdownExecutionPolicy: ExecutionPolicy? = nil
    ) {
        self.riskLevel = riskLevel
        self.executionPolicy = executionPolicy
        self.isLockdown = isLockdown
        self.preLockdownRiskLevel = preLockdownRiskLevel
        self.preLockdownExecutionPolicy = preLockdownExecutionPolicy
        self.timestamp = Date()
    }
    
    /// Returns a new policy with lockdown enabled
    public func enableLockdown() -> SecurityPolicy {
        SecurityPolicy(
            riskLevel: .advanced,
            executionPolicy: .safeMode,
            isLockdown: true,
            preLockdownRiskLevel: self.riskLevel,
            preLockdownExecutionPolicy: self.executionPolicy
        )
    }
    
    /// Returns a new policy with lockdown disabled
    public func disableLockdown() -> SecurityPolicy {
        // Restore pre-lockdown state if available, otherwise use defaults
        SecurityPolicy(
            riskLevel: preLockdownRiskLevel ?? .standard,
            executionPolicy: preLockdownExecutionPolicy ?? .balanced,
            isLockdown: false
        )
    }
    
    /// Determines if remote operations are permitted based on current policy
    public var allowsRemoteOperations: Bool {
        !isLockdown && executionPolicy != .safeMode
    }
    
    /// Determines if local inference is preferred
    public var prefersLocalInference: Bool {
        executionPolicy == .performance || (executionPolicy == .balanced && !isLockdown)
    }
}

// MARK: - Global Policy Manager

/// Actor responsible for managing the current security policy in a thread-safe manner
public actor SecurityPolicyManager {
    
    private var currentPolicy: SecurityPolicy
    
    /// Initialize with a default or custom policy
    public init(policy: SecurityPolicy = SecurityPolicy()) {
        self.currentPolicy = policy
    }
    
    /// Get the current security policy
    public func getPolicy() -> SecurityPolicy {
        currentPolicy
    }
    
    /// Update the security policy
    public func updatePolicy(_ policy: SecurityPolicy) {
        currentPolicy = policy
    }
    
    /// Enable lockdown mode immediately
    public func enableLockdown() {
        currentPolicy = currentPolicy.enableLockdown()
    }
    
    /// Disable lockdown mode
    public func disableLockdown() {
        currentPolicy = currentPolicy.disableLockdown()
    }
    
    /// Check if remote operations are currently allowed
    public func canPerformRemoteOperations() -> Bool {
        currentPolicy.allowsRemoteOperations
    }
}
