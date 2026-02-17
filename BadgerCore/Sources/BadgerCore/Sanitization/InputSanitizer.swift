import Foundation

// MARK: - Sanitization Pattern

/// Represents a pattern to detect and sanitize
/// Uses stored regex pattern strings instead of compiled Regex to maintain Sendable conformance
public struct SanitizationPattern: Sendable, Equatable {
    public let name: String
    public let patternString: String
    public let replacement: String
    public let severity: Severity
    
    public enum Severity: String, Sendable, Codable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"
    }
    
    public init(
        name: String,
        patternString: String,
        replacement: String,
        severity: Severity
    ) {
        self.name = name
        self.patternString = patternString
        self.replacement = replacement
        self.severity = severity
    }
    
    /// Compile the pattern string into a Regex
    public func compile() throws -> Regex<AnyRegexOutput> {
        return try Regex(patternString)
    }
}

// MARK: - Sanitization Result

/// Result of a sanitization operation
public struct SanitizationResult: Sendable {
    public let original: String
    public let sanitized: String
    public let violations: [Violation]
    public let wasSanitized: Bool
    
    public struct Violation: Sendable, Identifiable {
        public let id = UUID()
        public let patternName: String
        public let matchedText: String
        public let severity: SanitizationPattern.Severity
        public let replacement: String
    }
    
    public init(
        original: String,
        sanitized: String,
        violations: [Violation]
    ) {
        self.original = original
        self.sanitized = sanitized
        self.violations = violations
        self.wasSanitized = !violations.isEmpty
    }
}

// MARK: - Sanitization Errors

/// Errors that can occur during sanitization
public enum SanitizationError: Error, Sendable {
    case invalidRegexPattern(String)
    case sanitizationFailed(String)
}

// MARK: - Input Sanitizer

/// Struct responsible for sanitizing input strings to remove malicious code patterns
public struct InputSanitizer: Sendable {
    
    /// Internal representation of a compiled sanitization pattern
    private struct CompiledPattern: Sendable {
        let pattern: SanitizationPattern
        let regex: Regex<AnyRegexOutput>
    }

    // MARK: - Default Patterns
    
    /// SQL Injection patterns
    public static let sqlInjectionPatterns: [SanitizationPattern] = [
        SanitizationPattern(
            name: "SQL_UNION_INJECTION",
            patternString: #"(?i)(?:union\s+select|union\s+all\s+select|union\s+distinct\s+select)"#,
            replacement: "[REDACTED_SQL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SQL_DROP_TABLE",
            patternString: #"(?i)(?:drop\s+table|drop\s+database|delete\s+from|truncate\s+table)"#,
            replacement: "[REDACTED_SQL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SQL_INSERT_INJECTION",
            patternString: #"(?i)(?:insert\s+into|update\s+.*\s+set)"#,
            replacement: "[REDACTED_SQL]",
            severity: .high
        ),
        SanitizationPattern(
            name: "SQL_COMMENT",
            patternString: #"(?i)(?:--|/\*|\*/|#)"#,
            replacement: "[REDACTED_SQL]",
            severity: .medium
        ),
        SanitizationPattern(
            name: "SQL_OR_INJECTION",
            patternString: #"(?i)(?:or\s+1\s*=\s*1|or\s+'[^']*'\s*=\s*'[^']*')"#,
            replacement: "[REDACTED_SQL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SQL_SLEEP",
            patternString: #"(?i)(?:sleep\s*\(\s*\d+\s*\)|benchmark\s*\(\s*\d+\s*,)"#,
            replacement: "[REDACTED_SQL]",
            severity: .high
        ),
        SanitizationPattern(
            name: "SQL_STACKED_QUERIES",
            patternString: #"(?i)(?:;\s*(?:select|insert|update|delete|drop|create|alter))"#,
            replacement: "[REDACTED_SQL]",
            severity: .critical
        )
    ]
    
