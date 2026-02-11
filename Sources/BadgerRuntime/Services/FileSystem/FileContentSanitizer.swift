import Foundation

/// Bidirectional content sanitizer for the Secure File Manager.
///
/// Filters are split into two paths:
///
/// **Ingestion** (user → LLM):
/// - Embedded JavaScript in PDFs
/// - Macro payloads (VBA, Office macros)
/// - Steganographic markers
/// - EXIF‑embedded commands
/// - Polyglot file attacks
///
/// **Generation** (LLM → disk):
/// - Executable code emission (shell, AppleScript, `<script>`)
/// - Path traversal in filenames
/// - Oversized output beyond budget
/// - Prompt‑injection echo‑back
public struct FileContentSanitizer: Sendable {

    /// Maximum output size in bytes before rejection (10 MB).
    public let maxOutputBytes: UInt64

    public init(maxOutputBytes: UInt64 = 10 * 1024 * 1024) {
        self.maxOutputBytes = maxOutputBytes
    }

    // MARK: - Ingestion Sanitization

    /// Sanitize content extracted from an ingested file.
    public func sanitizeIngestion(_ content: String) -> SanitizationResult {
        var text = content

        // Strip embedded JavaScript.
        text = stripPattern(text, pattern: "<script[^>]*>[\\s\\S]*?</script>")
        text = stripPattern(text, pattern: "javascript\\s*:")

        // Strip VBA / Office macro markers.
        text = stripPattern(text, pattern: "(?i)(Sub |Function |End Sub|End Function|Dim )")
        text = stripPattern(text, pattern: "(?i)Auto_Open|AutoExec|Document_Open")

        // Strip steganographic markers (common binary escape sequences).
        text = stripPattern(text, pattern: "\\\\x[0-9a-fA-F]{2}")

        // Strip EXIF command patterns.
        text = stripPattern(text, pattern: "(?i)exiftool|exif:.*=")

        // Strip common polyglot attack signatures.
        text = stripPattern(text, pattern: "%PDF.*?%%EOF")

        // Prompt injection defense.
        text = stripPromptInjection(text)

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(reason: "Content is empty after sanitization")
        }

        return .clean(content: text)
    }

    // MARK: - Generation Sanitization

    /// Sanitize content produced by an LLM before writing to disk.
    public func sanitizeGeneration(
        _ content: String,
        filename: String
    ) -> SanitizationResult {
        // Path traversal check.
        if filename.contains("..") || filename.contains("/") || filename.contains("\\") {
            return .rejected(reason: "Filename contains path traversal characters")
        }

        // Size check.
        let byteCount = UInt64(content.utf8.count)
        if byteCount > maxOutputBytes {
            return .rejected(
                reason: "Output size \(byteCount) bytes exceeds budget of \(maxOutputBytes) bytes"
            )
        }

        var text = content

        // Block executable code emission.
        let executablePatterns = [
            "#!/",                              // Shebang
            "osascript",                        // AppleScript invocation
            "tell application",                 // AppleScript
            "<script",                          // JavaScript
            "eval(",                            // Dynamic code execution
            "exec(",                            // Shell exec
            "system(",                          // System calls
            "subprocess",                       // Python subprocess
            "Runtime.getRuntime().exec",        // Java exec
            "Process.Start",                    // .NET process
            "rm -rf",                           // Destructive shell
            "sudo ",                            // Privilege escalation
            "chmod ",                           // Permission change
            "curl ",                            // Network fetch
            "wget ",                            // Network fetch
        ]

        for pattern in executablePatterns {
            if text.localizedCaseInsensitiveContains(pattern) {
                text = text.replacingOccurrences(
                    of: pattern,
                    with: "[BLOCKED:\(pattern)]",
                    options: .caseInsensitive
                )
            }
        }

        // Prompt injection echo-back defense.
        text = stripPromptInjection(text)

        return .clean(content: text)
    }

    // MARK: - Shared Filters

    private func stripPattern(_ text: String, pattern: String) -> String {
        text.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }

    private func stripPromptInjection(_ text: String) -> String {
        var safe = text
        let injectionPatterns = [
            "ignore previous instructions",
            "ignore all previous",
            "disregard above",
            "new instructions:",
            "system prompt:",
            "you are now",
            "\\[INST\\]",
            "\\[/INST\\]",
            "<\\|im_start\\|>",
            "<\\|im_end\\|>",
        ]
        for pattern in injectionPatterns {
            safe = safe.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return safe
    }
}
