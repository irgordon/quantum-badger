import Foundation
import Observation

@MainActor
@Observable
final class ToolLimitsStore {
    private(set) var overrides: [String: ToolExecutionLimits]
    private let storageURL: URL
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.toolLimitsURL) {
        self.storageURL = storageURL
        self.overrides = [:]
        loadAsync()
    }

    func limits(for toolName: String, fallback: ToolExecutionLimits) -> ToolExecutionLimits {
        overrides[toolName] ?? fallback
    }

    func setMaxQueryTokens(for toolName: String, value: Int) {
        let clamped = max(64, min(value, 4096))
        var limits = overrides[toolName] ?? ToolCatalog.contract(for: toolName)?.limits ?? .default
        limits.maxQueryTokens = clamped
        overrides[toolName] = limits
        didMutate = true
        persist()
    }

    var dbQueryMaxTokens: Int {
        get {
            limits(
                for: "db.query",
                fallback: ToolCatalog.contract(for: "db.query")?.limits ?? .default
            ).maxQueryTokens
        }
        set {
            setMaxQueryTokens(for: "db.query", value: newValue)
        }
    }

    private func persist() {
        do {
            try JSONStore.save(overrides, to: storageURL)
        } catch {
            AppLogger.storage.error("Failed to persist tool limits: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func loadAsync() {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = JSONStore.load([String: ToolExecutionLimits].self, from: storageURL, defaultValue: [:])
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.overrides = snapshot
            }
        }
    }
}
