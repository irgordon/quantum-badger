import Foundation

/// Shared registry for all PII and sensitive data patterns.
/// This ensures consistent detection across InputSanitizer and PrivacyEgressFilter.
public enum PrivacyRegistry {

    /// A unified pattern definition for sensitive data
    public struct Pattern: Sendable {
        public let id: String
        public let regex: String
        public let replacement: String
        public let severity: Severity
        public let type: SensitiveDataType?
        public let confidence: Confidence

        public enum Severity: String, Sendable, Codable {
            case low = "Low"
            case medium = "Medium"
            case high = "High"
            case critical = "Critical"
        }

        public enum Confidence: String, Sendable {
            case high = "High"
            case medium = "Medium"
            case low = "Low"
        }

        public enum SensitiveDataType: String, Sendable, CaseIterable {
            case ssn = "SSN"
            case email = "Email"
            case phone = "Phone"
            case creditCard = "CreditCard"
            case ipAddress = "IPAddress"
            case macAddress = "MACAddress"
            case apiKey = "APIKey"
            case password = "Password"
            case accessToken = "AccessToken"
            case passport = "Passport"
            case driverLicense = "DriverLicense"
            case bankAccount = "BankAccount"
            case healthRecord = "HealthRecord"
            case dateOfBirth = "DateOfBirth"
            case address = "Address"

            public var redactionPlaceholder: String {
                "[REDACTED_\(rawValue.uppercased())]"
            }

            public var isHighRisk: Bool {
                switch self {
                case .ssn, .creditCard, .passport, .driverLicense,
                     .bankAccount, .healthRecord, .apiKey, .accessToken, .password:
                    return true
                default:
                    return false
                }
            }
        }
    }

    // MARK: - SQL Injection Patterns

