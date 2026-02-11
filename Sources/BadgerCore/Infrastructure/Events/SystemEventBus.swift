import Foundation
import Combine

/// A system-wide event bus for critical operational events.
public actor SystemEventBus {
    public static let shared = SystemEventBus()
    
    private var subscribers: [UUID: AsyncStream<SystemEvent>.Continuation] = [:]

    public func post(_ event: SystemEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
    
    public func stream() -> AsyncStream<SystemEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeSubscriber(id: id)
                }
            }
        }
    }
    
    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    
    nonisolated public func nonisolatedPost(_ event: SystemEvent) {
        Task {
            await self.post(event)
        }
    }
}

public enum SystemEvent: Sendable {
    case networkCircuitClosed(host: String)
    case networkCircuitTripped(host: String, cooldownSeconds: Int)
    case networkCircuitOpened(host: String, until: Date)
    case networkResponseTruncated(host: String)
    case thermalThrottlingChanged(active: Bool)
    case thermalEmergencyShutdown(reason: String)
}
