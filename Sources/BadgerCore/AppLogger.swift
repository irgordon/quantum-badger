import Foundation
import os

/// Unified logging facade for Console.app visibility and persistent error logging.
///
/// Every log call is dual‑routed:
/// 1. Apple's `os.Logger` → visible in Console.app and crash reports
/// 2. Persistent ``ErrorLog`` → queryable in‑app via the Error Log Viewer
///
/// Thread‑safe: all methods are `nonisolated` and `Sendable`.
/// The underlying `os.Logger` is inherently thread‑safe, and
/// the `ErrorLog` actor handles its own isolation.
public struct AppLogger: Sendable {

    // MARK: - Categories

    /// Logging category for subsystem routing.
    @frozen
    public enum Category: String, Sendable, Codable, CaseIterable {
        case runtime
        case remote
        case ui
        case security
    }

    /// Human‑facing severity level.
    ///
    /// These map to HIG‑compliant language:
    /// - **info** — routine system events
    /// - **warning** — degraded but recoverable conditions
    /// - **protectiveAction** — the system took a protective measure
    @frozen
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case info
        case warning
        case protectiveAction
    }

    // MARK: - State

    private let osLogger: os.Logger
    private let category: Category
    private let errorLog: ErrorLog

    // MARK: - Init

    /// Create a logger for a specific category.
    ///
    /// - Parameters:
    ///   - category: The subsystem category.
    ///   - errorLog: The shared persistent error log instance.
    public init(category: Category, errorLog: ErrorLog) {
        self.category = category
        self.errorLog = errorLog
        self.osLogger = os.Logger(
            subsystem: "com.quantumbadger.app",
            category: category.rawValue
        )
    }

    // MARK: - Public API

    /// Log an informational event.
    ///
    /// Use for routine system events that are useful for diagnostics
    /// but do not require user attention.
    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        persistEntry(severity: .info, message: message)
    }

    /// Log a warning condition.
    ///
    /// Use when the system is in a degraded but recoverable state.
    /// Example: "Memory pressure elevated — model budget reduced."
    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        persistEntry(severity: .warning, message: message)
    }

    /// Log a protective action taken by the system.
    ///
    /// Use when the system autonomously protected itself or the user.
    /// Example: "Local inference paused — thermal throttling active."
    public func protectiveAction(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        persistEntry(severity: .protectiveAction, message: message)
    }

    /// Log a critical fault. These always appear in Console.app crash logs.
    ///
    /// Reserved for conditions that should never occur in normal operation.
    public func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        persistEntry(severity: .protectiveAction, message: "[Fault] \(message)")
    }

    // MARK: - Private

    private func persistEntry(severity: Severity, message: String) {
        let entry = ErrorEntry(
            category: category,
            severity: severity,
            summary: message
        )
        Task {
            await errorLog.append(entry)
        }
    }
}
