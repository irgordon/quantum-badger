import Foundation
import BadgerCore
import BadgerRuntime

// MARK: - App Coordinator Errors

public enum AppCoordinatorError: Error, Sendable {
    case executionFailed(String)
    case sanitizationFailed(String)
    case invalidInput
    case engineNotAvailable
    case securityViolation(String)
    case formattingFailed
}

// MARK: - Execution Context

/// Context for command execution
public struct ExecutionContext: Sendable {
    public let source: CommandSource
    public let originalInput: String
    public let timestamp: Date
    public let userID: String?
    public let conversationID: String?
    
    public enum CommandSource: String, Sendable, CaseIterable {
        case shortcuts = "Shortcuts"
        case siri = "Siri"
        case imessage = "iMessage"
        case whatsapp = "WhatsApp"
        case telegram = "Telegram"
        case slack = "Slack"
        case internalApp = "Internal"
        case widget = "Widget"
    }
    
    public init(
        source: CommandSource,
        originalInput: String,
        userID: String? = nil,
        conversationID: String? = nil
    ) {
        self.source = source
        self.originalInput = originalInput
        self.timestamp = Date()
        self.userID = userID
        self.conversationID = conversationID
    }
}

// MARK: - Execution Result

/// Result of command execution
public struct CommandExecutionResult: Sendable {
    public let output: String
    public let formattedOutput: FormattedOutput?
    public let executionTime: TimeInterval
    public let routingDecision: RouterDecision
    public let wasSanitized: Bool
    public let metadata: [String: String]
    
    public init(
        output: String,
        formattedOutput: FormattedOutput? = nil,
        executionTime: TimeInterval,
        routingDecision: RouterDecision,
        wasSanitized: Bool,
        metadata: [String: String] = [:]
    ) {
        self.output = output
        self.formattedOutput = formattedOutput
        self.executionTime = executionTime
        self.routingDecision = routingDecision
        self.wasSanitized = wasSanitized
        self.metadata = metadata
    }
}

// MARK: - Formatted Output

/// Represents formatted output that may be returned as a file
public struct FormattedOutput: Sendable {
    public let content: String
    public let format: OutputFormat
    public let filename: String
    public let fileURL: URL?
    
    public enum OutputFormat: String, Sendable {
        case plainText = "txt"
        case markdown = "md"
        case json = "json"
        case code = "swift"
    }
    
    public init(
        content: String,
        format: OutputFormat,
        filename: String,
        fileURL: URL? = nil
    ) {
        self.content = content
        self.format = format
        self.filename = filename
        self.fileURL = fileURL
    }
}

// MARK: - App Coordinator

/// Central coordinator for executing commands from various sources
@MainActor
public final class AppCoordinator: ObservableObject, Sendable {
    
    // MARK: - Properties
    
    private let executionManager: HybridExecutionManager
    private let responseFormatter: ResponseFormatter
    private let searchIndexer: SearchIndexer
    private let auditService: AuditLogService
    private let inputSanitizer: InputSanitizer
    
    public static let shared = AppCoordinator()
    
    // MARK: - Initialization
    
    public init(
        executionManager: HybridExecutionManager? = nil,
        responseFormatter: ResponseFormatter? = nil,
        searchIndexer: SearchIndexer? = nil,
        auditService: AuditLogService? = nil
    ) {
        self.executionManager = executionManager ?? HybridExecutionManager()
        self.responseFormatter = responseFormatter ?? ResponseFormatter()
        self.searchIndexer = searchIndexer ?? SearchIndexer()
        self.auditService = auditService ?? AuditLogService()
        self.inputSanitizer = InputSanitizer()
    }
    
    // MARK: - Main Execution Entry Point
    
