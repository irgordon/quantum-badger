import Foundation
import Observation

@Observable
final class IdentityPolicyStore {
    private enum Keys {
        static let hashThresholdBytes = "qb.identity.hashThresholdBytes"
    }

    private let defaults: UserDefaults
    private(set) var hashThresholdBytes: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Keys.hashThresholdBytes) as? Int
        let defaultValue = 128 * 1024
        self.hashThresholdBytes = stored ?? defaultValue
        InboundIdentityValidator.shared.updateHashThresholdBytes(hashThresholdBytes)
    }

    func setHashThresholdBytes(_ value: Int) {
        let clamped = max(8 * 1024, min(value, 5 * 1024 * 1024))
        hashThresholdBytes = clamped
        defaults.set(clamped, forKey: Keys.hashThresholdBytes)
        InboundIdentityValidator.shared.updateHashThresholdBytes(clamped)
    }
}
