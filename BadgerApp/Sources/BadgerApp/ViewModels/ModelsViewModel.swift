import Foundation
import SwiftUI
import AppKit
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
    
    private struct HuggingFaceModelResponse: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
        }
        let siblings: [Sibling]
    }
    
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
        let modelClass = modelInfo.modelClass
        let repo = modelInfo.huggingFaceRepo
        downloadTasks[modelClass] = Task {
            do {
                try await self.performModelDownload(modelClass: modelClass, repo: repo)
            } catch is CancellationError {
                await MainActor.run {
                    self.updateDownloadState(for: modelClass, state: .notStarted)
                }
            } catch {
                await MainActor.run {
                    self.updateDownloadState(for: modelClass, state: .failed(error: error.localizedDescription))
                }
            }
            _ = await MainActor.run {
                self.downloadTasks.removeValue(forKey: modelClass)
            }
        }
    }
    
    public func cancelDownload(for modelClass: ModelClass) {
        downloadTasks[modelClass]?.cancel()
        downloadTasks.removeValue(forKey: modelClass)
        updateDownloadState(for: modelClass, state: .notStarted)
        let modelPath = modelsDirectory().appendingPathComponent(modelClass.rawValue)
        try? FileManager.default.removeItem(at: modelPath)
    }
    
    public func deleteModel(_ modelClass: ModelClass) {
        let modelPath = modelsDirectory().appendingPathComponent(modelClass.rawValue)
        do {
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }
        } catch {
            if let index = availableModels.firstIndex(where: { $0.modelClass == modelClass }) {
                availableModels[index].downloadState = .failed(error: error.localizedDescription)
            }
            return
        }
        
        if let index = availableModels.firstIndex(where: { $0.modelClass == modelClass }) {
            availableModels[index].isDownloaded = false
            availableModels[index].localPath = nil
            availableModels[index].downloadState = .notStarted
        }
    }
    
    private func checkDownloadedModels() async {
        let directory = modelsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        for index in availableModels.indices {
            let modelClass = availableModels[index].modelClass
            let modelPath = directory.appendingPathComponent(modelClass.rawValue)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                availableModels[index].isDownloaded = true
                availableModels[index].localPath = modelPath
                availableModels[index].downloadState = .completed
            } else {
                availableModels[index].isDownloaded = false
                availableModels[index].localPath = nil
                availableModels[index].downloadState = .notStarted
            }
        }
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
    
    public func openModelLocation(_ modelClass: ModelClass) {
        let modelPath = modelsDirectory().appendingPathComponent(modelClass.rawValue)
        NSWorkspace.shared.activateFileViewerSelecting([modelPath])
    }
    
    private func performModelDownload(modelClass: ModelClass, repo: String) async throws {
        let modelPath = modelsDirectory().appendingPathComponent(modelClass.rawValue)
        try? FileManager.default.removeItem(at: modelPath)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
        
        let files = try await fetchDownloadableFiles(repo: repo)
        guard !files.isEmpty else {
            throw URLError(.fileDoesNotExist)
        }
        
        let totalFiles = files.count
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let fileURL = huggingFaceResolveURL(repo: repo, file: file)
            let destination = modelPath.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let (data, response) = try await URLSession.shared.data(from: fileURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try data.write(to: destination, options: .atomic)
            
            let progress = Double(index + 1) / Double(totalFiles)
            await MainActor.run {
                self.updateDownloadState(
                    for: modelClass,
                    state: .downloading(
                        progress: progress,
                        bytesDownloaded: Int64(index + 1),
                        totalBytes: Int64(totalFiles)
                    )
                )
            }
        }
        
        await MainActor.run {
            self.updateDownloadState(for: modelClass, state: .verifying)
        }
        try validateDownloadedModel(at: modelPath)
        await MainActor.run {
            self.markModelAsDownloaded(modelClass)
            self.updateDownloadState(for: modelClass, state: .completed)
        }
    }
    
    private func fetchDownloadableFiles(repo: String) async throws -> [String] {
        let apiURL = URL(string: "https://huggingface.co/api/models/\(repo)")!
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let model = try JSONDecoder().decode(HuggingFaceModelResponse.self, from: data)
        let allowedExtensions: Set<String> = ["json", "txt", "model", "safetensors", "tiktoken"]
        let disallowedPrefixes = [".", "README", "LICENSE", "NOTICE", ".gitattributes"]
        
        let candidates = model.siblings
            .map(\.rfilename)
            .filter { name in
                !disallowedPrefixes.contains { name.hasPrefix($0) }
                && allowedExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
            }
        
        if candidates.contains("config.json") {
            return candidates
        }
        return []
    }
    
    private func huggingFaceResolveURL(repo: String, file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
    }
    
    private func validateDownloadedModel(at modelPath: URL) throws {
        let configPath = modelPath.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw URLError(.fileDoesNotExist)
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: modelPath, includingPropertiesForKeys: nil) else {
            throw URLError(.cannotOpenFile)
        }
        let hasWeights = files.contains { file in
            file.pathExtension.lowercased() == "safetensors" || file.pathExtension.lowercased() == "bin"
        }
        guard hasWeights else {
            throw URLError(.cannotDecodeRawData)
        }
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
