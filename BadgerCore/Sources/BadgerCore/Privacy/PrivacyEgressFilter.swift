import Foundation

// MARK: - Privacy Egress Filter

public struct PrivacyEgressFilter: Sendable {
    
    public typealias SensitiveDataType = PrivacyRegistry.Pattern.SensitiveDataType
    
    public struct Detection: Sendable, Identifiable {
        public let id = UUID()
        public let type: SensitiveDataType
        public let matchedText: String
        public let range: Range<String.Index>
        public let confidence: DetectionConfidence
        
        public typealias DetectionConfidence = PrivacyRegistry.Pattern.Confidence
    }
    
    // Internal helper to hold pre-compiled regex safely
    private struct PatternMatcher: Sendable {
        let type: SensitiveDataType
        let regex: NSRegularExpression
        let confidence: Detection.DetectionConfidence
        
        init(type: SensitiveDataType, pattern: String, confidence: Detection.DetectionConfidence) {
            self.type = type
            // Force try is acceptable here as these are static constants from PrivacyRegistry
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.confidence = confidence
        }
    }
    
    // Lazy static initialization for performance (compiled once).
    // PatternMatcher is Sendable, so this array is Sendable by composition.
    private static let matchers: [PatternMatcher] = PrivacyRegistry.piiPatterns.compactMap { pattern in
        guard let type = pattern.type else { return nil }
        return PatternMatcher(type: type, pattern: pattern.regex, confidence: pattern.confidence)
    }
    
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
        
        // Deduplicate overlapping detections of the same type
        // Keep the longest match when there are overlaps
        detections = deduplicateOverlappingDetections(detections)
        
        // Sort by position
        return detections.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
    
    /// Redacts sensitive PII from the text.
    public func redactSensitiveContent(_ text: String) -> String {
        let detections = detectSensitiveData(in: text)
        guard !detections.isEmpty else { return text }
        
        var result = text
        
        // Sort in reverse order (highest index first) to modify string safely.
        // This prevents replacements from invalidating indices of subsequent detections.
        // Since detectSensitiveData already returns sorted detections, we simply reverse.
        let reverseDetections = detections.reversed()
        
        var lastProcessedLowerBound: String.Index?
        
        for detection in reverseDetections {
            // Simple overlap handling: Skip if this detection overlaps with a previously processed (higher index) one.
            if let last = lastProcessedLowerBound, detection.range.upperBound > last {
                continue
            }
            
            result.replaceSubrange(detection.range, with: detection.type.redactionPlaceholder)
            lastProcessedLowerBound = detection.range.lowerBound
        }
        
        return result
    }
    
    public func containsSensitiveData(_ text: String) -> Bool {
        !detectSensitiveData(in: text).isEmpty
    }
    
    public func containsHighRiskData(_ text: String) -> Bool {
        detectSensitiveData(in: text).contains { $0.type.isHighRisk }
    }
    
    /// Deduplicate overlapping detections, preferring high-confidence matches over low-confidence ones.
    /// When detections overlap, we keep the one with higher confidence (or longer match if same confidence).
    internal func deduplicateOverlappingDetections(_ detections: [Detection]) -> [Detection] {
        // Sort all detections by:
        // 1. Confidence (high > medium > low)
        // 2. Match length (longer is better)
        // 3. Range start position (earlier is better)
        let sorted = detections.sorted(by: { (a, b) in
            // 1. Confidence priority
            let aPriority = confidencePriority(a.confidence)
            let bPriority = confidencePriority(b.confidence)
            if aPriority != bPriority {
                return aPriority > bPriority
            }
            // 2. Match length
            if a.matchedText.count != b.matchedText.count {
                return a.matchedText.count > b.matchedText.count
            }
            // 3. Start position
            return a.range.lowerBound < b.range.lowerBound
        })
        
        var filtered: [Detection] = []
        for detection in sorted {
            // Check if this detection overlaps with any already filtered detection
            let overlaps = filtered.contains { existing in
                detection.range.overlaps(existing.range)
            }
            if !overlaps {
                filtered.append(detection)
            }
        }
        
        return filtered
    }
    
    private func confidencePriority(_ confidence: Detection.DetectionConfidence) -> Int {
        switch confidence {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
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
