import Foundation
import BadgerRuntime

/// Normalization and sanitization gate for all remote input.
///
/// No remote content may reach the LLM unfiltered. This gate
/// defends against:
///
/// - **Prompt injection** — instruction‑override patterns
/// - **Instruction smuggling** — hidden directives in formatting
/// - **SQL / command injection** — shell and database payloads
/// - **Unicode obfuscation** — homoglyph attacks and RTL overrides
public struct SanitizationGate: Sendable {

    public init() {}

    // MARK: - Public API

    /// Sanitize and normalize a raw remote command.
    ///
    /// - Returns: Cleaned text, or `nil` if the input is rejected.
    public func sanitize(_ rawText: String) -> SanitizationResult {
        var text = rawText

        // Step 1: Unicode normalisation (NFC) to collapse homoglyphs.
        text = text.precomposedStringWithCanonicalMapping

        // Step 2: Strip Unicode control characters and RTL overrides.
        text = stripUnicodeObfuscation(text)

        // Step 3: Prompt injection defense.
        text = stripPromptInjection(text)

        // Step 4: SQL injection patterns.
        text = stripSQLInjection(text)

        // Step 5: Command injection patterns.
        text = stripCommandInjection(text)

        // Step 6: Instruction smuggling (hidden directives in whitespace / zero‑width).
        text = stripInstructionSmuggling(text)

        // Reject if content is now empty.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .rejected(reason: "Input is empty after sanitization")
        }

        return .clean(content: trimmed)
    }

    // MARK: - Filters

    private func stripUnicodeObfuscation(_ text: String) -> String {
        var cleaned = text

        // Remove RTL/LTR override characters.
        let bidiControls: [Character] = [
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
            "\u{200F}", "\u{200E}",
        ]
        cleaned.removeAll { bidiControls.contains($0) }

        // Remove zero‑width characters.
        let zeroWidth: [Character] = [
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}",
        ]
        cleaned.removeAll { zeroWidth.contains($0) }

        return cleaned
    }

    private func stripPromptInjection(_ text: String) -> String {
        var safe = text
        let patterns = [
            "ignore previous instructions",
            "ignore all previous",
            "disregard above",
            "new instructions:",
            "system prompt:",
            "you are now",
            "pretend to be",
            "act as if",
            "override:",
            "jailbreak",
            "DAN mode",
            "\\[INST\\]",
            "\\[/INST\\]",
            "<\\|im_start\\|>",
            "<\\|im_end\\|>",
            "<<SYS>>",
            "<</SYS>>",
        ]
        for pattern in patterns {
            safe = safe.replacingOccurrences(
                of: pattern,
                with: "[BLOCKED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return safe
    }

    private func stripSQLInjection(_ text: String) -> String {
        var safe = text
        let patterns = [
            "(?i)('\\s*OR\\s+'1'\\s*=\\s*'1)",
            "(?i)(UNION\\s+SELECT)",
            "(?i)(DROP\\s+TABLE)",
            "(?i)(INSERT\\s+INTO)",
            "(?i)(DELETE\\s+FROM)",
            "(?i)(UPDATE\\s+.*SET)",
            "(?i)(;\\s*--)",
            "(?i)(xp_cmdshell)",
        ]
        for pattern in patterns {
            safe = safe.replacingOccurrences(
                of: pattern,
                with: "[BLOCKED]",
                options: .regularExpression
            )
        }
        return safe
    }

    private func stripCommandInjection(_ text: String) -> String {
        var safe = text
        let patterns = [
            "(?i)(;\\s*rm\\s)",
            "(?i)(\\|\\s*cat\\s)",
            "(?i)(`[^`]+`)",             // Backtick command substitution
            "(?i)(\\$\\([^)]+\\))",      // $() command substitution
            "(?i)(&&\\s*sudo\\s)",
            "(?i)(\\|\\|\\s*curl\\s)",
            "(?i)(>\\s*/etc/)",
            "(?i)(chmod\\s+[0-7]{3,4})",
        ]
        for pattern in patterns {
            safe = safe.replacingOccurrences(
                of: pattern,
                with: "[BLOCKED]",
                options: .regularExpression
            )
        }
        return safe
    }

    private func stripInstructionSmuggling(_ text: String) -> String {
        // Remove sequences of control characters that might hide directives.
        text.replacingOccurrences(
            of: "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]",
            with: "",
            options: .regularExpression
        )
    }
}
