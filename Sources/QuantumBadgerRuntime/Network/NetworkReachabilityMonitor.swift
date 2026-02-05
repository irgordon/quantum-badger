import Foundation
import Network
import Observation

enum NetworkScope: String {
    case offline
    case localNetwork
    case internet
}

@MainActor
@Observable
final class NetworkReachabilityMonitor {
    private(set) var status: NWPath.Status = .requiresConnection
    private(set) var scope: NetworkScope = .offline
    private(set) var isConstrained: Bool = false
    private(set) var isExpensive: Bool = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.quantumbadger.network.monitor")
    private var streamContinuation: AsyncStream<NWPath>.Continuation?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.status = path.status
                self.scope = NetworkReachabilityMonitor.resolveScope(from: path)
                self.isConstrained = path.isConstrained
                self.isExpensive = path.isExpensive
                self.streamContinuation?.yield(path)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        streamContinuation?.finish()
        streamContinuation = nil
    }

    var isReachable: Bool {
        status == .satisfied
    }

    private static func resolveScope(from path: NWPath) -> NetworkScope {
        guard path.status == .satisfied else { return .offline }
        if #available(macOS 14.0, *) {
            if path.isLocalNetworkAccess {
                return .localNetwork
            }
        }
        return .internet
    }

    func statusStream() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            continuation.yield(monitor.currentPath)
            streamContinuation = continuation
        }
    }
}
