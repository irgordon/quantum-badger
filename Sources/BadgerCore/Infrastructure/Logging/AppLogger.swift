import Foundation
import os

/// Unified logging facade for Console.app visibility and persistent error logging.
public struct AppLogger: Sendable {

    // MARK: - Categories

    /// Logging category for subsystem routing.
    @frozen
    public enum Category: String, Sendable, Codable, CaseIterable {
        case runtime, remote, ui, security
    }

    /// Human‑facing severity level.
    @frozen
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case info, warning, protectiveAction
    }

    private let osLogger: os.Logger
    private let category: Category
    private let errorLog: ErrorLog

    public init(category: Category, errorLog: ErrorLog) {
        self.category = category
        self.errorLog = errorLog
        // Use Bundle ID for subsystem to avoid hardcoded strings
        self.osLogger = os.Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.quantumbadger",
            category: category.rawValue
        )
    }

    // MARK: - Public API

    public func info(_ message: String) {
        // 🔒 SECURITY: Removed 'privacy: .public'. 
        // macOS will now redact dynamic values in Release builds automatically.
        osLogger.info("\(message)")
        persistEntry(severity: .info, message: message)
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message)")
        persistEntry(severity: .warning, message: message)
    }

    public func protectiveAction(_ message: String) {
        osLogger.error("\(message)")
        persistEntry(severity: .protectiveAction, message: message)
    }

    public func fault(_ message: String) {
        osLogger.fault("\(message)")
        persistEntry(severity: .protectiveAction, message: "[Fault] \(message)")
    }

    // MARK: - Private

    private func persistEntry(severity: Severity, message: String) {
        // ⚡️ PERF: Use detached utility task to avoid cluttering the Main Actor
        Task.detached(priority: .utility) {
            await errorLog.append(
                ErrorEntry(category: category, severity: severity, summary: message)
            )
        }
    }
}
