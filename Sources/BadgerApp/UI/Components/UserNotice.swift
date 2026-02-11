import Foundation

/// A non‑blocking, human‑readable notice for the UI.
///
/// `UserNotice` is the **only** type used to present system events
/// to the user. It is never a modal alert. The ``NotificationBanner``
/// view modifier renders it as a top‑edge banner that auto‑dismisses.
///
/// ## HIG Compliance
/// - Non‑technical — no stack traces, codes, or internal terminology
/// - Calm — neutral tone, no blame, no alarmism
/// - Actionable — states what happened and what the user can do
public struct UserNotice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let severity: Severity

    /// Auto‑dismiss duration in seconds.
    public let dismissAfterSeconds: Double

    @frozen
    public enum Severity: String, Sendable, Codable {
        /// Routine system event — no action needed.
        case info
        /// Degraded but recoverable condition.
        case warning
        /// The system took a protective measure on the user's behalf.
        case protectiveAction
    }

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        severity: Severity = .info,
        dismissAfterSeconds: Double = 5.0
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.dismissAfterSeconds = dismissAfterSeconds
    }
}

// MARK: - Convenience Factories

extension UserNotice {
    /// Voice input is unavailable.
    static func voiceUnavailable(reason: String) -> UserNotice {
        UserNotice(
            title: "Voice input paused",
            detail: "\(reason) You can try again or type your command.",
            severity: .warning,
            dismissAfterSeconds: 6
        )
    }

    /// Processing was paused due to system protection.
    static func processingPaused(reason: String) -> UserNotice {
        UserNotice(
            title: "Processing paused",
            detail: reason,
            severity: .protectiveAction,
            dismissAfterSeconds: 8
        )
    }

    /// Settings applied successfully.
    static func settingsApplied(setting: String) -> UserNotice {
        UserNotice(
            title: "\(setting) updated",
            detail: "Your preference has been saved and applied.",
            severity: .info,
            dismissAfterSeconds: 3
        )
    }
}
