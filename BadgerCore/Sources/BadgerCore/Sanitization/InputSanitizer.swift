import Foundation

// MARK: - Sanitization Pattern

/// Represents a pattern to detect and sanitize
/// Uses stored regex pattern strings instead of compiled Regex to maintain Sendable conformance
public struct SanitizationPattern: Sendable, Equatable {
    public let name: String
    public let patternString: String
    public let replacement: String
    public let severity: Severity
    
    public typealias Severity = PrivacyRegistry.Pattern.Severity
    
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
    
    public init(from pattern: PrivacyRegistry.Pattern) {
        self.name = pattern.id
        self.patternString = pattern.regex
        self.replacement = pattern.replacement
        self.severity = pattern.severity
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
    public static let sqlInjectionPatterns: [SanitizationPattern] = PrivacyRegistry.sqlInjectionPatterns.map { SanitizationPattern(from: $0) }
    
    /// Shell command injection patterns
    public static let shellInjectionPatterns: [SanitizationPattern] = PrivacyRegistry.shellInjectionPatterns.map { SanitizationPattern(from: $0) }
    
    /// Path traversal patterns
    public static let pathTraversalPatterns: [SanitizationPattern] = PrivacyRegistry.pathTraversalPatterns.map { SanitizationPattern(from: $0) }
    
    /// XSS and HTML injection patterns
    public static let xssPatterns: [SanitizationPattern] = PrivacyRegistry.xssPatterns.map { SanitizationPattern(from: $0) }
    
    /// PII (Personally Identifiable Information) patterns
    public static let piiPatterns: [SanitizationPattern] = PrivacyRegistry.piiPatterns.map { SanitizationPattern(from: $0) }
    
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
        return String(input.unicodeScalars.filter { allowedCharacters.contains($0) })
    }
    
    /// Escape special regex characters in a string
    /// - Parameter string: The string to escape
    /// - Returns: Escaped string safe for use in regex
    public static func escapeForRegex(_ string: String) -> String {
        return NSRegularExpression.escapedPattern(for: string)
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
