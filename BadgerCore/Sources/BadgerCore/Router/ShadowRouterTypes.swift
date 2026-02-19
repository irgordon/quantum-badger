import Foundation

// MARK: - Model Class

/// Represents different classes of local models available for inference
public enum ModelClass: String, Sendable, Codable, CaseIterable, Identifiable {
    case phi4 = "Phi-4"
    case qwen25 = "Qwen-2.5"
    case llama31 = "Llama-3.1"
    case mistral = "Mistral-7B"  // Renamed from 'mixtral' - was incorrectly labeled
    case gemma2 = "Gemma-2"
    
    public var id: String { rawValue }
    
    /// The approximate size of the model in billions of parameters
    public var parameterSize: Int {
        switch self {
        case .phi4: return 14
        case .qwen25: return 7
        case .llama31: return 8
        case .mistral: return 7  // Correct for Mistral 7B (not Mixtral 8x7B which is 47B params)
        case .gemma2: return 9
        }
    }
    
    /// Whether this model is optimized for Apple Silicon
    public var isMLXOptimized: Bool {
        switch self {
        case .phi4, .qwen25, .llama31, .mistral, .gemma2:
            return true
        }
    }
    
    /// Recommended VRAM requirement in GB
    public var recommendedVRAM: Double {
        switch self {
        case .phi4: return 8.0
        case .qwen25: return 4.0
        case .llama31: return 6.0
        case .mistral: return 6.0  // ~6GB for Q4 quantization of 7B model
        case .gemma2: return 6.0
        }
    }
    
    /// Quality score for general tasks (1-10)
    public var generalQualityScore: Int {
        switch self {
        case .phi4: return 9
        case .qwen25: return 8
        case .llama31: return 8
        case .mistral: return 7
        case .gemma2: return 7
        }
    }
    
    /// Quality score for coding tasks (1-10)
    public var codingQualityScore: Int {
        switch self {
        case .phi4: return 9
        case .qwen25: return 8
        case .llama31: return 7
        case .mistral: return 7
        case .gemma2: return 6
        }
    }
    
    /// Quality score for reasoning tasks (1-10)
    public var reasoningQualityScore: Int {
        switch self {
        case .phi4: return 9
        case .qwen25: return 8
        case .llama31: return 7
        case .mistral: return 7
        case .gemma2: return 7
        }
    }
}

// MARK: - Cloud Provider

/// Supported cloud AI providers
public enum CloudProvider: String, Sendable, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"
    case applePCC = "ApplePCC"
    
    public var id: String { rawValue }
    
    /// Whether this provider supports Private Cloud Compute
    public var supportsPCC: Bool {
        switch self {
        case .applePCC:
            return true
        case .openAI, .anthropic, .google:
            return false
        }
    }
    
    /// Whether this provider is considered "sovereign" (privacy-preserving)
    public var isSovereign: Bool {
        switch self {
        case .applePCC:
            return true
        case .openAI, .anthropic, .google:
            return false
        }
    }
    
    /// Default model for this provider
    public var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-4o"
        case .anthropic:
            return "claude-3-5-sonnet-20241022"
        case .google:
            return "gemini-1.5-pro"
        case .applePCC:
            return "apple-llm"
        }
    }
    
    /// Available models for this provider
    public var availableModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .google:
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]
        case .applePCC:
            return ["apple-llm"]
        }
    }
    
    /// Estimated latency tier (lower is faster)
    public var latencyTier: Int {
        switch self {
        case .applePCC:
            return 1
        case .anthropic:
            return 2
        case .openAI:
            return 2
        case .google:
            return 3
        }
    }
}

// MARK: - Prompt Complexity

