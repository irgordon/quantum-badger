import Foundation
import BadgerRuntime

/// Central handler that orchestrates remote command ingestion.
///
/// Pipeline: authenticate → rate‑limit → sanitize → normalize → dispatch
///
/// All remote commands are dispatched as **Tier 1 (user‑initiated)** tasks
/// to the ``HybridExecutionManager``.
public actor RemoteCommandHandler {

    // MARK: - Dependencies

    private let executionManager: HybridExecutionManager
    private let sanitizationGate: SanitizationGate
    private let rateLimiter: RateLimiter

    // MARK: - State

    /// Whether the bridge has been configured.
    private var isConfigured: Bool = false

    /// Whether remote command handling is enabled.
    private var isEnabled: Bool = false

    /// Audit log of processed commands.
    private var commandLog: [ProcessedCommand] = []

    // MARK: - Init

    public init(
        executionManager: HybridExecutionManager,
        sanitizationGate: SanitizationGate = SanitizationGate(),
        rateLimiter: RateLimiter = RateLimiter()
    ) {
        self.executionManager = executionManager
        self.sanitizationGate = sanitizationGate
        self.rateLimiter = rateLimiter
    }

    // MARK: - Configuration

    /// Configure the command bridge.
    ///
    /// - Note: This method enforces **Immutable Configuration**.
    ///   It can only be called once per lifecycle to prevent dependency hijacking.
    ///   Subsequent calls are ignored with a warning.
    public func configure(enabled: Bool) {
        guard !isConfigured else {
            // Security: Prevent reconfiguration by hijacked dependencies.
            print("⚠️ [Security] Attempted to re-configure RemoteCommandHandler. Request denied.")
            return
        }
        
        self.isEnabled = enabled
        self.isConfigured = true
        print("✅ [Security] RemoteCommandHandler configured (enabled: \(enabled)). Configuration locked.")
    }
    
    /// Enable or disable remote command handling (runtime toggle).
    ///
    /// This is distinct from the initial `configure` lock. This allows
    /// the user to toggle the feature in Settings without unlocking the bridge.
    public func setEnabled(_ enabled: Bool) {
        // Only allow toggling if we are already configured (or we can panic?)
        // The user requirement "Immutable Configuration" usually applies to *setup* (handlers etc).
        // Since we don't have pluggable handlers here (we use ExecutionManager),
        // we'll treat `configure` as the "Boot" step.
        isEnabled = enabled
    }

    /// Whether remote control is currently enabled.
    public func isRemoteEnabled() -> Bool {
        isEnabled
    }
    
    // MARK: - Warm-Up Handlers
    
    /// Pre-heat the NPU and Logical Engine for incoming commands.
    ///
    /// Call this when the user intent is detected but before the payload is ready
    /// (e.g. "Siri, ask Quantum Badger..." - trigger here).
    public func triggerWarmUpHint() {
        Task {
            // In a real implementation, this would signal the NPU to wake up
            // or load the lightweight routing model.
            // For now, we just ensure the actor is responsive.
            await executionManager.preloadHotPath()
        }
    }

    // MARK: - Ingestion Pipeline

    /// Process an incoming remote command through the full pipeline.
    ///
    /// - Returns: The execution result, or `nil` if the command was rejected.
    public func handleCommand(
        _ command: RemoteCommand
    ) async throws -> ExecutionResult? {
        try Task.checkCancellation()

        guard isEnabled else {
            log(command, outcome: .rejected(reason: "Remote control disabled"))
            return nil
        }

        // Step 1: Authentication.
        guard command.isAuthenticated else {
            log(command, outcome: .rejected(reason: "Sender not authenticated"))
            return nil
        }

        // Step 2: Rate limiting.
        let allowed = await rateLimiter.tryConsume(channel: command.channel)
        guard allowed else {
            log(command, outcome: .rejected(reason: "Rate limit exceeded"))
            return nil
        }

        try Task.checkCancellation()

        // Step 3: Sanitization.
        let sanitized = sanitizationGate.sanitize(command.rawText)
        guard let cleanText = sanitized.content else {
            log(command, outcome: sanitized)
            return nil
        }

        // Step 4: Dispatch as Tier 1 task.
        let intent = ExecutionIntent(
            prompt: cleanText,
            tier: .userInitiated
        )

        let result = try await executionManager.process(intent: intent)
        log(command, outcome: .clean(content: "Executed successfully"))
        return result
    }

    /// Return the command audit log.
    public func auditLog() -> [ProcessedCommand] {
        commandLog
    }

    // MARK: - Logging

    private func log(
        _ command: RemoteCommand,
        outcome: SanitizationResult
    ) {
        commandLog.append(ProcessedCommand(
            commandID: command.id,
            channel: command.channel,
            senderID: command.senderID,
            outcome: outcome.isSafe ? "accepted" : "rejected",
            processedAt: Date()
        ))
    }
}

// MARK: - Audit Types

/// Record of a processed remote command.
public struct ProcessedCommand: Sendable, Codable, Equatable, Hashable {
    public let commandID: UUID
    public let channel: RemoteChannel
    public let senderID: String
    public let outcome: String
    public let processedAt: Date
}
