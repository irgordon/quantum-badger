import Foundation
import Network
import CryptoKit

enum NetworkClientError: Error, LocalizedError {
    case networkUnavailable
    case purposeDisabled
    case invalidURL
    case schemeNotAllowed
    case hostNotAllowed
    case ipLiteralBlocked
    case localNetworkBlocked
    case methodNotAllowed
    case pathNotAllowed
    case trustFailed
    case pinningFailed
    case responseTooLarge
    case redirectBlocked
    case circuitOpen

    var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "No internet connection."
        case .purposeDisabled: return "Network purpose is disabled."
        case .invalidURL: return "Invalid URL."
        case .schemeNotAllowed: return "Only HTTPS is allowed."
        case .hostNotAllowed: return "Host not allowlisted."
        case .ipLiteralBlocked: return "IP literal destinations are blocked."
        case .localNetworkBlocked: return "Local network destinations are blocked."
        case .methodNotAllowed: return "HTTP method not allowed."
        case .pathNotAllowed: return "Path not allowed."
        case .trustFailed: return "TLS trust evaluation failed."
        case .pinningFailed: return "Certificate pinning failed."
        case .responseTooLarge: return "Response exceeds size limits."
        case .redirectBlocked: return "Redirect blocked by policy."
        case .circuitOpen: return "Network circuit is open."
        }
    }
}

struct NetworkResponse {
    var data: Data
    var response: URLResponse
}

struct NetworkOpenCircuit: Identifiable {
    let host: String
    let until: Date

    var id: String { host }
}

struct NetworkCircuitTripRecord: Identifiable {
    let host: String
    let lastTrippedAt: Date

    var id: String { host }
}

