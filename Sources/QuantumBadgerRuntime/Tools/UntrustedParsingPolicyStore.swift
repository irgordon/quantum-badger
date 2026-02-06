import Foundation
import Observation

@Observable
final class UntrustedParsingPolicyStore {
    private enum Keys {
        static let retryEnabled = "qb.untrustedParsing.retryEnabled"
        static let maxRetries = "qb.untrustedParsing.maxRetries"
        static let allowedTags = "qb.untrustedParsing.allowedTags"
        static let preset = "qb.untrustedParsing.preset"
        static let maxParseSeconds = "qb.untrustedParsing.maxParseSeconds"
        static let maxAnchorScans = "qb.untrustedParsing.maxAnchorScans"
    }

    private let defaults: UserDefaults

    private(set) var retryEnabled: Bool
    private(set) var maxRetries: Int
    private(set) var allowedTags: [String]
    private(set) var preset: UntrustedParsingPreset
    private(set) var maxParseSeconds: Double
    private(set) var maxAnchorScans: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRetry = defaults.object(forKey: Keys.retryEnabled) as? Bool
        let storedMaxRetries = defaults.object(forKey: Keys.maxRetries) as? Int
        let storedTags = defaults.stringArray(forKey: Keys.allowedTags)
        let storedPreset = defaults.string(forKey: Keys.preset)
        let storedMaxParseSeconds = defaults.object(forKey: Keys.maxParseSeconds) as? Double
        let storedMaxAnchorScans = defaults.object(forKey: Keys.maxAnchorScans) as? Int
        self.retryEnabled = storedRetry ?? true
        self.maxRetries = storedMaxRetries ?? 1
        self.maxParseSeconds = storedMaxParseSeconds ?? 0.6
        self.maxAnchorScans = storedMaxAnchorScans ?? 600
        let normalizedStoredTags = normalizeTags(storedTags ?? [])
        if let storedPreset, let preset = UntrustedParsingPreset(rawValue: storedPreset) {
            self.preset = preset
            if preset == .custom, !normalizedStoredTags.isEmpty {
                self.allowedTags = normalizedStoredTags
            } else {
                self.allowedTags = normalizeTags(preset.tags)
            }
        } else if !normalizedStoredTags.isEmpty {
            let detected = Self.presetForTags(normalizedStoredTags)
            self.preset = detected
            self.allowedTags = normalizedStoredTags
        } else {
            self.preset = .strict
            self.allowedTags = normalizeTags(Self.strictTags)
        }
    }

    func setRetryEnabled(_ enabled: Bool) {
        retryEnabled = enabled
        defaults.set(enabled, forKey: Keys.retryEnabled)
    }

    func setMaxRetries(_ value: Int) {
        let clamped = max(0, min(value, 3))
        maxRetries = clamped
        defaults.set(clamped, forKey: Keys.maxRetries)
    }

    func setMaxParseSeconds(_ value: Double) {
        let clamped = max(0.1, min(value, 2.0))
        maxParseSeconds = clamped
        defaults.set(clamped, forKey: Keys.maxParseSeconds)
    }

    func setMaxAnchorScans(_ value: Int) {
        let clamped = max(50, min(value, 5000))
        maxAnchorScans = clamped
        defaults.set(clamped, forKey: Keys.maxAnchorScans)
    }

    func setAllowedTags(_ tags: [String]) {
        let normalized = normalizeTags(tags)
        allowedTags = normalized
        preset = .custom
        defaults.set(normalized, forKey: Keys.allowedTags)
        defaults.set(preset.rawValue, forKey: Keys.preset)
    }

    func resetAllowedTagsToDefault() {
        setPreset(.strict)
    }

    func setPreset(_ preset: UntrustedParsingPreset) {
        self.preset = preset
        if preset == .custom {
            allowedTags = normalizeTags(allowedTags)
        } else {
            allowedTags = normalizeTags(preset.tags)
        }
        defaults.set(allowedTags, forKey: Keys.allowedTags)
        defaults.set(preset.rawValue, forKey: Keys.preset)
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
        let unique = Array(Set(cleaned))
        return unique.sorted()
    }

    static let strictTags: [String] = [
        "p", "br", "ul", "ol", "li",
        "strong", "em",
        "code", "pre", "blockquote",
        "h1", "h2", "h3", "h4", "h5", "h6"
    ]

    static let balancedTags: [String] = [
        "a", "p", "div", "span", "section", "article",
        "ul", "ol", "li", "br", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "strong", "em", "b", "i", "u",
        "code", "pre", "blockquote",
        "table", "thead", "tbody", "tr", "th", "td"
    ]

    static let permissiveTags: [String] = [
        "a", "p", "div", "span", "section", "article", "nav", "header", "footer", "main", "aside",
        "ul", "ol", "li", "br", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "strong", "em", "b", "i", "u", "small", "mark", "sup", "sub",
        "code", "pre", "blockquote", "kbd", "samp",
        "table", "thead", "tbody", "tr", "th", "td"
    ]

    private static func presetForTags(_ tags: [String]) -> UntrustedParsingPreset {
        let set = Set(tags)
        if set == Set(strictTags) {
            return .strict
        }
        if set == Set(balancedTags) {
            return .balanced
        }
        if set == Set(permissiveTags) {
            return .permissive
        }
        return .custom
    }
}

enum UntrustedParsingPreset: String, CaseIterable, Identifiable, Codable {
    case strict
    case balanced
    case permissive
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return "Strict (Recommended)"
        case .balanced: return "Balanced"
        case .permissive: return "Minimal filtering (Higher Risk)"
        case .custom: return "Custom"
        }
    }

    var descriptionText: String {
        switch self {
        case .strict:
            return "Keeps only essential text elements for the safest browsing."
        case .balanced:
            return "Allows common layout tags while still blocking risky content."
        case .permissive:
            return "Allows much more content. This can surface hidden or misleading text."
        case .custom:
            return "You control the exact tag allowlist."
        }
    }

    var tags: [String] {
        switch self {
        case .strict:
            return UntrustedParsingPolicyStore.strictTags
        case .balanced:
            return UntrustedParsingPolicyStore.balancedTags
        case .permissive:
            return UntrustedParsingPolicyStore.permissiveTags
        case .custom:
            return []
        }
    }
}
