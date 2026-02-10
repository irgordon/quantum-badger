import Foundation
import Combine

/// A system-wide event bus for critical operational events.
public final class SystemEventBus: @unchecked Sendable {
    public static let shared = SystemEventBus()
    
    // Using PassthroughSubject for simplicity, or NotificationCenter?
    // User snippet uses .post().
    // We'll use Combine for modern Swift.
    private let subject = PassthroughSubject<SystemEvent, Never>()
    
    public var events: AnyPublisher<SystemEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    private init() {}
    
    public func post(_ event: SystemEvent) {
        subject.send(event)
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