/// Represents the assessed complexity level of a user prompt
public enum PromptComplexity: String, Sendable, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    /// The minimum quality score required from a local model to handle this complexity
    public var minimumLocalQualityScore: Int {
        switch self {
        case .low:
            return 5
        case .medium:
            return 7
        case .high:
            return 9
        }
    }
    
    /// Estimated token count range
    public var estimatedTokenRange: ClosedRange<Int> {
        switch self {
        case .low:
            return 1...100
        case .medium:
            return 101...1000
        case .high:
            return 1001...8000
        }
    }
    
    /// Whether this complexity typically requires reasoning capabilities
    public var requiresReasoning: Bool {
        switch self {
        case .low:
            return false
        case .medium, .high:
            return true
        }
    }
    
    /// Keywords that indicate higher prompt complexity
    public static let complexityIndicators = [
        "explain", "analyze", "compare", "contrast", "evaluate",
        "synthesize", "critique", "justify", "recommend", "design",
        "implement", "optimize", "refactor", "architecture",
        "algorithm", "complex", "detailed", "comprehensive",
        "synthesize", "critique", "analysis", "evaluate"
    ]

    /// Assess complexity based on prompt characteristics
    public static func assess(prompt: String) -> PromptComplexity {
        let wordCount = prompt.split(separator: " ").count
        let lineCount = prompt.components(separatedBy: .newlines).count
        
        let indicatorCount = complexityIndicators.reduce(0) { count, indicator in
            count + (prompt.lowercased().contains(indicator) ? 1 : 0)
        }
        
        // Check for code blocks
        let hasCodeBlock = prompt.contains("```") || prompt.contains("`")
        
        // Check for specific high-complexity patterns
        let hasCodeWithExplanation = hasCodeBlock && (prompt.lowercased().contains("explain") || prompt.lowercased().contains("document"))
        let asksForMultipleThings = (prompt.lowercased().components(separatedBy: "?").count > 2) ||
                                    (prompt.lowercased().components(separatedBy: "also").count > 2)
        
        // Scoring
        var score = 0
        if wordCount > 400 { score += 3 }
        else if wordCount > 200 { score += 2 }
        else if wordCount > 50 { score += 1 }
        
        if lineCount > 40 { score += 3 }
        else if lineCount > 20 { score += 2 }
        else if lineCount > 5 { score += 1 }
        
        if indicatorCount > 5 { score += 3 }
        else if indicatorCount > 2 { score += 2 }
        else if indicatorCount > 0 { score += 1 }
        
        if hasCodeWithExplanation { score += 2 }
        else if hasCodeBlock { score += 1 }
        
        if asksForMultipleThings { score += 1 }
        
        switch score {
        case 0...3:
            return .low
        case 4...6:
            return .medium
        default:
            return .high
        }
    }
}

// MARK: - Router Decision

/// Represents the routing decision made by the Shadow Router
public enum RouterDecision: Sendable, Codable, Equatable {
    case local(ModelClass)
    case cloud(CloudProvider, String)
    
    /// Whether this decision routes to a local model
    public var isLocal: Bool {
        switch self {
        case .local:
            return true
        case .cloud:
            return false
        }
    }
    
    /// Whether this decision routes to the cloud
    public var isCloud: Bool {
        !isLocal
    }
    
    /// The target model name
    public var targetModel: String {
        switch self {
        case .local(let modelClass):
            return modelClass.rawValue
        case .cloud(_, let model):
            return model
        }
    }
    
    /// The provider (cloud provider or "Local")
    public var provider: String {
        switch self {
        case .local:
            return "Local"
        case .cloud(let provider, _):
            return provider.rawValue
        }
    }
    
    /// Whether this decision uses Private Cloud Compute
    public var usesPCC: Bool {
        switch self {
        case .local:
            return false
        case .cloud(let provider, _):
            return provider.supportsPCC
        }
    }
    
    /// Whether this decision is privacy-preserving
    public var isPrivacyPreserving: Bool {
        switch self {
        case .local:
            return true
        case .cloud(let provider, _):
            return provider.isSovereign
        }
    }
}

// MARK: - System State

/// Represents the current state of the system for routing decisions
public struct SystemState: Sendable, Codable {
    
    // MARK: - RAM Information
    
    /// Available RAM in bytes
    public let ramAvailable: UInt64
    
    /// Total RAM in bytes
    public let ramTotal: UInt64
    
    /// RAM usage percentage (0.0 - 1.0)
    public var ramUsagePercentage: Double {
        guard ramTotal > 0 else { return 0 }
        return 1.0 - (Double(ramAvailable) / Double(ramTotal))
    }
    