actor NetworkClient: NSObject {
    private let policy: NetworkPolicyStore
    private let auditLog: AuditLog
    private let session: URLSession
    private var isNetworkAvailable: Bool = true
    private var breakers: [String: CircuitBreaker] = [:]
    private var lastTrip: [String: Date] = [:]
    private let breakerThreshold = 3
    private let breakerCooldownSeconds = 60

    init(policy: NetworkPolicyStore, auditLog: AuditLog) {
        self.policy = policy
        self.auditLog = auditLog

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30

        self.session = URLSession(configuration: configuration)
        super.init()
    }

    func fetch(_ request: URLRequest, purpose: NetworkPurpose) async throws -> NetworkResponse {
        guard isNetworkAvailable else {
            let decision = NetworkDecision(purpose: purpose, host: request.url?.host, endpoint: nil, reason: "Network unavailable")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Network unavailable"))
            throw NetworkClientError.networkUnavailable
        }
        let decision = try await evaluate(request: request, purpose: purpose)
        if let host = decision.host {
            let breaker = breaker(for: host)
            if !(await breaker.allowRequest()) {
                throw NetworkClientError.circuitOpen
            }
        }
        await auditLog.record(event: .networkAttempt(decision: decision, allowed: true))

        var timedRequest = request
        if let endpoint = decision.endpoint {
            timedRequest.timeoutInterval = endpoint.timeoutSeconds
        }
        timedRequest.setValue(defaultUserAgent(), forHTTPHeaderField: "User-Agent")
        timedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        timedRequest = await redactJSONPayloadIfNeeded(timedRequest, decision: decision)

        let maxBytes = decision.endpoint?.maxResponseBytes ?? 1_048_576
        
        let collector = StreamingDataCollector(
            maxBytes: maxBytes,
            auditLog: auditLog,
            decision: decision
        )
        // Need to ensure NetworkSessionDelegate handles non-endpoint case gracefully?
        // evaluate returns decision with endpoint != nil if host found.
        // If host not found, it throws.
        // So endpoint is safe to unwrap?
        // The evaluate method returns NetworkDecision which has endpoint optional in struct but guaranteed non-nil by logic if specific errors not thrown?
        // Let's check evaluate logic. logic throws if host not allowed.
        // So endpoint should be present.
        guard let endpoint = decision.endpoint else {
             throw NetworkClientError.hostNotAllowed // Should be caught by evaluate
        }
        
        // Wait, NetworkDecision struct has endpoint?
        // Yes.
        
        let delegate = NetworkSessionDelegate(
            policy: policy,
            purpose: purpose,
            endpoint: endpoint,
            auditLog: auditLog,
            collector: collector
        )
        do {
            let (data, response) = try await session.data(for: timedRequest, delegate: delegate)
            if let host = decision.host {
                let breaker = breaker(for: host)
                let transitioned = await breaker.recordSuccessAndReportTransition()
                if transitioned {
                    SystemEventBus.shared.post(.networkCircuitClosed(host: host))
                }
            }
            return NetworkResponse(data: data, response: response)
        } catch {
            if let host = decision.host {
                let tripped = await breaker(for: host).recordFailure()
                if tripped {
                    lastTrip[host] = Date()
                    await auditLog.record(event: .networkCircuitTripped(host: host, cooldownSeconds: breakerCooldownSeconds))
                    SystemEventBus.shared.post(.networkCircuitTripped(host: host, cooldownSeconds: breakerCooldownSeconds))
                    SystemEventBus.shared.post(.networkCircuitOpened(
                        host: host,
                        until: Date().addingTimeInterval(TimeInterval(breakerCooldownSeconds))
                    ))
                }
            }
            throw error
        }
    }

    func updateNetworkAvailability(_ isAvailable: Bool) {
        isNetworkAvailable = isAvailable
    }

    func openCircuitsSnapshot() async -> [NetworkOpenCircuit] {
        var results: [NetworkOpenCircuit] = []
        for (host, breaker) in breakers {
            let state = await breaker.stateSnapshot()
            if case .open(let until) = state {
                results.append(NetworkOpenCircuit(host: host, until: until))
            }
        }
        return results.sorted { $0.host < $1.host }
    }

    func lastTripSnapshot() -> [NetworkCircuitTripRecord] {
        lastTrip
            .map { NetworkCircuitTripRecord(host: $0.key, lastTrippedAt: $0.value) }
            .sorted { $0.lastTrippedAt > $1.lastTrippedAt }
    }

    private func breaker(for host: String) -> CircuitBreaker {
        if let existing = breakers[host] {
            return existing
        }
        let breaker = CircuitBreaker(
            failureThreshold: breakerThreshold,
            cooldownSeconds: TimeInterval(breakerCooldownSeconds),
            identifier: host
        )
        breakers[host] = breaker
        return breaker
    }

    private func defaultUserAgent() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(version.majorVersion)_\(version.minorVersion)"
        let arch = "Macintosh"
        return "QuantumBadger/1.0 (\(arch); Intel Mac OS X \(osString))"
    }

    private func redactJSONPayloadIfNeeded(_ request: URLRequest, decision: NetworkDecision) async -> URLRequest {
        guard let body = request.httpBody else { return request }
        guard shouldAttemptJSONRedaction(request, body: body) else { return request }
        let redacted = await NetworkPayloadRedactor.redactJSONPayload(body)
        guard redacted.didRedact else { return request }
        await auditLog.recordNetworkPayloadRedaction(decision: decision, before: body, after: redacted.data)
        var updated = request
        updated.httpBody = redacted.data
        return updated
    }

    private func shouldAttemptJSONRedaction(_ request: URLRequest, body: Data) -> Bool {
        guard !body.isEmpty else { return false }
        if let contentType = request.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if contentType.contains("application/json") || contentType.contains("+json") {
                return true
            }
        }
        // Fallback for JSON requests that omit Content-Type.
        // This avoids a second JSON parse before redaction.
        return firstNonWhitespaceByte(in: body) == 0x7B // {
            || firstNonWhitespaceByte(in: body) == 0x5B // [
    }

    private func firstNonWhitespaceByte(in data: Data) -> UInt8? {
        for byte in data {
            switch byte {
            case 0x20, 0x0A, 0x0D, 0x09:
                continue
            default:
                return byte
            }
        }
        return nil
    }

    // Payload redaction audit entries are now recorded via AuditLog to keep large data externalized.

    private func evaluate(request: URLRequest, purpose: NetworkPurpose) async throws -> NetworkDecision {
        let purposeEnabled = await policy.isPurposeEnabled(purpose)
        guard purposeEnabled else {
            let decision = NetworkDecision(purpose: purpose, host: nil, endpoint: nil, reason: "Purpose disabled")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Purpose disabled"))
            throw NetworkClientError.purposeDisabled
        }

        guard let url = request.url else {
            let decision = NetworkDecision(purpose: purpose, host: nil, endpoint: nil, reason: "Invalid URL")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Invalid URL"))
            throw NetworkClientError.invalidURL
        }

        guard url.scheme?.lowercased() == "https" else {
            let decision = NetworkDecision(purpose: purpose, host: url.host, endpoint: nil, reason: "Scheme blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Scheme blocked"))
            throw NetworkClientError.schemeNotAllowed
        }

        guard let host = url.host?.lowercased() else {
            let decision = NetworkDecision(purpose: purpose, host: nil, endpoint: nil, reason: "Host missing")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Host missing"))
            throw NetworkClientError.hostNotAllowed
        }

        if IPAddress.isLiteral(host) {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: nil, reason: "IP literal blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "IP literal blocked"))
            throw NetworkClientError.ipLiteralBlocked
        }

        if IPAddress.isLocalHost(host) {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: nil, reason: "Local host blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Local host blocked"))
            throw NetworkClientError.localNetworkBlocked
        }

        if let ipAddress = IPAddress.parse(host), IPAddress.isLocalNetwork(ipAddress) {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: nil, reason: "Local network blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Local network blocked"))
            throw NetworkClientError.localNetworkBlocked
        }

        let endpoints = await policy.endpointsSnapshot()
        guard let endpoint = endpoints.first(where: { $0.host == host }) else {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: nil, reason: "Host not allowlisted")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Host not allowlisted"))
            throw NetworkClientError.hostNotAllowed
        }
        if endpoint.requiredPurpose != purpose {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: endpoint, reason: "Purpose mismatch")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Purpose mismatch"))
            throw NetworkClientError.purposeDisabled
        }

        let method = (request.httpMethod ?? "GET").uppercased()
        if !endpoint.allowedMethods.contains(method) {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: endpoint, reason: "Method blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Method blocked"))
            throw NetworkClientError.methodNotAllowed
        }

        let path = url.path.isEmpty ? "/" : url.path
        let pathAllowed = endpoint.allowedPathPrefixes.contains(where: { path.hasPrefix($0) })
        if !pathAllowed {
            let decision = NetworkDecision(purpose: purpose, host: host, endpoint: endpoint, reason: "Path blocked")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Path blocked"))
            throw NetworkClientError.pathNotAllowed
        }

        return NetworkDecision(purpose: purpose, host: host, endpoint: endpoint, reason: "Allowed")
    }

    fileprivate func isPathAllowed(_ request: URLRequest, endpoint: NetworkEndpointPolicy) -> Bool {
        guard let url = request.url else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return endpoint.allowedPathPrefixes.contains(where: { path.hasPrefix($0) })
    }
}

