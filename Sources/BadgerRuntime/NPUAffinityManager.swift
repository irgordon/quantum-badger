import Foundation
import BadgerCore

    case chat
    case utility // summarization, indexing, etc.
    case scout
}

/// Manages task priority and affinity for NPU operations.
public actor NPUAffinityManager {
    public static let shared = NPUAffinityManager()
    
    private init() {}
    
    private var isThrottled = false

    public func setThermalLimitExceeded(_ exceeded: Bool) {
        self.isThrottled = exceeded
    }

    public func executeWithAffinity<T>(kind: TaskKind, operation: () async throws -> T) async throws -> T {
        // In a real implementation, this might use custom QoS or
        // interact with a semaphore to limit concurrent heavy tasks.
        
        // Thermal Throttling:
        // If the system is hot (.serious or .critical), we downgrade 
        // all tasks to .utility to reduce heat generation and allow the OS to schedule on Efficiency cores.
        var priority: TaskPriority = kind == .chat ? .userInitiated : .utility
        
        if isThrottled {
            priority = .utility 
            // We could also add a small sleep here to "trickle" process?
            // try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        return try await Task(priority: priority) {
            try await operation()
        }.value
    }
}
