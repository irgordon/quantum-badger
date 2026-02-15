import Foundation
import Metal
import BadgerCore

// MARK: - VRAM Monitor Errors

public enum VRAMMonitorError: Error, Sendable {
    case metalNotAvailable
    case deviceCreationFailed
    case queryFailed
}

// MARK: - VRAM Status

/// Represents the current VRAM status of the system
public struct VRAMStatus: Sendable, CustomStringConvertible {
    /// Total recommended max working set size in bytes (Neural Engine limit)
    public let recommendedMaxWorkingSetSize: UInt64
    
    /// Current allocated size in bytes (if available)
    public let currentAllocatedSize: UInt64?
    
    /// Available VRAM in bytes (estimated)
    public var availableVRAM: UInt64 {
        // Apple recommends not exceeding 70-80% of the working set limit to avoid swap death.
        let safeLimit = UInt64(Double(recommendedMaxWorkingSetSize) * 0.75)
        
        if let allocated = currentAllocatedSize {
            return allocated < safeLimit ? safeLimit - allocated : 0
        }
        return safeLimit
    }
    
    /// Whether sufficient VRAM is available for local inference
    public var hasSufficientVRAM: Bool {
        availableVRAM >= 4 * 1024 * 1024 * 1024 // 4GB minimum
    }
    
    /// Usage ratio (0.0 - 1.0)
    public var usageRatio: Double {
        guard let allocated = currentAllocatedSize, recommendedMaxWorkingSetSize > 0 else {
            return 0.0
        }
        return Double(allocated) / Double(recommendedMaxWorkingSetSize)
    }
    
    /// Recommended quantization level based on available VRAM
    public var recommendedQuantization: QuantizationLevel {
        let availableGB = Double(availableVRAM) / (1024 * 1024 * 1024)
        switch availableGB {
        case 24...: return .none // Full precision (rare on consumer hardware)
        case 12..<24: return .q8 // High precision
        case 6..<12: return .q4  // Standard balanced
        default: return .q4      // Stick to Q4 for stability, avoid Q3 unless necessary
        }
    }
    
    public var description: String {
        let maxGB = Double(recommendedMaxWorkingSetSize) / (1024 * 1024 * 1024)
        let availGB = Double(availableVRAM) / (1024 * 1024 * 1024)
        return "VRAM: \(String(format: "%.1f", maxGB))GB max, \(String(format: "%.1f", availGB))GB available, quantization: \(recommendedQuantization)"
    }
}

// MARK: - Quantization Level

/// Available quantization levels for model loading
public enum QuantizationLevel: String, Sendable, CaseIterable {
    case none = "None"
    case q8 = "Q8"
    case q6 = "Q6"
    case q4 = "Q4"
    case q3 = "Q3"
    case q2 = "Q2"
    
    /// The bit depth for this quantization level
    public var bits: Int {
        switch self {
        case .none: return 16 // Full fp16
        case .q8: return 8
        case .q6: return 6
        case .q4: return 4
        case .q3: return 3
        case .q2: return 2
        }
    }
    
    /// Estimated memory reduction factor (approximate)
    public var memoryReductionFactor: Double {
        Double(bits) / 16.0
    }
    
    /// Whether this quantization level is recommended for quality-sensitive tasks
    public var isQualityPreserving: Bool {
        switch self {
        case .none, .q8:
            return true
        case .q6, .q4:
            return true // Still decent quality
        case .q3, .q2:
            return false // May impact quality
        }
    }
}

// MARK: - VRAM Monitor

