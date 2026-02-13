import Foundation
import BadgerCore

// MARK: - Thermal Status

/// Represents the current thermal state of the system
public struct ThermalStatus: Sendable, CustomStringConvertible {
    /// The raw thermal state from ProcessInfo
    public let state: SystemState.ThermalState
    
    /// Timestamp when this status was recorded
    public let timestamp: Date
    
    /// Whether the system is under thermal stress
    public var isUnderStress: Bool {
        state == .serious || state == .critical
    }
    
    /// Whether local inference should be throttled
    public var shouldThrottle: Bool {
        state == .fair || state == .serious || state == .critical
    }
    
    /// Whether local inference should be suspended
    public var shouldSuspend: Bool {
        state == .critical
    }
    
    /// Recommended action based on thermal state
    public var recommendedAction: ThermalAction {
        switch state {
        case .nominal:
            return .proceed
        case .fair:
            return .throttle
        case .serious:
            return .offloadToCloud
        case .critical:
            return .suspend
        }
    }
    
    public var description: String {
        "Thermal: \(state.rawValue) - \(recommendedAction)"
    }
}

// MARK: - Thermal Action

/// Recommended action based on thermal state
public enum ThermalAction: String, Sendable {
    case proceed = "Proceed"
    case throttle = "Throttle"
    case offloadToCloud = "OffloadToCloud"
    case suspend = "Suspend"
}

// MARK: - Thermal State Change

/// Represents a change in thermal state
public struct ThermalStateChange: Sendable {
    public let previous: SystemState.ThermalState
    public let current: SystemState.ThermalState
    public let timestamp: Date
    
    /// Whether this change represents a worsening condition
    public var isWorsening: Bool {
        current.priorityLevel > previous.priorityLevel
    }
    
    /// Whether this change represents an improvement
    public var isImproving: Bool {
        current.priorityLevel < previous.priorityLevel
    }
}

// MARK: - Thermal Monitor Delegate

/// Protocol for receiving thermal state updates.
/// Methods are 'async' to allow safe calling from the Actor context.
public protocol ThermalMonitorDelegate: AnyObject, Sendable {
    func thermalStateDidChange(_ change: ThermalStateChange) async
    func thermalStateDidReachCritical() async
}

// MARK: - Thermal Guard

