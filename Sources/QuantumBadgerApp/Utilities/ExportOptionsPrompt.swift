import AppKit
import Foundation

@MainActor
enum ExportOptionsPrompt {
    static func present() async -> ExportOption? {
        await present(
            title: "Export Activity Log",
            message: "Choose a format. Encrypted is recommended for privacy."
        )
    }

    static func presentPlanReport() async -> ExportOption? {
        await present(
            title: "Export Workflow Report",
            message: "Choose a format. Encrypted is recommended for privacy."
        )
    }

    private static func present(title: String, message: String) async -> ExportOption? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Encrypted (Recommended)")
        alert.addButton(withTitle: "Plain JSON (Not Recommended)")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return await promptForPassword()
        case .alertSecondButtonReturn:
            return confirmUnencrypted()
        default:
            return nil
        }
    }

    private static func promptForPassword() async -> ExportOption? {
        let passwordField = NSSecureTextField()
        passwordField.placeholderString = "Export password"
        let strengthLabel = NSTextField(labelWithString: "Strength: —")
        strengthLabel.textColor = .secondaryLabelColor

        let strengthTarget = PasswordStrengthTarget(strengthLabel: strengthLabel)
        passwordField.target = strengthTarget
        passwordField.action = #selector(PasswordStrengthTarget.passwordChanged(_:))

        let alert = NSAlert()
        alert.messageText = "Set an Export Password"
        alert.informativeText = "Use a strong password to open this file on any Mac."
        let stack = NSStackView(views: [passwordField, strengthLabel])
        stack.orientation = .vertical
        stack.spacing = 6
        alert.accessoryView = stack
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return nil }

        if PasswordStrength.evaluate(password) == .weak {
            let warn = NSAlert()
            warn.messageText = "Weak Password"
            warn.informativeText = "This password is easy to guess. Use a stronger password for better protection."
            warn.addButton(withTitle: "Use Anyway")
            warn.addButton(withTitle: "Change Password")
            let warnResponse = warn.runModal()
            if warnResponse != .alertFirstButtonReturn {
                return nil
            }
        }

        let authManager = AuthenticationManager()
        do {
            _ = try await authManager.authenticate(reason: "Confirm export with Touch ID.")
        } catch {
            // Biometric fallback: allow password-only export.
        }

        return .encryptedWithPassword(password)
    }

    private static func confirmUnencrypted() -> ExportOption? {
        let alert = NSAlert()
        alert.messageText = "Export Unencrypted Log?"
        alert.informativeText = "This file contains your full activity history and will not be protected."
        alert.addButton(withTitle: "Export Unencrypted")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return .unencryptedJSON
        }
        return nil
    }
}

private final class PasswordStrengthTarget: NSObject {
    private weak var strengthLabel: NSTextField?

    init(strengthLabel: NSTextField) {
        self.strengthLabel = strengthLabel
    }

    @objc func passwordChanged(_ sender: NSSecureTextField) {
        let password = sender.stringValue
        let strength = PasswordStrength.evaluate(password)
        strengthLabel?.stringValue = "Strength: \(strength.label)"
        strengthLabel?.textColor = strength.color
    }
}

private enum PasswordStrength {
    case weak
    case okay
    case strong

    var label: String {
        switch self {
        case .weak: return "Weak"
        case .okay: return "Okay"
        case .strong: return "Strong"
        }
    }

    var color: NSColor {
        switch self {
        case .weak: return .systemRed
        case .okay: return .systemOrange
        case .strong: return .systemGreen
        }
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        let length = password.count
        let hasUpper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil
        let score = [hasUpper, hasLower, hasNumber, hasSymbol].filter { $0 }.count

        if length >= 12 && score >= 3 { return .strong }
        if length >= 8 && score >= 2 { return .okay }
        return .weak
    }
}

enum ExportOption {
    case encryptedWithPassword(String)
    case unencryptedJSON

    var isEncrypted: Bool {
        switch self {
        case .encryptedWithPassword: return true
        case .unencryptedJSON: return false
        }
    }

    var allowedFileTypes: [String] {
        switch self {
        case .encryptedWithPassword:
            return ["qbaudit"]
        case .unencryptedJSON:
            return ["json"]
        }
    }

    var password: String? {
        switch self {
        case .encryptedWithPassword(let password):
            return password
        case .unencryptedJSON:
            return nil
        }
    }
}
