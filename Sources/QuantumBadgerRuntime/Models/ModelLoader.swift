import Foundation

protocol ModelRuntimeFactory {
    func makeLocalRuntime(for model: LocalModel) -> ModelRuntime
    func makeCloudRuntime(for model: LocalModel) -> ModelRuntime
}

struct DefaultModelRuntimeFactory: ModelRuntimeFactory {
    private let cloudKeyProvider: CloudAPIKeyProvider?

    init(cloudKeyProvider: CloudAPIKeyProvider? = nil) {
        self.cloudKeyProvider = cloudKeyProvider
    }

    func makeLocalRuntime(for model: LocalModel) -> ModelRuntime {
        switch model.engine {
        case .gguf:
            return LocalGGUFRuntimeAdapter(model: model)
        default:
            return LocalStubAdapter()
        }
    }

    func makeCloudRuntime(for model: LocalModel) -> ModelRuntime {
        let apiKey = cloudKeyProvider?.apiKey(for: model.id)
        return CloudRuntimeAdapter(model: model, apiKey: apiKey)
    }
}

@MainActor
final class ModelLoader {
    private let modelRegistry: ModelRegistry
    private let modelSelection: ModelSelectionStore
    private let resourcePolicy: ResourcePolicyStore
    private let factory: ModelRuntimeFactory
    private var runtimeCache: [UUID: ModelRuntime] = [:]
    private var usageOrder: [UUID] = []
    private let maxCachedRuntimes: Int

    init(
        modelRegistry: ModelRegistry,
        modelSelection: ModelSelectionStore,
        resourcePolicy: ResourcePolicyStore,
        factory: ModelRuntimeFactory = DefaultModelRuntimeFactory(),
        maxCachedRuntimes: Int = 2
    ) {
        self.modelRegistry = modelRegistry
        self.modelSelection = modelSelection
        self.resourcePolicy = resourcePolicy
        self.factory = factory
        self.maxCachedRuntimes = max(1, maxCachedRuntimes)
    }

    func loadActiveRuntime() -> ModelRuntime {
        guard let id = modelSelection.activeModelId,
              let model = modelRegistry.models.first(where: { $0.id == id }) else {
            return LocalStubAdapter()
        }
        if resourcePolicy.memoryPressure != .normal {
            if let cached = runtimeCache[id] {
                return cached
            }
            SystemEventBus.shared.post(.modelLoadBlocked(level: resourcePolicy.memoryPressure))
            return LocalStubAdapter()
        }
        if let cached = runtimeCache[id] {
            touch(id)
            return cached
        }
        let runtime = model.isCloud ? factory.makeCloudRuntime(for: model) : factory.makeLocalRuntime(for: model)
        modelRegistry.lockModel(id)
        runtimeCache[id] = runtime
        touch(id)
        evictIfNeeded()
        return runtime
    }

    func warmUpActiveRuntime() async {
        let runtime = loadActiveRuntime()
        if let warmable = runtime as? WarmableModelRuntime {
            await warmable.warmUp()
        }
    }

    func unloadModel(_ id: UUID) {
        runtimeCache[id] = nil
        usageOrder.removeAll { $0 == id }
        modelRegistry.unlockModel(id)
        if modelSelection.activeModelId == id {
            modelSelection.setActiveModel(nil)
        }
    }

    private func touch(_ id: UUID) {
        usageOrder.removeAll { $0 == id }
        usageOrder.append(id)
    }

    private func evictIfNeeded() {
        while usageOrder.count > maxCachedRuntimes {
            let evictId = usageOrder.removeFirst()
            modelRegistry.unlockModel(evictId)
            runtimeCache[evictId] = nil
        }
    }
}