/// Actor responsible for monitoring and managing thermal state
public actor ThermalGuard {
    
    // MARK: - Properties
    
    private var currentState: SystemState.ThermalState
    private var previousState: SystemState.ThermalState?
    private var delegates: [UUID: WeakThermalDelegate] = [:]
    private var isMonitoring = false
    private var notificationTask: Task<Void, Never>?
    
    /// History of thermal state changes (limited to last 100)
    private var stateHistory: [ThermalStateChange] = []
    private let maxHistorySize = 100
    
    // MARK: - Initialization
    
    public init() {
        // Get initial thermal state
        let processInfo = ProcessInfo.processInfo
        #if os(macOS)
        // Map ProcessInfo.ThermalState to our SystemState.ThermalState
        currentState = Self.mapThermalState(processInfo.thermalState)
        #else
        currentState = .nominal
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Get the current thermal status
    public func getCurrentStatus() -> ThermalStatus {
        ThermalStatus(state: currentState, timestamp: Date())
    }
    
    /// Check if the system is under thermal stress
    public func isUnderThermalStress() -> Bool {
        let status = getCurrentStatus()
        return status.isUnderStress
    }
    
    /// Check if local inference should be throttled
    public func shouldThrottle() -> Bool {
        let status = getCurrentStatus()
        return status.shouldThrottle
    }
    
    /// Check if local inference should be suspended
    public func shouldSuspend() -> Bool {
        let status = getCurrentStatus()
        return status.shouldSuspend
    }
    
    /// Get the recommended action based on current thermal state
    public func getRecommendedAction() -> ThermalAction {
        let status = getCurrentStatus()
        return status.recommendedAction
    }
    
    /// Get the history of thermal state changes
    public func getStateHistory() -> [ThermalStateChange] {
        stateHistory
    }
    
    /// Get the current thermal state as SystemState.ThermalState
    public func getThermalState() -> SystemState.ThermalState {
        currentState
    }
    
    /// Create a SystemState struct with current thermal information
    public func createSystemState(
        ramAvailable: UInt64,
        ramTotal: UInt64,
        batteryState: SystemState.BatteryState = .unknown,
        batteryLevel: Double? = nil
    ) -> SystemState {
        SystemState(
            ramAvailable: ramAvailable,
            ramTotal: ramTotal,
            thermalState: currentState,
            batteryState: batteryState,
            batteryLevel: batteryLevel,
            cpuUtilization: 0.0 // Would need additional monitoring
        )
    }
    
    // MARK: - Monitoring
    
    /// Start monitoring thermal state changes
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        #if os(macOS)
        notificationTask = Task { [weak self] in
            // Set up notification observer for thermal state changes
            _ = NotificationCenter.default
            
            // Periodically check thermal state
            while !Task.isCancelled {
                await self?.checkThermalState()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds
            }
        }
        #endif
    }
    
    /// Stop monitoring thermal state changes
    public func stopMonitoring() {
        isMonitoring = false
        notificationTask?.cancel()
        notificationTask = nil
    }
    
    /// Manually check and update thermal state
    public func checkThermalState() async {
        #if os(macOS)
        let processInfo = ProcessInfo.processInfo
        let newState = Self.mapThermalState(processInfo.thermalState)
        
        await updateState(newState)
        #endif
    }
    
    // MARK: - Delegate Management
    
    /// Register a delegate for thermal state updates
    /// - Returns: A token that can be used to unregister
    @discardableResult
    public func addDelegate(_ delegate: ThermalMonitorDelegate) -> UUID {
        let id = UUID()
        delegates[id] = WeakThermalDelegate(delegate: delegate)
        return id
    }
    
    /// Unregister a delegate
    public func removeDelegate(_ id: UUID) {
        delegates.removeValue(forKey: id)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: SystemState.ThermalState) async {
        guard newState != currentState else { return }
        
        previousState = currentState
        currentState = newState
        
        let change = ThermalStateChange(
            previous: previousState ?? .nominal,
            current: newState,
            timestamp: Date()
        )
        
        // Add to history
        stateHistory.append(change)
        if stateHistory.count > maxHistorySize {
            stateHistory.removeFirst()
        }
        
        // Notify delegates
        await notifyDelegates(of: change)
        
        // Special handling for critical state
        if newState == .critical {
            await notifyCriticalState()
        }
    }
    
    private func notifyDelegates(of change: ThermalStateChange) async {
        // Clean up dead references
        delegates = delegates.filter { $0.value.delegate != nil }
        
        // Notify living delegates
        for wrapper in delegates.values {
            await wrapper.delegate?.thermalStateDidChange(change)
        }
    }
    
    private func notifyCriticalState() async {
        for wrapper in delegates.values {
            await wrapper.delegate?.thermalStateDidReachCritical()
        }
    }
    
    // MARK: - Static Helpers
    
    #if os(macOS)
    /// Maps Foundation thermal state to BadgerCore system state
    internal static func mapThermalState(_ state: ProcessInfo.ThermalState) -> SystemState.ThermalState {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }
    #endif
    
    /// Get a human-readable description of thermal state
    public static func description(for state: SystemState.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Thermal state is nominal. No restrictions on inference."
        case .fair:
            return "Thermal state is fair. Consider throttling intensive tasks."
        case .serious:
            return "Thermal state is serious. Offload inference to cloud."
        case .critical:
            return "Thermal state is critical. Suspend all inference immediately."
        }
    }
}

// MARK: - Weak Delegate Wrapper

/// Weak wrapper for delegate to prevent retain cycles
private struct WeakThermalDelegate: Sendable {
    weak var delegate: ThermalMonitorDelegate?
    
    init(delegate: ThermalMonitorDelegate) {
        self.delegate = delegate
    }
}

// MARK: - System State Extensions

extension SystemState {
    /// Create a SystemState with current thermal information
    public static func current() -> SystemState {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        
        #if os(macOS)
        let thermalState = ThermalGuard.mapThermalState(ProcessInfo.processInfo.thermalState)
        #else
        let thermalState = SystemState.ThermalState.nominal
        #endif
        
        return SystemState(
            ramAvailable: physicalMemory / 4,
            ramTotal: physicalMemory,
            thermalState: thermalState,
            batteryState: .unknown,
            batteryLevel: nil,
            cpuUtilization: 0.0
        )
    }
}

// Note: mapThermalState is already defined inside the ThermalGuard actor at line 275.
// No duplicate extension needed.
