import Foundation
import Network
import os

/// Thread-safe network reachability monitor.
///
/// Uses `NWPathMonitor` to track connectivity changes and exposes a synchronous,
/// thread-safe checking interface for the runtime.
public final class NetworkMonitor: Sendable {
    
    // MARK: - Types
    
    public enum Status: Sendable {
        case online
        case expensive
        case offline
    }
    
    // MARK: - State
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.quantumbadger.network.monitor")
    
    // Thread-safe storage for current status (macOS 13+).
    // Using a simple lock-protected value for maximum compatibility and safety.
    private let _status = OSAllocatedUnfairLock(initialState: Status.offline)
    
    // MARK: - Init
    
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus: Status
            if path.status == .satisfied {
                newStatus = path.isExpensive ? .expensive : .online
            } else {
                newStatus = .offline
            }
            self._status.withLock { $0 = newStatus }
        }
    }
    
    // MARK: - Public API
    
    public func start() {
        monitor.start(queue: queue)
    }
    
    public func stop() {
        monitor.cancel()
    }
    
    public var currentStatus: Status {
        _status.withLock { $0 }
    }
    
    public var isReachable: Bool {
        let s = currentStatus
        return s == .online || s == .expensive
    }
}