    /// Shell command injection patterns
    public static let shellInjectionPatterns: [SanitizationPattern] = [
        SanitizationPattern(
            name: "SHELL_EXEC",
            patternString: #"(?i)(?:\$\(|`|;\s*\b(?:bash|sh|zsh|python|ruby|perl)\b|\|\s*\b(?:bash|sh|zsh)\b)"#,
            replacement: "[REDACTED_SHELL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SHELL_REDIRECT",
            patternString: #"(?i)(?:[0-9]*\s*>\s*(?:/dev/)?\w+|2>&1|&>\s*\w+)"#,
            replacement: "[REDACTED_SHELL]",
            severity: .high
        ),
        SanitizationPattern(
            name: "SHELL_PIPE",
            patternString: #"(?i)(?:\|\s*(?:cat|less|more|head|tail|grep|awk|sed|cut|sort|uniq|xargs|sh|bash|zsh))"#,
            replacement: "[REDACTED_SHELL]",
            severity: .high
        ),
        SanitizationPattern(
            name: "SHELL_VARIABLE",
            patternString: #"(?i)(?:\$\w+|\$\{[^}]+\}|\$\([^)]+\))"#,
            replacement: "[REDACTED_SHELL]",
            severity: .medium
        ),
        SanitizationPattern(
            name: "SHELL_CHAIN",
            patternString: #"(?i)(?:;\s*(?:rm|mv|cp|cat|echo|wget|curl|nc|netcat)\b|\|\||&&)"#,
            replacement: "[REDACTED_SHELL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SHELL_DOWNLOAD",
            patternString: #"(?i)(?:wget\s+|curl\s+.*\s+-o\s+|curl\s+.*\s+--output\s+)"#,
            replacement: "[REDACTED_SHELL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SHELL_BACKTICKS",
            patternString: #"`[^`]*`"#,
            replacement: "[REDACTED_SHELL]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "SHELL_SUBSHELL",
            patternString: #"\$\([^)]*\)"#,
            replacement: "[REDACTED_SHELL]",
            severity: .critical
        )
    ]
    
    /// Path traversal patterns
    public static let pathTraversalPatterns: [SanitizationPattern] = [
        SanitizationPattern(
            name: "PATH_TRAVERSAL",
            patternString: #"(?:\.\./|\.\.\\|%2e%2e%2f|%2e%2e/|\.\./|%252e%252e%252f)"#,
            replacement: "[REDACTED_PATH]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PATH_ABSOLUTE",
            patternString: #"(?i)(?:/etc/passwd|/etc/shadow|/proc/self|/var/log|/private/etc|C:\\Windows|C:\\Program\s+Files)"#,
            replacement: "[REDACTED_PATH]",
            severity: .high
        ),
        SanitizationPattern(
            name: "PATH_NULL_BYTE",
            patternString: #"%00"#,
            replacement: "[REDACTED_PATH]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PATH_ENCODED",
            patternString: #"%2f|%5c|0x2f|0x5c"#,
            replacement: "[REDACTED_PATH]",
            severity: .high
        )
    ]
    
    /// XSS and HTML injection patterns
    public static let xssPatterns: [SanitizationPattern] = [
        SanitizationPattern(
            name: "XSS_SCRIPT_TAG",
            patternString: #"(?i)(?:<script[^>]*>.*?</script>|javascript:)"#,
            replacement: "[REDACTED_XSS]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "XSS_EVENT_HANDLER",
            patternString: #"(?i)(?:on\w+\s*=\s*['\"]?)"#,
            replacement: "[REDACTED_XSS]",
            severity: .high
        ),
        SanitizationPattern(
            name: "XSS_HTML_TAG",
            patternString: #"(?i)(?:<iframe|<object|<embed|<form|<input|<button)"#,
            replacement: "[REDACTED_XSS]",
            severity: .high
        ),
        SanitizationPattern(
            name: "XSS_DATA_URI",
            patternString: #"(?i)(?:data:text/html|data:application/javascript)"#,
            replacement: "[REDACTED_XSS]",
            severity: .critical
        )
    ]
    