    public static let sqlInjectionPatterns: [Pattern] = [
        Pattern(id: "SQL_UNION_INJECTION", regex: #"(?i)(?:union\s+select|union\s+all\s+select|union\s+distinct\s+select)"#, replacement: "[REDACTED_SQL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SQL_DROP_TABLE", regex: #"(?i)(?:drop\s+table|drop\s+database|delete\s+from|truncate\s+table)"#, replacement: "[REDACTED_SQL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SQL_INSERT_INJECTION", regex: #"(?i)(?:insert\s+into|update\s+.*\s+set)"#, replacement: "[REDACTED_SQL]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "SQL_COMMENT", regex: #"(?i)(?:--|/\*|\*/|#)"#, replacement: "[REDACTED_SQL]", severity: .medium, type: nil, confidence: .medium),
        Pattern(id: "SQL_OR_INJECTION", regex: #"(?i)(?:or\s+1\s*=\s*1|or\s+'[^']*'\s*=\s*'[^']*')"#, replacement: "[REDACTED_SQL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SQL_SLEEP", regex: #"(?i)(?:sleep\s*\(\s*\d+\s*\)|benchmark\s*\(\s*\d+\s*,)"#, replacement: "[REDACTED_SQL]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "SQL_STACKED_QUERIES", regex: #"(?i)(?:;\s*(?:select|insert|update|delete|drop|create|alter))"#, replacement: "[REDACTED_SQL]", severity: .critical, type: nil, confidence: .high)
    ]

    // MARK: - Shell Injection Patterns

    public static let shellInjectionPatterns: [Pattern] = [
        Pattern(id: "SHELL_EXEC", regex: #"(?i)(?:\$\(|`|;\s*\b(?:bash|sh|zsh|python|ruby|perl)\b|\|\s*\b(?:bash|sh|zsh)\b)"#, replacement: "[REDACTED_SHELL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SHELL_REDIRECT", regex: #"(?i)(?:[0-9]*\s*>\s*(?:/dev/)?\w+|2>&1|&>\s*\w+)"#, replacement: "[REDACTED_SHELL]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "SHELL_PIPE", regex: #"(?i)(?:\|\s*(?:cat|less|more|head|tail|grep|awk|sed|cut|sort|uniq|xargs|sh|bash|zsh))"#, replacement: "[REDACTED_SHELL]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "SHELL_VARIABLE", regex: #"(?i)(?:\$\w+|\$\{[^}]+\}|\$\([^)]+\))"#, replacement: "[REDACTED_SHELL]", severity: .medium, type: nil, confidence: .medium),
        Pattern(id: "SHELL_CHAIN", regex: #"(?i)(?:;\s*(?:rm|mv|cp|cat|echo|wget|curl|nc|netcat)\b|\|\||&&)"#, replacement: "[REDACTED_SHELL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SHELL_DOWNLOAD", regex: #"(?i)(?:wget\s+|curl\s+.*\s+-o\s+|curl\s+.*\s+--output\s+)"#, replacement: "[REDACTED_SHELL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SHELL_BACKTICKS", regex: #"`[^`]*`"#, replacement: "[REDACTED_SHELL]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "SHELL_SUBSHELL", regex: #"\$\([^)]*\)"#, replacement: "[REDACTED_SHELL]", severity: .critical, type: nil, confidence: .high)
    ]

    // MARK: - Path Traversal Patterns

    public static let pathTraversalPatterns: [Pattern] = [
        Pattern(id: "PATH_TRAVERSAL", regex: #"(?:\.\./|\.\.\\|%2e%2e%2f|%2e%2e/|\.\./|%252e%252e%252f)"#, replacement: "[REDACTED_PATH]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "PATH_ABSOLUTE", regex: #"(?i)(?:/etc/passwd|/etc/shadow|/proc/self|/var/log|/private/etc|C:\\Windows|C:\\Program\s+Files)"#, replacement: "[REDACTED_PATH]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "PATH_NULL_BYTE", regex: #"%00"#, replacement: "[REDACTED_PATH]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "PATH_ENCODED", regex: #"%2f|%5c|0x2f|0x5c"#, replacement: "[REDACTED_PATH]", severity: .high, type: nil, confidence: .high)
    ]

    // MARK: - XSS Patterns

    public static let xssPatterns: [Pattern] = [
        Pattern(id: "XSS_SCRIPT_TAG", regex: #"(?i)(?:<script[^>]*>.*?</script>|javascript:)"#, replacement: "[REDACTED_XSS]", severity: .critical, type: nil, confidence: .high),
        Pattern(id: "XSS_EVENT_HANDLER", regex: #"(?i)(?:on\w+\s*=\s*['\"]?)"#, replacement: "[REDACTED_XSS]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "XSS_HTML_TAG", regex: #"(?i)(?:<iframe|<object|<embed|<form|<input|<button)"#, replacement: "[REDACTED_XSS]", severity: .high, type: nil, confidence: .high),
        Pattern(id: "XSS_DATA_URI", regex: #"(?i)(?:data:text/html|data:application/javascript)"#, replacement: "[REDACTED_XSS]", severity: .critical, type: nil, confidence: .high)
    ]

    // MARK: - PII Patterns

    public static let piiPatterns: [Pattern] = [
        Pattern(id: "PII_SSN", regex: #"\b(\d{3}-\d{2}-\d{4}|\d{9})\b"#, replacement: "[REDACTED_SSN]", severity: .critical, type: .ssn, confidence: .high),
        Pattern(id: "PII_EMAIL", regex: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, replacement: "[REDACTED_EMAIL]", severity: .high, type: .email, confidence: .high),
        Pattern(id: "PII_PHONE", regex: #"\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b"#, replacement: "[REDACTED_PHONE]", severity: .high, type: .phone, confidence: .high),

        // Credit card patterns
        Pattern(id: "PII_CREDIT_CARD_VISA16", regex: #"\b4[0-9]{15}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),
        Pattern(id: "PII_CREDIT_CARD_VISA13", regex: #"\b4[0-9]{12}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),
        Pattern(id: "PII_CREDIT_CARD_MASTERCARD", regex: #"\b5[1-5][0-9]{14}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),
        Pattern(id: "PII_CREDIT_CARD_AMEX", regex: #"\b3[47][0-9]{13}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),
        Pattern(id: "PII_CREDIT_CARD_DINERS", regex: #"\b3(?:0[0-5]|[68][0-9])[0-9]{11}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),
        Pattern(id: "PII_CREDIT_CARD_DISCOVER", regex: #"\b6(?:011|5[0-9]{2})[0-9]{12}\b"#, replacement: "[REDACTED_CREDITCARD]", severity: .critical, type: .creditCard, confidence: .high),

        Pattern(id: "PII_IP_ADDRESS", regex: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#, replacement: "[REDACTED_IPADDRESS]", severity: .medium, type: .ipAddress, confidence: .medium),
        Pattern(id: "PII_MAC_ADDRESS", regex: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})\b"#, replacement: "[REDACTED_MACADDRESS]", severity: .medium, type: .macAddress, confidence: .medium),

        Pattern(id: "PII_API_KEY", regex: #"(?i)(?:api[_-]?key|apikey)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{16,}['\"]?"#, replacement: "[REDACTED_APIKEY]", severity: .critical, type: .apiKey, confidence: .high),
        Pattern(id: "PII_SK_KEY", regex: #"\bsk-[a-zA-Z0-9]{16,}\b"#, replacement: "[REDACTED_APIKEY]", severity: .critical, type: .apiKey, confidence: .high),

        Pattern(id: "PII_PASSWORD", regex: #"(?i)(?:password|passwd|pwd)\s*[:=]\s*['\"]?[^\s'\"]+['\"]?"#, replacement: "[REDACTED_PASSWORD]", severity: .critical, type: .password, confidence: .high),
        Pattern(id: "PII_TOKEN", regex: #"(?i)(?:token|secret|access[_-]?key)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{16,}['\"]?"#, replacement: "[REDACTED_ACCESSTOKEN]", severity: .critical, type: .accessToken, confidence: .high),

        Pattern(id: "PII_PASSPORT", regex: #"\b[A-Z]{1}[0-9]{6,9}\b"#, replacement: "[REDACTED_PASSPORT]", severity: .high, type: .passport, confidence: .medium),
        Pattern(id: "PII_DRIVER_LICENSE", regex: #"(?i)(?:DL|driver[^a-zA-Z])[\s:]*[A-Z0-9]{6,14}\b"#, replacement: "[REDACTED_DRIVERLICENSE]", severity: .high, type: .driverLicense, confidence: .medium),
        Pattern(id: "PII_BANK_ACCOUNT", regex: #"\b\d{8,17}\b"#, replacement: "[REDACTED_BANKACCOUNT]", severity: .high, type: .bankAccount, confidence: .low),
        Pattern(id: "PII_HEALTH_RECORD", regex: #"(?i)(?:MRN|medical[^a-zA-Z]record|patient[^a-zA-Z]ID)[\s:]*[A-Z0-9]{6,10}\b"#, replacement: "[REDACTED_HEALTHRECORD]", severity: .high, type: .healthRecord, confidence: .medium),
        Pattern(id: "PII_DOB", regex: #"(?i)(?:DOB|date[^a-zA-Z]of[^a-zA-Z]birth|born)[\s:]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})"#, replacement: "[REDACTED_DATEOFBIRTH]", severity: .medium, type: .dateOfBirth, confidence: .medium),
        Pattern(id: "PII_ADDRESS", regex: #"\d+\s+([A-Za-z]+\s*)+,(\s*[A-Za-z]+)+,\s*[A-Za-z]{2}\s*\d{5}(-\d{4})?"#, replacement: "[REDACTED_ADDRESS]", severity: .medium, type: .address, confidence: .medium)
    ]

    /// All patterns in the registry
    public static let allPatterns: [Pattern] = {
        sqlInjectionPatterns +
        shellInjectionPatterns +
        pathTraversalPatterns +
        xssPatterns +
        piiPatterns
    }()
}
