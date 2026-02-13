import Foundation

// MARK: - Privacy Egress Filter

public struct PrivacyEgressFilter: Sendable {
    
    public enum SensitiveDataType: String, Sendable, CaseIterable, CustomStringConvertible {
        case socialSecurityNumber = "SSN"
        case emailAddress = "Email"
        case phoneNumber = "Phone"
        case creditCard = "CreditCard"
        case ipAddress = "IPAddress"
        case macAddress = "MACAddress"
        case apiKey = "APIKey"
        case password = "Password"
        case accessToken = "AccessToken"
        case passportNumber = "Passport"
        case driverLicense = "DriverLicense"
        case bankAccount = "BankAccount"
        case healthRecordID = "HealthRecord"
        case dateOfBirth = "DateOfBirth"
        case postalAddress = "Address"
        
        public var description: String { rawValue }
        
        public var redactionPlaceholder: String {
            "[REDACTED_\(rawValue.uppercased())]"
        }
        
        public var isHighRisk: Bool {
            switch self {
            case .socialSecurityNumber, .creditCard, .passportNumber,
                 .driverLicense, .bankAccount, .healthRecordID,
                 .apiKey, .accessToken, .password:
                return true
            default:
                return false
            }
        }
    }
    
    public struct Detection: Sendable, Identifiable {
        public let id = UUID()
        public let type: SensitiveDataType
        public let matchedText: String
        public let range: Range<String.Index>
        public let confidence: DetectionConfidence
        
        public enum DetectionConfidence: String, Sendable {
            case high = "High"
            case medium = "Medium"
            case low = "Low"
        }
    }
    
    // Internal helper to hold pre-compiled regex safely
    private struct PatternMatcher: Sendable {
        let type: SensitiveDataType
        let regex: NSRegularExpression
        let confidence: Detection.DetectionConfidence
        
        init(type: SensitiveDataType, pattern: String, confidence: Detection.DetectionConfidence) {
            self.type = type
            // Force try is acceptable here as these are static constants
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.confidence = confidence
        }
    }
    
