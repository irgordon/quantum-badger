import Foundation
import Observation
import BadgerCore

@MainActor
@Observable
public final class NPUThermalWatcher {
    public static let shared = NPUThermalWatcher()

    private var observer: NSObjectProtocol?
    private var isActive: Bool = false
    private var lastThrottleState: Bool = false
    private var emergencyTriggered: Bool = false
    public var isThrottling: Bool = false

    private init() {}

    public func start() {
        guard !isActive else { return }
        isActive = true
        updateThermalState(ProcessInfo.processInfo.thermalState)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateThermalState(ProcessInfo.processInfo.thermalState)
        }
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func updateThermalState(_ state: ProcessInfo.ThermalState) {
        // macOS doesn’t expose raw die temperature.
        // Treat .serious as the 95°C throttle proxy and .critical as the 105°C emergency proxy.
        let shouldThrottle = state == .serious || state == .critical
        
        // NPUAffinityManager is an actor, so we must await.
        // Since we are monitoring, fire-and-forget is acceptable.
        Task {
            await NPUAffinityManager.shared.setThermalLimitExceeded(shouldThrottle)
        }
        
        isThrottling = shouldThrottle
        
        if shouldThrottle != lastThrottleState {
            lastThrottleState = shouldThrottle
            SystemEventBus.shared.post(.thermalThrottlingChanged(active: shouldThrottle))
        }
        
        if state == .critical && !emergencyTriggered {
            emergencyTriggered = true
            SystemEventBus.shared.post(
                .thermalEmergencyShutdown(reason: "Thermal state critical (emergency shutdown).")
            )
        }
        
        if state != .critical {
            emergencyTriggered = false
        }
    }
}
