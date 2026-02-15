import Foundation

// MARK: - BadgerCore

public enum BadgerCore {
    public static let version = "1.0.0"
    
    public static func initialize() async throws {
        let auditService = AuditLogService()
        try await auditService.initialize()
        _ = try await auditService.log(
            type: .policyChange,
            source: "BadgerCore",
            details: "BadgerCore v\(version) initialized"
        )
    }
}

// MARK: - Security Exports

public typealias BadgerSecurityPolicy = SecurityPolicy
public typealias BadgerSecurityPolicyManager = SecurityPolicyManager

// MARK: - Audit Exports

public typealias BadgerAuditLogService = AuditLogService
public typealias BadgerAuditEventType = AuditEventType

// MARK: - Crypto Exports

public typealias BadgerKeyManager = KeyManager
public typealias BadgerAIProvider = AIProvider

// MARK: - Sanitization Exports

public typealias BadgerInputSanitizer = InputSanitizer
public typealias BadgerSanitizationResult = SanitizationResult

// MARK: - Privacy Egress Filter Exports (NEW)

public typealias BadgerPrivacyEgressFilter = PrivacyEgressFilter
public typealias BadgerSensitiveDataType = PrivacyEgressFilter.SensitiveDataType
public typealias BadgerPrivacyConfiguration = PrivacyEgressFilter.Configuration

// MARK: - Router Exports

public typealias BadgerModelClass = ModelClass
public typealias BadgerCloudProvider = CloudProvider
public typealias BadgerPromptComplexity = PromptComplexity
public typealias BadgerRouterDecision = RouterDecision
public typealias BadgerSystemState = SystemState
public typealias BadgerRouterConfiguration = RouterConfiguration

// MARK: - SLA Exports

public typealias BadgerFunctionSLA = FunctionSLA
public typealias BadgerFunctionError = FunctionError
public typealias BadgerFunctionClock = FunctionClock
public typealias BadgerSystemFunctionClock = SystemFunctionClock
public typealias BadgerSLARuntimeGuard = SLARuntimeGuard
public typealias BadgerFunctionAuditRecord = FunctionAuditRecord