    /// Whether sufficient RAM is available for local inference
    public var hasSufficientRAM: Bool {
        // Require at least 4GB available for local inference
        ramAvailable >= 4 * 1024 * 1024 * 1024
    }
    
    // MARK: - Thermal State
    
    /// Thermal state of the system
    public enum ThermalState: String, Sendable, Codable, CaseIterable {
        case nominal = "Nominal"
        case fair = "Fair"
        case serious = "Serious"
        case critical = "Critical"
        
        /// Whether this thermal state allows intensive local inference
        public var allowsIntensiveCompute: Bool {
            switch self {
            case .nominal, .fair:
                return true
            case .serious, .critical:
                return false
            }
        }
        
        /// Whether this thermal state requires offloading to cloud
        public var requiresCloudOffload: Bool {
            switch self {
            case .nominal, .fair:
                return false
            case .serious, .critical:
                return true
            }
        }
        
        /// Priority level (lower is better)
        public var priorityLevel: Int {
            switch self {
            case .nominal: return 1
            case .fair: return 2
            case .serious: return 3
            case .critical: return 4
            }
        }
    }
    
    public let thermalState: ThermalState
    
    // MARK: - Battery Information
    
    /// Battery state
    public enum BatteryState: String, Sendable, Codable, CaseIterable {
        case unknown = "Unknown"
        case unplugged = "Unplugged"
        case charging = "Charging"
        case full = "Full"
        
        /// Whether the device is on battery power
        public var isOnBattery: Bool {
            self == .unplugged
        }
    }
    
    public let batteryState: BatteryState
    
    /// Battery level (0.0 - 1.0), nil if unknown
    public let batteryLevel: Double?
    
    /// Whether local inference should be constrained due to battery
    public var shouldConstrainDueToBattery: Bool {
        guard batteryState.isOnBattery else { return false }
        guard let level = batteryLevel else { return true }
        return level < 0.2 // Constrain if battery below 20%
    }
    
    // MARK: - GPU Information
    
    /// Available GPU VRAM in bytes (if applicable)
    public let gpuVRAMAvailable: UInt64?
    
    /// GPU utilization percentage (0.0 - 1.0)
    public let gpuUtilization: Double?
    
    /// Whether sufficient GPU resources are available
    public var hasSufficientGPU: Bool {
        guard let vram = gpuVRAMAvailable else { return true }
        // Require at least 4GB VRAM for local inference
        return vram >= 4 * 1024 * 1024 * 1024
    }
    
    // MARK: - CPU Information
    
    /// CPU utilization percentage (0.0 - 1.0)
    public let cpuUtilization: Double
    
    /// Whether the CPU is under heavy load
    public var isCPUOverloaded: Bool {
        cpuUtilization > 0.8
    }
    
    // MARK: - System Load Indicators
    
    /// Active application that might be competing for resources
    public let competingApplications: [String]
    
    /// Keywords for identifying Xcode
    private static let xcodeKeywords = ["xcode"]

    /// Keywords for identifying video rendering applications
    private static let videoRenderingKeywords = [
        "final cut",
        "premiere",
        "davinci",
        "after effects"
    ]

    /// Helper to check if any app matching the keywords is running
    private func isAppRunning(matching keywords: [String]) -> Bool {
        competingApplications.contains { app in
            let lowercased = app.lowercased()
            return keywords.contains { keyword in
                lowercased.contains(keyword)
            }
        }
    }

    /// Whether Xcode is currently building
    public var isXcodeBuilding: Bool {
        isAppRunning(matching: Self.xcodeKeywords)
    }
    
    /// Whether video rendering is in progress
    public var isRenderingVideo: Bool {
        isAppRunning(matching: Self.videoRenderingKeywords)
    }
    
    // MARK: - Safe Mode Determination
    
    /// Whether the system should enter Safe Mode (offload all to PCC)
    public var shouldEnterSafeMode: Bool {
        thermalState.requiresCloudOffload ||
        (isCPUOverloaded && thermalState != .nominal) ||
        (isXcodeBuilding && thermalState != .nominal) ||
        (isRenderingVideo && thermalState != .nominal) ||
        shouldConstrainDueToBattery
    }
    
