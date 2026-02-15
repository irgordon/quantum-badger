import Foundation
import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Models View Model

@MainActor
@Observable
public final class ModelsViewModel {
    
    // MARK: - Download State
    
    public enum DownloadState: Equatable {
        case notStarted
        case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
        case verifying
        case completed
        case failed(error: String)
        
        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
        
        var displayProgress: Double {
            switch self {
            case .notStarted: return 0
            case .downloading(let progress, _, _): return progress
            case .verifying: return 0.95
            case .completed: return 1
            case .failed: return 0
            }
        }
        
        var statusText: String {
            switch self {
            case .notStarted: return "Not Downloaded"
            case .downloading(let progress, _, _):
                return String(format: "Downloading... %.0f%%", progress * 100)
            case .verifying: return "Verifying..."
            case .completed: return "Ready"
            case .failed(let error): return "Failed: \(error)"
            }
        }
    }
    
    // MARK: - Model Info
    
    public struct ModelDownloadInfo: Identifiable, Equatable {
        public let id = UUID()
        public let modelClass: ModelClass
        public let name: String
        public let description: String
        public let sizeGB: Double
        public let huggingFaceRepo: String
        public var downloadState: DownloadState = .notStarted
        public var isDownloaded: Bool = false
        public var localPath: URL?
        
        public var formattedSize: String {
            String(format: "%.1f GB", sizeGB)
        }
    }
    
    // MARK: - Properties
    
    public var availableModels: [ModelDownloadInfo] = []
    public var shadowRouterSettings = ShadowRouterSettings()
    
    private var downloadTasks: [ModelClass: Task<Void, Never>] = [:]
    
    // MARK: - Settings
    
    public struct ShadowRouterSettings: Equatable {
        public var forceSafeMode: Bool = false
        public var ramHeadroomLimitGB: Double = 4.0
        public var preferLocalInference: Bool = true
        public var enableIntentAnalysis: Bool = true
        public var thermalThrottlingEnabled: Bool = true
        public var minimumVRAMForLocalGB: Double = 8.0
        
        public var ramHeadroomLimitBytes: UInt64 {
            UInt64(ramHeadroomLimitGB * 1024 * 1024 * 1024)
        }
        
        public var minimumVRAMForLocalBytes: UInt64 {
            UInt64(minimumVRAMForLocalGB * 1024 * 1024 * 1024)
        }
    }
    
    // MARK: - Initialization
    
    public init() {
        setupAvailableModels()
        loadSettings()
    }
    
    private func setupAvailableModels() {
        availableModels = [
            ModelDownloadInfo(
                modelClass: .phi4,
                name: "Phi-4",
                description: "Microsoft's Phi-4 14B model - Excellent reasoning and coding capabilities",
                sizeGB: 8.5,
                huggingFaceRepo: "mlx-community/Phi-4"
            ),
            ModelDownloadInfo(
                modelClass: .qwen25,
                name: "Qwen 2.5",
                description: "Alibaba's Qwen 2.5 7B model - Strong multilingual support",
                sizeGB: 4.5,
                huggingFaceRepo: "mlx-community/Qwen2.5-7B-Instruct"
            ),
            ModelDownloadInfo(
                modelClass: .llama31,
                name: "Llama 3.1",
                description: "Meta's Llama 3.1 8B model - Balanced performance",
                sizeGB: 5.0,
                huggingFaceRepo: "mlx-community/Llama-3.1-8B-Instruct"
            ),
            ModelDownloadInfo(
                modelClass: .gemma2,
                name: "Gemma 2",
                description: "Google's Gemma 2 9B model - Efficient and capable",
                sizeGB: 6.0,
                huggingFaceRepo: "mlx-community/gemma-2-9b-it"
            )
        ]
        
        // Check which models are already downloaded
        Task {
            await checkDownloadedModels()
        }
    }
    
    // MARK: - Model Management
    