    // Lazy static initialization for performance (compiled once).
    // PatternMatcher is Sendable, so this array is Sendable by composition.
    private static let matchers: [PatternMatcher] = [
        PatternMatcher(type: .socialSecurityNumber, pattern: #"\b(\d{3}-\d{2}-\d{4}|\d{9})\b"#, confidence: .high),
        PatternMatcher(type: .emailAddress, pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, confidence: .high),
        PatternMatcher(type: .phoneNumber, pattern: #"\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b"#, confidence: .high),
        PatternMatcher(type: .creditCard, pattern: #"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12})\b"#, confidence: .high),
        PatternMatcher(type: .ipAddress, pattern: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#, confidence: .medium),
        PatternMatcher(type: .macAddress, pattern: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})\b"#, confidence: .medium),
        PatternMatcher(type: .apiKey, pattern: #"(?i)(?:api[_-]?key|apikey)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{16,}['\"]?"#, confidence: .high),
        PatternMatcher(type: .apiKey, pattern: #"\bsk-[a-zA-Z0-9]{20,}\b"#, confidence: .high),
        PatternMatcher(type: .password, pattern: #"(?i)(?:password|passwd|pwd)\s*[:=]\s*['\"]?[^\s'\"]+['\"]?"#, confidence: .high),
        PatternMatcher(type: .accessToken, pattern: #"(?i)(?:token|secret|access[_-]?key)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{16,}['\"]?"#, confidence: .high),
        PatternMatcher(type: .passportNumber, pattern: #"\b[A-Z]{1}[0-9]{6,9}\b"#, confidence: .medium),
        PatternMatcher(type: .driverLicense, pattern: #"(?i)(?:DL|driver[^a-zA-Z])[\s:]*[A-Z0-9]{6,14}\b"#, confidence: .medium),
        PatternMatcher(type: .bankAccount, pattern: #"\b\d{8,17}\b"#, confidence: .low),
        PatternMatcher(type: .healthRecordID, pattern: #"(?i)(?:MRN|medical[^a-zA-Z]record|patient[^a-zA-Z]ID)[\s:]*[A-Z0-9]{6,10}\b"#, confidence: .medium),
        PatternMatcher(type: .dateOfBirth, pattern: #"(?i)(?:DOB|date[^a-zA-Z]of[^a-zA-Z]birth|born)[\s:]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})"#, confidence: .medium),
        PatternMatcher(type: .postalAddress, pattern: #"\d+\s+([A-Za-z]+\s*)+,(\s*[A-Za-z]+)+,\s*[A-Za-z]{2}\s*\d{5}(-\d{4})?"#, confidence: .medium)
    ]
    
    public struct Configuration: Sendable {
        public let typesToRedact: [SensitiveDataType]
        public let highRiskOnly: Bool
        public let preserveContext: Bool
        public let contextWindow: Int
        
        public init(
            typesToRedact: [SensitiveDataType] = [],
            highRiskOnly: Bool = false,
            preserveContext: Bool = false,
            contextWindow: Int = 10
        ) {
            self.typesToRedact = typesToRedact
            self.highRiskOnly = highRiskOnly
            self.preserveContext = preserveContext
            self.contextWindow = contextWindow
        }
        
        public static let `default` = Configuration()
        public static let highRiskOnly = Configuration(highRiskOnly: true)
        public static let strict = Configuration(typesToRedact: SensitiveDataType.allCases, preserveContext: false)
    }
    
    private let configuration: Configuration
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    /// Scans text and returns a list of detected PII ranges.
    public func detectSensitiveData(in text: String) -> [Detection] {
        var detections: [Detection] = []
        let range = NSRange(text.startIndex..., in: text)
        
        for matcher in Self.matchers {
            // Check filters
            if configuration.highRiskOnly && !matcher.type.isHighRisk { continue }
            if !configuration.typesToRedact.isEmpty && !configuration.typesToRedact.contains(matcher.type) { continue }
            
            let matches = matcher.regex.matches(in: text, options: [], range: range)
            
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let matchedText = String(text[range])
                    detections.append(Detection(
                        type: matcher.type,
                        matchedText: matchedText,
                        range: range,
                        confidence: matcher.confidence
                    ))
                }
            }
        }
        
        // Sort by position
        return detections.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
    
    /// Redacts sensitive PII from the text.
    public func redactSensitiveContent(_ text: String) -> String {
        let detections = detectSensitiveData(in: text)
        guard !detections.isEmpty else { return text }
        
        var result = text
        
        // FIX: Sort in reverse order (highest index first) to modify string safely.
        // This prevents replacements from invalidating indices of subsequent detections.
        let reverseDetections = detections.sorted { $0.range.lowerBound > $1.range.lowerBound }
        
        var lastLowerBound: String.Index?
        
        for detection in reverseDetections {
            // Simple overlap handling: Skip if this detection overlaps with a previously processed (higher index) one.
            if let last = lastLowerBound, detection.range.upperBound > last {
                continue
            }
            
            result.replaceSubrange(detection.range, with: detection.type.redactionPlaceholder)
            lastLowerBound = detection.range.lowerBound
        }
        
        return result
    }
    
    public func containsSensitiveData(_ text: String) -> Bool {
        !detectSensitiveData(in: text).isEmpty
    }
    
    public func containsHighRiskData(_ text: String) -> Bool {
        detectSensitiveData(in: text).contains { $0.type.isHighRisk }
    }
}

extension PrivacyEgressFilter {
    public static func redact(_ text: String) -> String {
        PrivacyEgressFilter().redactSensitiveContent(text)
    }
    
    public static func isSafeForEgress(_ text: String) -> Bool {
        let filter = PrivacyEgressFilter(configuration: .highRiskOnly)
        return !filter.containsHighRiskData(text)
    }
}

extension String {
    public var redactedForPrivacy: String {
        PrivacyEgressFilter.redact(self)
    }
    
    public var containsSensitiveData: Bool {
        PrivacyEgressFilter().containsSensitiveData(self)
    }
}