final class NetworkSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let policy: NetworkPolicyStore
    private let purpose: NetworkPurpose
    private let endpoint: NetworkEndpointPolicy
    private let auditLog: AuditLog
    private let collector: StreamingDataCollector

    init(
        policy: NetworkPolicyStore,
        purpose: NetworkPurpose,
        endpoint: NetworkEndpointPolicy,
        auditLog: AuditLog,
        collector: StreamingDataCollector
    ) {
        self.policy = policy
        self.purpose = purpose
        self.endpoint = endpoint
        self.auditLog = auditLog
        self.collector = collector
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard endpoint.allowRedirects else {
            completionHandler(nil)
            Task { await auditLog.record(event: .networkRedirectBlocked(host: request.url?.host ?? "")) }
            return
        }
        guard let redirectHost = request.url?.host?.lowercased(), redirectHost == endpoint.host else {
            completionHandler(nil)
            Task { await auditLog.record(event: .networkRedirectBlocked(host: request.url?.host ?? "")) }
            return
        }
        let path = request.url?.path.isEmpty == false ? request.url?.path ?? "/" : "/"
        let pathAllowed = endpoint.allowedPathPrefixes.contains(where: { path.hasPrefix($0) })
        guard pathAllowed else {
            completionHandler(nil)
            Task { await auditLog.record(event: .networkRedirectBlocked(host: request.url?.host ?? "")) }
            return
        }

        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse,
           let length = http.value(forHTTPHeaderField: "Content-Length"),
           let lengthBytes = Int(length),
           lengthBytes > collector.maxBytes {
            Task { await collector.cancel(task: dataTask) } // Async cancel
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        Task { await collector.didReceive(data: data, task: dataTask) }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if !SecTrustEvaluateWithError(trust, nil) {
            let decision = NetworkDecision(purpose: purpose, host: challenge.protectionSpace.host, endpoint: endpoint, reason: "Trust failed")
            Task { await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Trust failed")) }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if endpoint.requiresAppleTrust {
            if !AppleTrustPolicy.isAppleHost(challenge.protectionSpace.host) {
                let decision = NetworkDecision(purpose: purpose, host: challenge.protectionSpace.host, endpoint: endpoint, reason: "Apple trust required")
                Task { await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Apple trust required")) }
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        if !endpoint.pinnedSPKIHashes.isEmpty {
            if !PinningPolicy.evaluate(trust: trust, pins: endpoint.pinnedSPKIHashes) {
                let decision = NetworkDecision(purpose: purpose, host: challenge.protectionSpace.host, endpoint: endpoint, reason: "Pinning failed")
                Task { await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Pinning failed")) }
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

final class StreamingDataCollector {
    let maxBytes: Int
    private let auditLog: AuditLog
    private let decision: NetworkDecision
    private var receivedBytes: Int = 0

    init(maxBytes: Int, auditLog: AuditLog, decision: NetworkDecision) {
        self.maxBytes = maxBytes
        self.auditLog = auditLog
        self.decision = decision
    }

    func didReceive(data: Data, task: URLSessionDataTask) async {
        receivedBytes += data.count
        if receivedBytes > maxBytes {
            await cancel(task: task)
        }
    }

    func cancel(task: URLSessionDataTask) async {
        let host = decision.host ?? "unknown"
        await auditLog.record(event: .networkResponseTruncated(host: host, reason: "Response too large"))
        // auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Response too large")) 
        // Logic: Should we record attempt denied? It was allowed initially.
        // We'll trust user logic or simplified version.
        SystemEventBus.shared.post(.networkResponseTruncated(host: host))
        task.cancel()
    }
}

enum IPAddress {
    static func isLiteral(_ host: String) -> Bool {
        IPv4Address(host) != nil || IPv6Address(host) != nil
    }

    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost"
    }

    static func parse(_ host: String) -> IPAddressValue? {
        if let ipv4 = IPv4Address(host) {
            return .ipv4(ipv4)
        }
        if let ipv6 = IPv6Address(host) {
            return .ipv6(ipv6)
        }
        return nil
    }

    static func isLocalNetwork(_ value: IPAddressValue) -> Bool {
        switch value {
        case .ipv4(let address):
            let bytes = [UInt8](address.rawValue)
            if bytes == [0, 0, 0, 0] {
                return true
            }
            switch bytes[0] {
            case 10:
                return true
            case 127:
                return true
            case 172:
                return bytes[1] >= 16 && bytes[1] <= 31
            case 192:
                return bytes[1] == 168
            case 169:
                return bytes[1] == 254
            default:
                return false
            }
        case .ipv6(let address):
            let bytes = [UInt8](address.rawValue)
            if bytes == [UInt8](repeating: 0, count: 16) {
                return true
            }
            if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 {
                return true
            }
            if bytes[0] == 0xfc || bytes[0] == 0xfd {
                return true
            }
            if bytes == [UInt8](repeating: 0, count: 15) + [1] {
                return true
            }
            return false
        }
    }
}

enum IPAddressValue {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)
}

enum AppleTrustPolicy {
    static func isAppleHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "apple.com"
            || host.hasSuffix(".apple.com")
            || host == "icloud.com"
            || host.hasSuffix(".icloud.com")
    }
}

enum PinningPolicy {
    static func evaluate(trust: SecTrust, pins: [String]) -> Bool {
        let pinSet = Set(pins.map { $0.lowercased() })
        let certificateCount = SecTrustGetCertificateCount(trust)
        for index in 0..<certificateCount {
            guard let cert = SecTrustGetCertificateAtIndex(trust, index) else { continue }
            guard let spkiHash = SPKIHashHelper.spkiHashBase64(from: cert) else { continue }
            if pinSet.contains(spkiHash.lowercased()) {
                return true
            }
        }
        return false
    }
}

enum SPKIHashHelper {
    static func spkiHashBase64(from certificate: SecCertificate) -> String? {
        if let spkiData = spkiData(from: certificate) {
            let digest = Hashing.sha256Data(spkiData)
            return digest.base64EncodedString()
        }
        return nil
    }

    private static func spkiData(from certificate: SecCertificate) -> Data? {
        let keys: [CFString] = [kSecOIDX509V1SubjectPublicKey]
        guard let values = SecCertificateCopyValues(certificate, keys as CFArray, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1SubjectPublicKey] as? [CFString: Any],
              let spki = entry[kSecPropertyKeyValue] as? Data else {
            return nil
        }
        return spki
    }
}

// Helper for Hashing, assuming it exists or needs to be here.
// User snippet uses `Hashing.sha256Data`.
// If not exists, I'll add a helper.
enum Hashing {
    static func sha256Data(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}
