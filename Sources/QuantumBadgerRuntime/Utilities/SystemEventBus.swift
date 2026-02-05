import Foundation

enum SystemEvent {
    case networkResponseTruncated(host: String)
    case modelLoadBlocked(level: MemoryPressureLevel)
    case networkCircuitTripped(host: String, cooldownSeconds: Int)
    case networkCircuitOpened(host: String, until: Date)
    case networkCircuitClosed(host: String)
    case decodingSkipped(count: Int, source: String?)
}

final class SystemEventBus {
    static let shared = SystemEventBus()

    private let streamInternal: AsyncStream<SystemEvent>
    private var continuation: AsyncStream<SystemEvent>.Continuation?

    private init() {
        var continuation: AsyncStream<SystemEvent>.Continuation?
        self.streamInternal = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func stream() -> AsyncStream<SystemEvent> {
        streamInternal
    }

    func post(_ event: SystemEvent) {
        continuation?.yield(event)
    }
}