    /// Execute a command from any source
    /// - Parameters:
    ///   - command: The command string to execute
    ///   - context: Execution context (source, user, etc.)
    /// - Returns: Execution result with formatted output
    public func execute(
        command: String,
        context: ExecutionContext
    ) async throws -> CommandExecutionResult {
        let startTime = Date()
        
        // Step 1: Log the received command
        try await auditService.log(
            type: .remoteCommandReceived,
            source: context.source.rawValue,
            details: "Command from \(context.source.rawValue): \(command.prefix(100))..."
        )
        
        // Step 2: Sanitize input (critical security step)
        let sanitizationResult = inputSanitizer.sanitize(command)
        let sanitizedCommand = sanitizationResult.sanitized
        
        // Check for security violations
        let criticalViolations = sanitizationResult.violations.filter {
            $0.severity == .critical || $0.severity == .high
        }
        
        if !criticalViolations.isEmpty {
            let violationNames = criticalViolations.map { $0.patternName }.joined(separator: ", ")
            try await auditService.log(
                type: .sanitizationTriggered,
                source: context.source.rawValue,
                details: "Security violations blocked: \(violationNames)"
            )
            throw AppCoordinatorError.securityViolation(
                "Potentially harmful content detected: \(violationNames)"
            )
        }
        
        // Step 3: Execute through the hybrid engine
        let executionResult: HybridExecutionResult
        do {
            executionResult = try await executionManager.executeWithFallback(
                prompt: sanitizedCommand,
                configuration: defaultConfiguration(for: context)
            )
        } catch {
            throw AppCoordinatorError.executionFailed(error.localizedDescription)
        }
        
        // Step 4: Format the response
        let formattedOutput = try await responseFormatter.format(
            content: executionResult.text,
            source: context.source
        )
        
        // Step 5: Build the result
        let result = CommandExecutionResult(
            output: executionResult.text,
            formattedOutput: formattedOutput,
            executionTime: Date().timeIntervalSince(startTime),
            routingDecision: executionResult.decision,
            wasSanitized: sanitizationResult.wasSanitized,
            metadata: [
                "source": context.source.rawValue,
                "sanitized": String(sanitizationResult.wasSanitized),
                "violations": String(sanitizationResult.violations.count),
                "routing": executionResult.decision.isLocal ? "local" : "cloud"
            ]
        )
        
        // Step 6: Index for search if appropriate
        if shouldIndex(context: context, result: result) {
            await searchIndexer.indexInteraction(
                query: sanitizedCommand,
                response: executionResult.text,
                context: context
            )
        }
        
        // Step 7: Log completion
        try await auditService.log(
            type: .shadowRouterDecision,
            source: context.source.rawValue,
            details: "Execution completed in \(String(format: "%.2f", result.executionTime))s"
        )
        
        return result
    }
    
    /// Execute from Shortcuts/AppIntent (simplified interface)
    public func execute(
        command: String,
        source: ExecutionContext.CommandSource = .shortcuts
    ) async throws -> CommandExecutionResult {
        let context = ExecutionContext(
            source: source,
            originalInput: command
        )
        return try await execute(command: command, context: context)
    }
    
    // MARK: - Configuration
    
    private func defaultConfiguration(for context: ExecutionContext) -> ExecutionConfiguration {
        switch context.source {
        case .shortcuts, .siri:
            // Fast response for voice/shortcuts
            return ExecutionConfiguration.fast
            
        case .imessage, .whatsapp, .telegram, .slack:
            // Balanced for messaging
            return ExecutionConfiguration(
                useIntentAnalysis: true,
                preferredCloudTier: .normal,
                allowFallback: true
            )
            
        case .internalApp:
            // Full features for in-app use
            return ExecutionConfiguration.default
            
        case .widget:
            // Fast, no fallback for widgets
            return ExecutionConfiguration(
                useIntentAnalysis: false,
                allowFallback: false
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldIndex(
        context: ExecutionContext,
        result: CommandExecutionResult
    ) -> Bool {
        // Don't index if there were security violations
        if result.wasSanitized && result.metadata["violations"] != "0" {
            return false
        }
        
        // Don't index from certain sources
        switch context.source {
        case .shortcuts, .siri, .internalApp:
            return true
        case .imessage, .whatsapp, .telegram, .slack:
            // Only index if explicitly enabled for messaging
            return false // Privacy by default
        case .widget:
            return false
        }
    }
}

// MARK: - Convenience Extensions

extension AppCoordinator {
    /// Quick execute for simple use cases
    public func quickExecute(command: String) async throws -> String {
        let result = try await execute(
            command: command,
            source: .internalApp
        )
        return result.output
    }
    
    /// Execute and return as file if needed
    public func executeAsFile(
        command: String,
        source: ExecutionContext.CommandSource
    ) async throws -> URL? {
        let result = try await execute(command: command, source: source)
        return result.formattedOutput?.fileURL
    }
}
