import Foundation
import Observation

struct ResourcePolicy: Codable {
    var minAvailableMemoryGB: Int

    static let `default` = ResourcePolicy(minAvailableMemoryGB: 8)
}

enum MemoryPressureLevel: String, Codable, CaseIterable, Identifiable {
    case normal
    case warning
    case critical

    var id: String { rawValue }
}

@MainActor
@Observable
final class ResourcePolicyStore {
    private(set) var policy: ResourcePolicy
    private(set) var memoryPressure: MemoryPressureLevel = .normal
    private let storageURL: URL
    private var pressureSource: DispatchSourceMemoryPressure?
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.resourcePolicyURL) {
        self.storageURL = storageURL
        self.policy = .default
        startMemoryPressureMonitor()
        loadAsync()
    }

    func setMinAvailableMemoryGB(_ value: Int) {
        didMutate = true
        policy.minAvailableMemoryGB = max(2, min(64, value))
        persist()
    }

    private func persist() {
        try? JSONStore.save(policy, to: storageURL)
    }

    private func loadAsync() {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = JSONStore.load(ResourcePolicy.self, from: storageURL, defaultValue: .default)
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.policy = snapshot
            }
        }
    }

    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            let newLevel: MemoryPressureLevel
            if flags.contains(.critical) {
                newLevel = .critical
            } else if flags.contains(.warning) {
                newLevel = .warning
            } else {
                newLevel = .normal
            }
            Task { @MainActor in
                self.memoryPressure = newLevel
            }
        }
        source.resume()
        pressureSource = source
    }
}
