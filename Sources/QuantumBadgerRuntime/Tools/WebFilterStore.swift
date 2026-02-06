import Foundation
import Observation

@MainActor
@Observable
final class WebFilterStore {
    private let storageURL: URL
    private(set) var filters: [WebFilterRule]
    private(set) var strictModeEnabled: Bool
    private(set) var allowedDomains: [String]
    private var regexCache: [UUID: NSRegularExpression] = [:]
    private var compiledCache: [CompiledWebFilter] = []
    private var compiledDirty: Bool = true
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.webFilterURL) {
        self.storageURL = storageURL
        let defaults = WebFilterSnapshot(filters: [], strictModeEnabled: false, allowedDomains: [])
        self.filters = defaults.filters
        self.strictModeEnabled = defaults.strictModeEnabled
        self.allowedDomains = ["duckduckgo.com", "github.com"]
        loadAsync(defaults: defaults)
    }

    func addFilter(pattern: String, type: WebFilterType) {
        didMutate = true
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filters.append(WebFilterRule(id: UUID(), pattern: trimmed, type: type))
        compiledDirty = true
        persist()
    }

    func removeFilter(_ filter: WebFilterRule) {
        didMutate = true
        filters.removeAll { $0.id == filter.id }
        regexCache.removeValue(forKey: filter.id)
        compiledDirty = true
        persist()
    }

    func activeFilters() -> [WebFilterRule] {
        filters
    }

    func compiledFilters() -> [CompiledWebFilter] {
        if !compiledDirty {
            return compiledCache
        }
        var compiled: [CompiledWebFilter] = []
        compiled.reserveCapacity(filters.count)
        for rule in filters {
            switch rule.type {
            case .word:
                compiled.append(CompiledWebFilter(rule: rule, regex: nil))
            case .regex:
                if let cached = regexCache[rule.id] {
                    compiled.append(CompiledWebFilter(rule: rule, regex: cached))
                    continue
                }
                if let compiledRegex = try? NSRegularExpression(pattern: rule.pattern) {
                    regexCache[rule.id] = compiledRegex
                    compiled.append(CompiledWebFilter(rule: rule, regex: compiledRegex))
                } else {
                    compiled.append(CompiledWebFilter(rule: rule, regex: nil))
                }
            }
        }
        compiledCache = compiled
        compiledDirty = false
        return compiled
    }

    func setStrictMode(_ enabled: Bool) {
        didMutate = true
        strictModeEnabled = enabled
        persist()
    }

    func addAllowedDomain(_ domain: String) {
        didMutate = true
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        if !allowedDomains.contains(trimmed) {
            allowedDomains.append(trimmed)
            persist()
        }
    }

    func removeAllowedDomain(_ domain: String) {
        didMutate = true
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

    private func loadAsync(defaults: WebFilterSnapshot) {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = JSONStore.load(WebFilterSnapshot.self, from: storageURL, defaultValue: defaults)
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.filters = snapshot.filters
                self.strictModeEnabled = snapshot.strictModeEnabled
                if snapshot.allowedDomains.isEmpty {
                    self.allowedDomains = ["duckduckgo.com", "github.com"]
                    self.persist()
                } else {
                    self.allowedDomains = snapshot.allowedDomains
                }
                self.compiledDirty = true
            }
        }
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

struct CompiledWebFilter {
    let rule: WebFilterRule
    let regex: NSRegularExpression?
}

private struct WebFilterSnapshot: Codable {
    var filters: [WebFilterRule]
    var strictModeEnabled: Bool
    var allowedDomains: [String]
}
