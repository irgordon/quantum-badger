import Foundation
import Security

@objc protocol UntrustedParsingXPCProtocol {
    func parse(
        _ data: Data,
        allowlist: [String],
        maxParseSeconds: Double,
        maxAnchorScans: Int,
        withReply reply: @escaping (String?, String?) -> Void
    )
}

final class UntrustedParsingXPCClient: UntrustedParsingService {
    private let serviceName: String
    private let policyStore: UntrustedParsingPolicyStore

    init(
        serviceName: String = "com.quantumbadger.UntrustedParser",
        policyStore: UntrustedParsingPolicyStore = UntrustedParsingPolicyStore()
    ) {
        self.serviceName = serviceName
        self.policyStore = policyStore
    }

    func parse(_ data: Data) async throws -> String {
        let retryEnabled = policyStore.retryEnabled
        let maxRetries = policyStore.maxRetries
        let allowlist = policyStore.allowedTags
        let maxParseSeconds = policyStore.maxParseSeconds
        let maxAnchorScans = policyStore.maxAnchorScans
        var attempt = 0
        while true {
            do {
                return try await parseOnce(
                    data,
                    allowlist: allowlist,
                    maxParseSeconds: maxParseSeconds,
                    maxAnchorScans: maxAnchorScans
                )
            } catch {
                attempt += 1
                if !retryEnabled || attempt > maxRetries || !shouldRetry(error) {
                    throw error
                }
                await refreshServiceConnection()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func parseOnce(
        _ data: Data,
        allowlist: [String],
        maxParseSeconds: Double,
        maxAnchorScans: Int
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: serviceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: UntrustedParsingXPCProtocol.self)
            var didResume = false
            let resumeOnce: (Result<String, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            connection.interruptionHandler = {
                connection.invalidate()
                resumeOnce(.failure(UntrustedParsingError.unavailable))
            }

            connection.invalidationHandler = {
                resumeOnce(.failure(UntrustedParsingError.unavailable))
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                connection.invalidate()
                resumeOnce(.failure(UntrustedParsingError.unavailable))
            } as? UntrustedParsingXPCProtocol

            guard let proxy else {
                connection.invalidate()
                resumeOnce(.failure(UntrustedParsingError.unavailable))
                return
            }

            proxy.parse(
                data,
                allowlist: allowlist,
                maxParseSeconds: maxParseSeconds,
                maxAnchorScans: maxAnchorScans
            ) { result, error in
                connection.invalidate()
                if let error {
                    resumeOnce(.failure(UntrustedParsingError.remote(error)))
                } else {
                    resumeOnce(.success(result ?? ""))
                }
            }
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if case UntrustedParsingError.unavailable = error {
            return true
        }
        return false
    }

    private func refreshServiceConnection() async {
        let connection = NSXPCConnection(machServiceName: serviceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: UntrustedParsingXPCProtocol.self)
        connection.resume()
        connection.invalidate()
    }
}
