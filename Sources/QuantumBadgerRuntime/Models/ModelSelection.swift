import Foundation
import Observation

@MainActor
@Observable
final class ModelSelectionStore {
    private(set) var activeModelId: UUID?
    private(set) var offlineFallbackModelId: UUID?
    private(set) var hideCloudModelsWhenOffline: Bool
    private(set) var didDismissOfflineDownloadCTA: Bool

    private let storageURL: URL
    private var didMutate: Bool = false

    init(storageURL: URL = AppPaths.modelSelectionURL) {
        self.storageURL = storageURL
        let defaults = SelectionSnapshot(
            activeModelId: nil,
            offlineFallbackModelId: nil,
            hideCloudModelsWhenOffline: true,
            didDismissOfflineDownloadCTA: false
        )
        self.activeModelId = defaults.activeModelId
        self.offlineFallbackModelId = defaults.offlineFallbackModelId
        self.hideCloudModelsWhenOffline = defaults.hideCloudModelsWhenOffline
        self.didDismissOfflineDownloadCTA = defaults.didDismissOfflineDownloadCTA
        loadAsync(defaults: defaults)
    }

    func setActiveModel(_ id: UUID?) {
        didMutate = true
        activeModelId = id
        persist()
    }

    func setOfflineFallbackModel(_ id: UUID?) {
        didMutate = true
        offlineFallbackModelId = id
        persist()
    }

    func setHideCloudModelsWhenOffline(_ value: Bool) {
        didMutate = true
        hideCloudModelsWhenOffline = value
        persist()
    }

    func setDidDismissOfflineDownloadCTA(_ value: Bool) {
        didMutate = true
        didDismissOfflineDownloadCTA = value
        persist()
    }

    @discardableResult
    func resolveActiveModel(from registry: ModelRegistry) -> UUID? {
        guard let activeModelId else { return nil }
        let exists = registry.models.contains { $0.id == activeModelId }
        if !exists {
            self.activeModelId = nil
            persist()
            return nil
        }
        return activeModelId
    }

    func effectiveModelId(
        isReachable: Bool,
        registry: ModelRegistry
    ) -> UUID? {
        guard let activeModelId = resolveActiveModel(from: registry) else { return nil }
        if !isReachable, let model = registry.models.first(where: { $0.id == activeModelId }), model.isCloud {
            return offlineFallbackModelId
        }
        return activeModelId
    }

    private func persist() {
        let snapshot = SelectionSnapshot(
            activeModelId: activeModelId,
            offlineFallbackModelId: offlineFallbackModelId,
            hideCloudModelsWhenOffline: hideCloudModelsWhenOffline,
            didDismissOfflineDownloadCTA: didDismissOfflineDownloadCTA
        )
        try? JSONStore.save(snapshot, to: storageURL)
    }

    private func loadAsync(defaults: SelectionSnapshot) {
        let storageURL = storageURL
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = JSONStore.load(SelectionSnapshot.self, from: storageURL, defaultValue: defaults)
            await MainActor.run {
                guard let self, !self.didMutate else { return }
                self.activeModelId = snapshot.activeModelId
                self.offlineFallbackModelId = snapshot.offlineFallbackModelId
                self.hideCloudModelsWhenOffline = snapshot.hideCloudModelsWhenOffline
                self.didDismissOfflineDownloadCTA = snapshot.didDismissOfflineDownloadCTA
            }
        }
    }

    private struct SelectionSnapshot: Codable {
        var activeModelId: UUID?
        var offlineFallbackModelId: UUID?
        var hideCloudModelsWhenOffline: Bool
        var didDismissOfflineDownloadCTA: Bool
    }
}