    /// Whether local inference is recommended given current conditions
    public var isLocalInferenceRecommended: Bool {
        hasSufficientRAM &&
        hasSufficientGPU &&
        thermalState.allowsIntensiveCompute &&
        !shouldConstrainDueToBattery &&
        !isCPUOverloaded
    }
    
    // MARK: - Initialization
    
    public init(
        ramAvailable: UInt64,
        ramTotal: UInt64,
        thermalState: ThermalState,
        batteryState: BatteryState,
        batteryLevel: Double?,
        gpuVRAMAvailable: UInt64? = nil,
        gpuUtilization: Double? = nil,
        cpuUtilization: Double,
        competingApplications: [String] = []
    ) {
        self.ramAvailable = ramAvailable
        self.ramTotal = ramTotal
        self.thermalState = thermalState
        self.batteryState = batteryState
        self.batteryLevel = batteryLevel
        self.gpuVRAMAvailable = gpuVRAMAvailable
        self.gpuUtilization = gpuUtilization
        self.cpuUtilization = cpuUtilization
        self.competingApplications = competingApplications
    }
    
    // MARK: - Factory Methods
    
    /// Create a nominal system state (for testing)
    public static func nominal() -> SystemState {
        SystemState(
            ramAvailable: 16 * 1024 * 1024 * 1024, // 16GB
            ramTotal: 32 * 1024 * 1024 * 1024,     // 32GB
            thermalState: .nominal,
            batteryState: .full,
            batteryLevel: 1.0,
            gpuVRAMAvailable: 16 * 1024 * 1024 * 1024,
            gpuUtilization: 0.1,
            cpuUtilization: 0.2,
            competingApplications: []
        )
    }
    
    /// Create a stressed system state (for testing Safe Mode)
    public static func stressed() -> SystemState {
        SystemState(
            ramAvailable: 2 * 1024 * 1024 * 1024,  // 2GB
            ramTotal: 32 * 1024 * 1024 * 1024,
            thermalState: .serious,
            batteryState: .unplugged,
            batteryLevel: 0.15,
            gpuVRAMAvailable: 1 * 1024 * 1024 * 1024,
            gpuUtilization: 0.9,
            cpuUtilization: 0.95,
            competingApplications: ["Xcode", "Final Cut Pro"]
        )
    }
}

// MARK: - Router Configuration

/// Configuration for the Shadow Router decision making
public struct RouterConfiguration: Sendable, Codable {
    
    /// Threshold for preferring cloud over local (quality score 1-10)
    public let localQualityThreshold: Int
    
    /// Whether to prefer sovereign (PCC/Local) options
    public let preferSovereign: Bool
    
    /// Whether Safe Mode is enabled
    public let safeModeEnabled: Bool
    
    /// Default cloud provider preference
    public let preferredCloudProvider: CloudProvider
    
    /// Preferred local model when conditions allow
    public let preferredLocalModel: ModelClass
    
    /// Minimum RAM required for local inference (in GB)
    public let minimumRAMForLocal: Double
    
    /// Maximum thermal state allowed for local inference
    public let maxThermalStateForLocal: SystemState.ThermalState
    
    /// Whether to offload to cloud during heavy battery drain
    public let offloadOnLowBattery: Bool
    
    public init(
        localQualityThreshold: Int = 7,
        preferSovereign: Bool = true,
        safeModeEnabled: Bool = false,
        preferredCloudProvider: CloudProvider = .anthropic,
        preferredLocalModel: ModelClass = .phi4,
        minimumRAMForLocal: Double = 4.0,
        maxThermalStateForLocal: SystemState.ThermalState = .fair,
        offloadOnLowBattery: Bool = true
    ) {
        self.localQualityThreshold = localQualityThreshold
        self.preferSovereign = preferSovereign
        self.safeModeEnabled = safeModeEnabled
        self.preferredCloudProvider = preferredCloudProvider
        self.preferredLocalModel = preferredLocalModel
        self.minimumRAMForLocal = minimumRAMForLocal
        self.maxThermalStateForLocal = maxThermalStateForLocal
        self.offloadOnLowBattery = offloadOnLowBattery
    }
}
