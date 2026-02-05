import Foundation
import Observation

@Observable
final class UntrustedParsingPolicyStore {
    private enum Keys {
        static let retryEnabled = "qb.untrustedParsing.retryEnabled"
        static let maxRetries = "qb.untrustedParsing.maxRetries"
    }

    private let defaults: UserDefaults

    private(set) var retryEnabled: Bool
    private(set) var maxRetries: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRetry = defaults.object(forKey: Keys.retryEnabled) as? Bool
        let storedMaxRetries = defaults.object(forKey: Keys.maxRetries) as? Int
        self.retryEnabled = storedRetry ?? true
        self.maxRetries = storedMaxRetries ?? 1
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
}
