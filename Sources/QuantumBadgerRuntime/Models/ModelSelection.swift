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

    init(storageURL: URL = AppPaths.modelSelectionURL) {
        self.storageURL = storageURL
        let defaults = SelectionSnapshot(
            activeModelId: nil,
            offlineFallbackModelId: nil,
            hideCloudModelsWhenOffline: true,
            didDismissOfflineDownloadCTA: false
        )
        let snapshot = JSONStore.load(SelectionSnapshot.self, from: storageURL, defaultValue: defaults)
        self.activeModelId = snapshot.activeModelId
        self.offlineFallbackModelId = snapshot.offlineFallbackModelId
        self.hideCloudModelsWhenOffline = snapshot.hideCloudModelsWhenOffline
        self.didDismissOfflineDownloadCTA = snapshot.didDismissOfflineDownloadCTA
    }

    func setActiveModel(_ id: UUID?) {
        activeModelId = id
        persist()
    }

    func setOfflineFallbackModel(_ id: UUID?) {
        offlineFallbackModelId = id
        persist()
    }

    func setHideCloudModelsWhenOffline(_ value: Bool) {
        hideCloudModelsWhenOffline = value
        persist()
    }

    func setDidDismissOfflineDownloadCTA(_ value: Bool) {
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

    private struct SelectionSnapshot: Codable {
        var activeModelId: UUID?
        var offlineFallbackModelId: UUID?
        var hideCloudModelsWhenOffline: Bool
        var didDismissOfflineDownloadCTA: Bool
    }
}
