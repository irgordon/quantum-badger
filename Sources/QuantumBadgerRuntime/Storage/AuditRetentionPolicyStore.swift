import Foundation
import Observation

@Observable
final class AuditRetentionPolicyStore {
    private enum Keys {
        static let retentionDays = "qb.audit.retentionDays"
    }

    private let defaults: UserDefaults
    private(set) var retentionDays: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Keys.retentionDays) as? Int
        let defaultValue = 30
        self.retentionDays = stored ?? defaultValue
    }

    func setRetentionDays(_ value: Int) {
        let clamped = max(7, min(value, 365))
        retentionDays = clamped
        defaults.set(clamped, forKey: Keys.retentionDays)
    }
}