/// Actor responsible for monitoring VRAM usage on Apple Silicon
public actor VRAMMonitor {
    
    // MARK: - Properties
    
    private var metalDevice: MTLDevice?
    private var lastStatus: VRAMStatus?
    private var updateInterval: TimeInterval
    
    // FIX: Replaced unused Timer with Task handle for proper cancellation
    private var monitoringTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Initialize the VRAM monitor
    /// - Parameter updateInterval: How often to update the status (default: 5 seconds)
    public init(updateInterval: TimeInterval = 5.0) {
        self.updateInterval = updateInterval
        self.metalDevice = MTLCreateSystemDefaultDevice()
    }
    
    // MARK: - Public Methods
    
    /// Check if Metal is available on this system
    public func isAvailable() -> Bool {
        metalDevice != nil
    }
    
    /// Get the current VRAM status
    /// - Returns: VRAMStatus with current memory information
    public func getCurrentStatus() -> VRAMStatus {
        guard let device = metalDevice else {
            return VRAMStatus(recommendedMaxWorkingSetSize: 0, currentAllocatedSize: nil)
        }
        
        // Get recommended max working set size (Neural Engine limit)
        let maxWorkingSetSize = device.recommendedMaxWorkingSetSize
        
        // Try to get current allocation if available (may not be supported on all devices)
        let currentAllocated = UInt64(device.currentAllocatedSize)
        
        let status = VRAMStatus(
            recommendedMaxWorkingSetSize: maxWorkingSetSize,
            currentAllocatedSize: currentAllocated
        )
        
        lastStatus = status
        return status
    }
    
    /// Get the recommended max working set size in bytes
    public func getRecommendedMaxWorkingSetSize() -> UInt64 {
        guard let device = metalDevice else {
            return 0
        }
        return device.recommendedMaxWorkingSetSize
    }
    
    /// Check if a model with given size can fit in available VRAM
    /// - Parameter requiredBytes: The required VRAM in bytes
    /// - Returns: True if the model can fit
    public func canFitModel(requiredBytes: UInt64) -> Bool {
        let status = getCurrentStatus()
        return status.availableVRAM >= requiredBytes
    }
    
    /// Get the recommended quantization for the current available VRAM
    public func getRecommendedQuantization() throws -> QuantizationLevel {
        let status = getCurrentStatus()
        return status.recommendedQuantization
    }
    
    /// Estimate the maximum model size that can be loaded
    public func estimateMaxModelSize() -> UInt64 {
        let status = getCurrentStatus()
        // Reserve 1.5GB buffer for OS overhead
        let buffer: UInt64 = 1536 * 1024 * 1024
        return status.availableVRAM > buffer ? status.availableVRAM - buffer : 0
    }
    
    /// Estimate model memory requirement
    /// - Parameters:
    ///   - parameterCount: Number of parameters in billions
    ///   - quantization: Quantization level to use
    /// - Returns: Estimated memory in bytes
    nonisolated public func estimateModelMemory(parameterCountBillions: Double, quantization: QuantizationLevel) -> UInt64 {
        // Base calculation: parameters * bytes per parameter
        // Add overhead for KV cache, activations, etc. (approximately 20%)
        let baseMemory = parameterCountBillions * 1_000_000_000 * Double(quantization.bits) / 8
        let withOverhead = baseMemory * 1.2 // 20% overhead
        return UInt64(withOverhead)
    }
    
    /// Start periodic monitoring
    /// - Parameter callback: Called when status is updated
    public func startMonitoring(callback: @escaping @Sendable (VRAMStatus) -> Void) {
        guard monitoringTask == nil else { return }
        
        monitoringTask = Task {
            while !Task.isCancelled {
                let status = await getCurrentStatus()
                callback(status)
                
                try? await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop periodic monitoring
    public func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    // MARK: - Model Selection Helpers
    
    /// Recommend a model class based on available VRAM.
    /// FIX: Adjusted thresholds to prevent OOM on 8GB machines.
    public func recommendModelClass() -> ModelClass {
        let status = getCurrentStatus()
        let availableGB = Double(status.availableVRAM) / (1024 * 1024 * 1024)
        
        switch availableGB {
        case 16...:
            return .phi4     // 14B Params -> Needs ~10GB. Safe for >16GB available.
        case 10..<16:
            return .llama31  // 8B Params -> Needs ~6GB.
        case 6..<10:
            return .mistral  // 7B Params -> Needs ~5GB.
        case 4..<6:
            return .qwen25   // 3B-7B Params (Qwen comes in sizes, assuming 3B here)
        default:
            return .gemma2   // 2B Params -> Safe for low memory.
        }
    }
    
    /// Get the optimal batch size for inference based on available VRAM
    public func getOptimalBatchSize() -> Int {
        let status = getCurrentStatus()
        let availableGB = Double(status.availableVRAM) / (1024 * 1024 * 1024)
        
        // Conservative batching to maintain responsiveness
        switch availableGB {
        case 24...: return 8
        case 16..<24: return 4
        case 8..<16: return 1 // Strict serial for 8GB/16GB machines
        default: return 1
        }
    }
}

// MARK: - Convenience Extensions

extension VRAMMonitor {
    /// Quick check if the system has sufficient VRAM for local inference
    public static func hasSufficientVRAM() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return false
        }
        // 5GB is a safer minimum baseline for the OS + App + 3B Model
        return device.recommendedMaxWorkingSetSize >= 5 * 1024 * 1024 * 1024
    }
    
    /// Get the Metal device name
    public static func getDeviceName() -> String? {
        MTLCreateSystemDefaultDevice()?.name
    }
}