    public func downloadModel(_ modelInfo: ModelDownloadInfo) async {
        guard !modelInfo.isDownloaded else { return }
        
        updateDownloadState(for: modelInfo.modelClass, state: .downloading(progress: 0, bytesDownloaded: 0, totalBytes: 0))
        
        // Simulate download progress
        let totalBytes = Int64(modelInfo.sizeGB * 1024 * 1024 * 1024)
        
        downloadTasks[modelInfo.modelClass] = Task {
            for progress in stride(from: 0.0, to: 1.0, by: 0.05) {
                guard !Task.isCancelled else { return }
                
                let bytesDownloaded = Int64(Double(totalBytes) * progress)
                let state: DownloadState = .downloading(
                    progress: progress,
                    bytesDownloaded: bytesDownloaded,
                    totalBytes: totalBytes
                )
                
                await MainActor.run {
                    updateDownloadState(for: modelInfo.modelClass, state: state)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms per step
            }
            
            // Verify
            await MainActor.run {
                updateDownloadState(for: modelInfo.modelClass, state: .verifying)
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms verification
            
            // Complete
            await MainActor.run {
                markModelAsDownloaded(modelInfo.modelClass)
                updateDownloadState(for: modelInfo.modelClass, state: .completed)
            }
        }
    }
    
    public func cancelDownload(for modelClass: ModelClass) {
        downloadTasks[modelClass]?.cancel()
        downloadTasks.removeValue(forKey: modelClass)
        updateDownloadState(for: modelClass, state: .notStarted)
    }
    
    public func deleteModel(_ modelClass: ModelClass) {
        // In real implementation, delete from disk
        if let index = availableModels.firstIndex(where: { $0.modelClass == modelClass }) {
            availableModels[index].isDownloaded = false
            availableModels[index].localPath = nil
            availableModels[index].downloadState = .notStarted
        }
    }
    
    private func checkDownloadedModels() async {
        // Check which models exist in the models directory
        // For now, all marked as not downloaded
    }
    
    private func markModelAsDownloaded(_ modelClass: ModelClass) {
        if let index = availableModels.firstIndex(where: { $0.modelClass == modelClass }) {
            availableModels[index].isDownloaded = true
            availableModels[index].localPath = modelsDirectory().appendingPathComponent(modelClass.rawValue)
        }
    }
    
    private func updateDownloadState(for modelClass: ModelClass, state: DownloadState) {
        if let index = availableModels.firstIndex(where: { $0.modelClass == modelClass }) {
            availableModels[index].downloadState = state
        }
    }
    
    private func modelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("QuantumBadger/Models")
    }
    
    // MARK: - Settings Management
    
    public func saveSettings() {
        // Persist to UserDefaults or secure storage
        let defaults = UserDefaults.standard
        defaults.set(shadowRouterSettings.forceSafeMode, forKey: "forceSafeMode")
        defaults.set(shadowRouterSettings.ramHeadroomLimitGB, forKey: "ramHeadroomLimitGB")
        defaults.set(shadowRouterSettings.preferLocalInference, forKey: "preferLocalInference")
        defaults.set(shadowRouterSettings.enableIntentAnalysis, forKey: "enableIntentAnalysis")
        defaults.set(shadowRouterSettings.thermalThrottlingEnabled, forKey: "thermalThrottlingEnabled")
        defaults.set(shadowRouterSettings.minimumVRAMForLocalGB, forKey: "minimumVRAMForLocalGB")
    }
    
    public func loadSettings() {
        let defaults = UserDefaults.standard
        shadowRouterSettings.forceSafeMode = defaults.bool(forKey: "forceSafeMode")
        shadowRouterSettings.ramHeadroomLimitGB = defaults.double(forKey: "ramHeadroomLimitGB")
        shadowRouterSettings.ramHeadroomLimitGB = shadowRouterSettings.ramHeadroomLimitGB == 0 ? 4.0 : shadowRouterSettings.ramHeadroomLimitGB
        shadowRouterSettings.preferLocalInference = defaults.object(forKey: "preferLocalInference") as? Bool ?? true
        shadowRouterSettings.enableIntentAnalysis = defaults.object(forKey: "enableIntentAnalysis") as? Bool ?? true
        shadowRouterSettings.thermalThrottlingEnabled = defaults.object(forKey: "thermalThrottlingEnabled") as? Bool ?? true
        shadowRouterSettings.minimumVRAMForLocalGB = defaults.double(forKey: "minimumVRAMForLocalGB")
        shadowRouterSettings.minimumVRAMForLocalGB = shadowRouterSettings.minimumVRAMForLocalGB == 0 ? 8.0 : shadowRouterSettings.minimumVRAMForLocalGB
    }
    
    public func resetToDefaults() {
        shadowRouterSettings = ShadowRouterSettings()
        saveSettings()
    }
    
    // MARK: - Helper Methods
    
    public var totalDownloadedSize: Double {
        availableModels
            .filter { $0.isDownloaded }
            .reduce(0) { $0 + $1.sizeGB }
    }
    
    public var downloadedCount: Int {
        availableModels.filter { $0.isDownloaded }.count
    }
}