    /// PII (Personally Identifiable Information) patterns
    public static let piiPatterns: [SanitizationPattern] = [
        SanitizationPattern(
            name: "PII_SSN",
            patternString: #"\b\d{3}-\d{2}-\d{4}\b"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PII_CREDIT_CARD",
            patternString: #"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12})\b"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PII_EMAIL",
            patternString: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
            replacement: "[REDACTED_PII]",
            severity: .high
        ),
        SanitizationPattern(
            name: "PII_PHONE",
            patternString: #"\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b"#,
            replacement: "[REDACTED_PII]",
            severity: .high
        ),
        SanitizationPattern(
            name: "PII_IP_ADDRESS",
            patternString: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#,
            replacement: "[REDACTED_PII]",
            severity: .medium
        ),
        SanitizationPattern(
            name: "PII_MAC_ADDRESS",
            patternString: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})\b"#,
            replacement: "[REDACTED_PII]",
            severity: .medium
        ),
        SanitizationPattern(
            name: "PII_API_KEY",
            patternString: #"(?i)(?:api[_-]?key|apikey)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{8,}['\"]?"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PII_SK_KEY",
            patternString: #"(?i)\bsk-[a-zA-Z0-9]{10,}\b"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PII_PASSWORD",
            patternString: #"(?i)(?:password|passwd|pwd)\s*[:=]\s*['\"]?[^\s'\"]+['\"]?"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        ),
        SanitizationPattern(
            name: "PII_TOKEN",
            patternString: #"(?i)(?:token|secret|access[_-]?key)\s*[:=]\s*['\"]?[a-zA-Z0-9_-]{16,}['\"]?"#,
            replacement: "[REDACTED_PII]",
            severity: .critical
        )
    ]
    
    /// Combined default patterns
    public static let defaultPatterns: [SanitizationPattern] = {
        sqlInjectionPatterns +
        shellInjectionPatterns +
        pathTraversalPatterns +
        xssPatterns +
        piiPatterns
    }()
    
    /// Cached compiled default patterns to avoid recompilation
    private static let defaultCompiledPatterns: [CompiledPattern] = {
        defaultPatterns.compactMap { pattern in
            guard let regex = try? pattern.compile() else { return nil }
            return CompiledPattern(pattern: pattern, regex: regex)
        }
    }()

    // MARK: - Properties
    
    private let compiledPatterns: [CompiledPattern]
    
    // MARK: - Initialization
    
    /// Create a sanitizer with custom patterns
    /// - Parameter patterns: The patterns to use for sanitization
    public init(patterns: [SanitizationPattern] = InputSanitizer.defaultPatterns) {
        if patterns == InputSanitizer.defaultPatterns {
            self.compiledPatterns = InputSanitizer.defaultCompiledPatterns
        } else {
            self.compiledPatterns = patterns.compactMap { pattern in
                guard let regex = try? pattern.compile() else { return nil }
                return CompiledPattern(pattern: pattern, regex: regex)
            }
        }
    }
    
    /// Create a sanitizer for specific threat categories
    /// - Parameters:
    ///   - includeSQL: Include SQL injection patterns
    ///   - includeShell: Include shell injection patterns
    ///   - includePath: Include path traversal patterns
    ///   - includeXSS: Include XSS patterns
    ///   - includePII: Include PII patterns
    public init(
        includeSQL: Bool = true,
        includeShell: Bool = true,
        includePath: Bool = true,
        includeXSS: Bool = true,
        includePII: Bool = true
    ) {
        // If all are true (default), use the cached default compiled patterns
        if includeSQL && includeShell && includePath && includeXSS && includePII {
            self.compiledPatterns = InputSanitizer.defaultCompiledPatterns
            return
        }

        var selectedPatterns: [SanitizationPattern] = []
        
        if includeSQL {
            selectedPatterns.append(contentsOf: InputSanitizer.sqlInjectionPatterns)
        }
        if includeShell {
            selectedPatterns.append(contentsOf: InputSanitizer.shellInjectionPatterns)
        }
        if includePath {
            selectedPatterns.append(contentsOf: InputSanitizer.pathTraversalPatterns)
        }
        if includeXSS {
            selectedPatterns.append(contentsOf: InputSanitizer.xssPatterns)
        }
        if includePII {
            selectedPatterns.append(contentsOf: InputSanitizer.piiPatterns)
        }
        
        self.compiledPatterns = selectedPatterns.compactMap { pattern in
            guard let regex = try? pattern.compile() else { return nil }
            return CompiledPattern(pattern: pattern, regex: regex)
        }
    }
    
    // MARK: - Sanitization Methods
    
    /// Sanitize a string by applying all configured patterns.
    /// Safely handles string index changes by separating detection from replacement.
    /// - Parameter input: The string to sanitize
    /// - Returns: A SanitizationResult containing the sanitized string and any violations found
    public func sanitize(_ input: String) -> SanitizationResult {
        var sanitized = input
        var violations: [SanitizationResult.Violation] = []
        
        for compiled in compiledPatterns {
            let regex = compiled.regex
            let pattern = compiled.pattern

            // 1. Detection Phase: Find matches to log violations
            let matches = sanitized.matches(of: regex)
            if matches.isEmpty { continue }

            // Record violations
            for match in matches {
                let matchedText = String(sanitized[match.range])
                let violation = SanitizationResult.Violation(
                    patternName: pattern.name,
                    matchedText: matchedText,
                    severity: pattern.severity,
                    replacement: pattern.replacement
                )
                violations.append(violation)
            }

            // 2. Replacement Phase: Safe substitution
            // Using standard String regex replacement which handles indices automatically
            sanitized.replace(regex, with: pattern.replacement)
        }
        
        return SanitizationResult(
            original: input,
            sanitized: sanitized,
            violations: violations
        )
    }
    
    /// Quickly check if a string contains any malicious patterns
    /// - Parameter input: The string to check
    /// - Returns: True if malicious patterns are detected
    public func containsMaliciousPatterns(_ input: String) -> Bool {
        for compiled in compiledPatterns {
            if input.contains(compiled.regex) {
                return true
            }
        }
        return false
    }
    
    /// Get all patterns that match in the input string
    /// - Parameter input: The string to check
    /// - Returns: Array of pattern names that matched
    public func getMatchingPatterns(_ input: String) -> [String] {
        var matches: [String] = []
        
        for compiled in compiledPatterns {
            if input.contains(compiled.regex) {
                matches.append(compiled.pattern.name)
            }
        }
        
        return matches
    }
    
    /// Sanitize with a whitelist approach - only allow specific characters
    /// - Parameters:
    ///   - input: The string to sanitize
    ///   - allowedCharacters: CharacterSet of allowed characters
    /// - Returns: Sanitized string containing only allowed characters
    public static func whitelistSanitize(
        _ input: String,
        allowedCharacters: CharacterSet = .alphanumerics
    ) -> String {
        return input.unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map { String($0) }
            .joined()
    }
    
    /// Escape special regex characters in a string
    /// - Parameter string: The string to escape
    /// - Returns: Escaped string safe for use in regex
    public static func escapeForRegex(_ string: String) -> String {
        let specialCharacters = #"\^$.*+?()[]{}|"#
        var escaped = ""
        
        for char in string {
            if specialCharacters.contains(char) {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        
        return escaped
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Check if this string contains malicious patterns using the default sanitizer
    public var containsMaliciousPatterns: Bool {
        InputSanitizer().containsMaliciousPatterns(self)
    }
    
    /// Sanitize this string using the default sanitizer
    public var sanitized: String {
        InputSanitizer().sanitize(self).sanitized
    }
}
