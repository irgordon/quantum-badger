import Foundation
import Observation

@MainActor
@Observable
final class WebFilterStore {
    private let storageURL: URL
    private(set) var filters: [WebFilterRule]
    private(set) var strictModeEnabled: Bool
    private(set) var allowedDomains: [String]

    init(storageURL: URL = AppPaths.webFilterURL) {
        self.storageURL = storageURL
        let defaults = WebFilterSnapshot(filters: [], strictModeEnabled: false, allowedDomains: [])
        let snapshot = JSONStore.load(WebFilterSnapshot.self, from: storageURL, defaultValue: defaults)
        self.filters = snapshot.filters
        self.strictModeEnabled = snapshot.strictModeEnabled
        if snapshot.allowedDomains.isEmpty {
            self.allowedDomains = ["duckduckgo.com", "github.com"]
            persist()
        } else {
            self.allowedDomains = snapshot.allowedDomains
        }
    }

    func addFilter(pattern: String, type: WebFilterType) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filters.append(WebFilterRule(id: UUID(), pattern: trimmed, type: type))
        persist()
    }

    func removeFilter(_ filter: WebFilterRule) {
        filters.removeAll { $0.id == filter.id }
        persist()
    }

    func activeFilters() -> [WebFilterRule] {
        filters
    }

    func setStrictMode(_ enabled: Bool) {
        strictModeEnabled = enabled
        persist()
    }

    func addAllowedDomain(_ domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        if !allowedDomains.contains(trimmed) {
            allowedDomains.append(trimmed)
            persist()
        }
    }

    func removeAllowedDomain(_ domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        allowedDomains.removeAll { $0 == trimmed }
        persist()
    }

    func isDomainAllowed(_ host: String?) -> Bool {
        guard strictModeEnabled else { return true }
        guard let host = host?.lowercased() else { return false }
        for rule in allowedDomains {
            if rule.hasPrefix("*.") {
                let suffix = String(rule.dropFirst(1))
                if host.hasSuffix(suffix) { return true }
            } else if rule.hasPrefix(".") {
                if host.hasSuffix(rule) { return true }
            } else if host == rule {
                return true
            }
        }
        return false
    }

    private func persist() {
        let snapshot = WebFilterSnapshot(
            filters: filters,
            strictModeEnabled: strictModeEnabled,
            allowedDomains: allowedDomains
        )
        try? JSONStore.save(snapshot, to: storageURL)
    }
}

enum WebFilterType: String, Codable, CaseIterable, Identifiable {
    case word
    case regex

    var id: String { rawValue }
}

struct WebFilterRule: Identifiable, Codable, Hashable {
    let id: UUID
    var pattern: String
    var type: WebFilterType
}

private struct WebFilterSnapshot: Codable {
    var filters: [WebFilterRule]
    var strictModeEnabled: Bool
    var allowedDomains: [String]
}
