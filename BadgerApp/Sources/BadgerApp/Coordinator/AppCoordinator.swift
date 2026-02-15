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
        timestamp: Date = Date(),
        userID: String? = nil,
        conversationID: String? = nil
    ) {
        self.source = source
        self.originalInput = originalInput
        self.timestamp = timestamp
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

private struct SanitizedCommand: Sendable {
    let command: String
    let wasSanitized: Bool
    let violationCount: Int
}

// MARK: - App Coordinator

/// Central coordinator for executing commands from various sources
public final class AppCoordinator: ObservableObject, Sendable {
    
    // MARK: - Properties
    
    private let executionManager: HybridExecutionManager
    private let responseFormatter: ResponseFormatter
    private let searchIndexer: SearchIndexer
    private let auditService: AuditLogService
    private let inputSanitizer: InputSanitizer
    private let clock: FunctionClock
    
    public static let shared = AppCoordinator()
    
    // MARK: - Initialization
    
    public init(
        executionManager: HybridExecutionManager? = nil,
        responseFormatter: ResponseFormatter? = nil,
        searchIndexer: SearchIndexer? = nil,
        auditService: AuditLogService? = nil,
        clock: FunctionClock = SystemFunctionClock()
    ) {
        self.executionManager = executionManager ?? HybridExecutionManager()
        self.responseFormatter = responseFormatter ?? ResponseFormatter()
        self.searchIndexer = searchIndexer ?? SearchIndexer()
        self.auditService = auditService ?? AuditLogService()
        self.inputSanitizer = InputSanitizer()
        self.clock = clock
    }
    
    // MARK: - Main Execution Entry Point
    
    /// Execute a command from any source using strict SLA enforcement.
    public func executeWithSLA(
        command: String,
        context: ExecutionContext,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 10_000,
            maxMemoryMb: 512,
            deterministic: true,
            timeoutSeconds: 10,
            version: "v1"
        )
    ) async -> Result<CommandExecutionResult, FunctionError> {
        switch validateCommand(command) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }
        
        return await SLARuntimeGuard.run(
            functionName: "AppCoordinator.executeWithSLA",
            inputMaterial: "\(context.source.rawValue)|\(command)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.executePipeline(command: command, context: context)
            },
            outputMaterial: { result in
                self.hashableOutputMaterial(for: result)
            }
        )
    }
    
    /// Execute a command from any source.
    public func execute(
        command: String,
        context: ExecutionContext
    ) async throws -> CommandExecutionResult {
        let result = await executeWithSLA(command: command, context: context)
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    /// Execute from Shortcuts/AppIntent (simplified interface)
    public func execute(
        command: String,
        source: ExecutionContext.CommandSource = .shortcuts
    ) async throws -> CommandExecutionResult {
        let context = ExecutionContext(
            source: source,
            originalInput: command,
            timestamp: clock.now()
        )
        return try await execute(command: command, context: context)
    }
    
    // MARK: - Configuration
    
    private func defaultConfiguration(for context: ExecutionContext) -> ExecutionConfiguration {
        switch context.source {
        case .shortcuts, .siri:
            return ExecutionConfiguration.fast
        case .imessage, .whatsapp, .telegram, .slack:
            return ExecutionConfiguration(
                useIntentAnalysis: true,
                preferredCloudTier: .normal,
                allowFallback: true
            )
        case .internalApp:
            return ExecutionConfiguration.default
        case .widget:
            return ExecutionConfiguration(
                useIntentAnalysis: false,
                allowFallback: false
            )
        }
    }
    
    // MARK: - Pipeline
    
    private func executePipeline(
        command: String,
        context: ExecutionContext
    ) async throws -> CommandExecutionResult {
        let start = clock.now()
        try await logCommandReceipt(command: command, context: context)
        let sanitized = try await sanitize(command: command, source: context.source)
        let execution = try await executeEngine(command: sanitized.command, context: context)
        let formatted = try await format(output: execution.text, source: context.source)
        let result = buildResult(
            execution: execution,
            formatted: formatted,
            sanitized: sanitized,
            context: context,
            start: start
        )
        await indexIfNeeded(context: context, result: result, sanitizedCommand: sanitized.command)
        try await logCompletion(context: context, duration: result.executionTime)
        return result
    }
    
    // MARK: - Validation
    
    private func validateCommand(_ command: String) -> Result<Void, FunctionError> {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.invalidInput("Command cannot be empty"))
        }
        if trimmed.count > 20_000 {
            return .failure(.invalidInput("Command exceeds max length"))
        }
        if containsAmbiguousMultiTaskPrompt(trimmed) {
            return .failure(.invalidInput("Command appears to contain multiple tasks"))
        }
        return .success(())
    }
    
    private func containsAmbiguousMultiTaskPrompt(_ command: String) -> Bool {
        let separators = [" and then ", "\n- ", "\n1.", ";"]
        return separators.contains { command.localizedCaseInsensitiveContains($0) }
    }
    
    // MARK: - Steps
    
    private func logCommandReceipt(
        command: String,
        context: ExecutionContext
    ) async throws {
        try await auditService.log(
            type: .remoteCommandReceived,
            source: context.source.rawValue,
            details: "Command from \(context.source.rawValue): \(command.prefix(100))..."
        )
    }
    
    private func sanitize(
        command: String,
        source: ExecutionContext.CommandSource
    ) async throws -> SanitizedCommand {
        let sanitizationResult = inputSanitizer.sanitize(command)
        let criticalViolations = sanitizationResult.violations.filter {
            $0.severity == .critical || $0.severity == .high
        }
        if criticalViolations.isEmpty {
            return SanitizedCommand(
                command: sanitizationResult.sanitized,
                wasSanitized: sanitizationResult.wasSanitized,
                violationCount: sanitizationResult.violations.count
            )
        }
        
        let names = criticalViolations.map { $0.patternName }.joined(separator: ", ")
        try await auditService.log(
            type: .sanitizationTriggered,
            source: source.rawValue,
            details: "Security violations blocked: \(names)"
        )
        throw AppCoordinatorError.securityViolation("Potentially harmful content detected: \(names)")
    }
    
    private func executeEngine(
        command: String,
        context: ExecutionContext
    ) async throws -> HybridExecutionResult {
        do {
            return try await executionManager.executeWithFallback(
                prompt: command,
                configuration: defaultConfiguration(for: context)
            )
        } catch {
            throw AppCoordinatorError.executionFailed(error.localizedDescription)
        }
    }
    
    private func format(
        output: String,
        source: ExecutionContext.CommandSource
    ) async throws -> FormattedOutput? {
        do {
            return try await responseFormatter.format(content: output, source: source)
        } catch {
            throw AppCoordinatorError.formattingFailed
        }
    }
    
    private func buildResult(
        execution: HybridExecutionResult,
        formatted: FormattedOutput?,
        sanitized: SanitizedCommand,
        context: ExecutionContext,
        start: Date
    ) -> CommandExecutionResult {
        CommandExecutionResult(
            output: execution.text,
            formattedOutput: formatted,
            executionTime: clock.now().timeIntervalSince(start),
            routingDecision: execution.decision,
            wasSanitized: sanitized.wasSanitized,
            metadata: [
                "source": context.source.rawValue,
                "sanitized": String(sanitized.wasSanitized),
                "violations": String(sanitized.violationCount),
                "routing": execution.decision.isLocal ? "local" : "cloud"
            ]
        )
    }
    
    private func indexIfNeeded(
        context: ExecutionContext,
        result: CommandExecutionResult,
        sanitizedCommand: String
    ) async {
        guard shouldIndex(context: context, result: result) else {
            return
        }
        await searchIndexer.indexInteraction(
            query: sanitizedCommand,
            response: result.output,
            context: context
        )
    }
    
    private func logCompletion(
        context: ExecutionContext,
        duration: TimeInterval
    ) async throws {
        try await auditService.log(
            type: .shadowRouterDecision,
            source: context.source.rawValue,
            details: "Execution completed in \(String(format: "%.2f", duration))s"
        )
    }
    
    private func hashableOutputMaterial(for result: CommandExecutionResult) -> String {
        let metadata = result.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return [result.output, metadata, String(result.executionTime)].joined(separator: "#")
    }
    
    private func mapFunctionError(_ error: FunctionError) -> AppCoordinatorError {
        switch error {
        case .invalidInput:
            return .invalidInput
        case .timeoutExceeded(let seconds):
            return .executionFailed("Execution timed out after \(seconds)s")
        case .cancellationRequested:
            return .executionFailed("Execution cancelled")
        case .memoryBudgetExceeded(let limit, let observed):
            return .executionFailed("Memory budget exceeded \(observed)MB > \(limit)MB")
        case .deterministicViolation(let message):
            return .executionFailed(message)
        case .executionFailed(let message):
            return .executionFailed(message)
        }
    }
    
    // MARK: - Indexing Policy
    
    private func shouldIndex(
        context: ExecutionContext,
        result: CommandExecutionResult
    ) -> Bool {
        if result.wasSanitized && result.metadata["violations"] != "0" {
            return false
        }
        
        switch context.source {
        case .shortcuts, .siri, .internalApp:
            return true
        case .imessage, .whatsapp, .telegram, .slack:
            return false
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
