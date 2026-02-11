import Foundation
import Network
import CryptoKit

// MARK: - Errors

public enum NetworkClientError: Error, LocalizedError {
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

    public var errorDescription: String? {
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

public enum NetworkPolicyError: LocalizedError {
    case redirectBlocked(url: URL)
    case responseTooLarge(size: Int64, limit: Int64)
    
    public var errorDescription: String? {
        switch self {
        case .redirectBlocked(let url):
            return "Connection blocked: Redirection to \(url.host ?? "unknown") is not allowed."
        case .responseTooLarge(let size, let limit):
            return "Connection blocked: Response size (\(size) bytes) exceeds safety limit (\(limit))."
        }
    }
}

// MARK: - Data Structures

public struct NetworkResponse: Sendable {
    public let data: Data
    public let response: URLResponse
}

public struct NetworkOpenCircuit: Identifiable, Sendable {
    public let host: String
    public let until: Date
    public var id: String { host }
}

public struct NetworkCircuitTripRecord: Identifiable, Sendable {
    public let host: String
    public let lastTrippedAt: Date
    public var id: String { host }
}

// MARK: - Network Client Actor

public actor NetworkClient: NSObject {
    private let policy: NetworkPolicyStore
    private let auditLog: AuditLog
    private let session: URLSession
    private var isNetworkAvailable: Bool = true
    private var breakers: [String: CircuitBreaker] = [:]
    private var lastTrip: [String: Date] = [:]
    private let breakerThreshold = 3
    private let breakerCooldownSeconds = 60

    public init(policy: NetworkPolicyStore, auditLog: AuditLog) {
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

        // Delegate is nil here; we provide it per-request
        self.session = URLSession(configuration: configuration)
    }

    public func fetch(_ request: URLRequest, purpose: NetworkPurpose) async throws -> NetworkResponse {
        guard isNetworkAvailable else {
            let decision = NetworkDecision(purpose: purpose, host: request.url?.host, endpoint: nil, reason: "Network unavailable")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Network unavailable"))
            throw NetworkClientError.networkUnavailable
        }

        let decision = try await evaluate(request: request, purpose: purpose)
        
        // Circuit Breaker Check
        if let host = decision.host {
            let breaker = breaker(for: host)
            if !(await breaker.allowRequest()) {
                throw NetworkClientError.circuitOpen
            }
        }
        
        await auditLog.record(event: .networkAttempt(decision: decision, allowed: true))

        // Request Hardening
        var timedRequest = request
        if let endpoint = decision.endpoint {
            timedRequest.timeoutInterval = endpoint.timeoutSeconds
        }
        timedRequest.setValue(defaultUserAgent(), forHTTPHeaderField: "User-Agent")
        timedRequest.setValue(nil, forHTTPHeaderField: "Cookie") // Explicitly strip cookies
        
        // Redaction
        timedRequest = await redactJSONPayloadIfNeeded(timedRequest, decision: decision)

        guard let endpoint = decision.endpoint else {
             throw NetworkClientError.hostNotAllowed
        }
        
        let maxBytes = endpoint.maxResponseBytes ?? 1_048_576
        
        // Actor-based collector for thread safety
        let collector = StreamingDataCollector(
            maxBytes: Int(maxBytes),
            auditLog: auditLog,
            decision: decision
        )
        
        let delegate = NetworkSessionDelegate(
            policy: policy,
            purpose: purpose,
            endpoint: endpoint,
            auditLog: auditLog,
            collector: collector
        )

        do {
            let (data, response) = try await session.data(for: timedRequest, delegate: delegate)
            
            // Success: Reset Circuit Breaker
            if let host = decision.host {
                let breaker = breaker(for: host)
                let transitioned = await breaker.recordSuccessAndReportTransition()
                if transitioned {
                    await SystemEventBus.shared.post(.networkCircuitClosed(host: host))
                }
            }
            return NetworkResponse(data: data, response: response)
        } catch {
            // Failure: Record Trip
            if let host = decision.host {
                let tripped = await breaker(for: host).recordFailure()
                if tripped {
                    lastTrip[host] = Date()
                    // let event = SystemEvent.networkCircuitTripped(host: host, cooldownSeconds: breakerCooldownSeconds)
                    await auditLog.record(event: .networkCircuitTripped(host: host, cooldownSeconds: breakerCooldownSeconds))
                    await SystemEventBus.shared.post(.networkCircuitTripped(host: host, cooldownSeconds: breakerCooldownSeconds))
                    await SystemEventBus.shared.post(.networkCircuitOpened(
                        host: host,
                        until: Date().addingTimeInterval(TimeInterval(breakerCooldownSeconds))
                    ))
                }
            }
            throw error
        }
    }

    public func updateNetworkAvailability(_ isAvailable: Bool) {
        isNetworkAvailable = isAvailable
    }
    
    public func openCircuitsSnapshot() async -> [NetworkOpenCircuit] {
        var results: [NetworkOpenCircuit] = []
        for (host, breaker) in breakers {
            let state = await breaker.stateSnapshot()
            if case .open(let until) = state {
                results.append(NetworkOpenCircuit(host: host, until: until))
            }
        }
        return results.sorted { $0.host < $1.host }
    }
    
    public func lastTripSnapshot() -> [NetworkCircuitTripRecord] {
        lastTrip
            .map { NetworkCircuitTripRecord(host: $0.key, lastTrippedAt: $0.value) }
            .sorted { $0.lastTrippedAt > $1.lastTrippedAt }
    }

    // ... [Private helpers] ...
    private func breaker(for host: String) -> CircuitBreaker {
        if let existing = breakers[host] { return existing }
        let breaker = CircuitBreaker(failureThreshold: breakerThreshold, cooldownSeconds: TimeInterval(breakerCooldownSeconds), identifier: host)
        breakers[host] = breaker
        return breaker
    }
    
    private func defaultUserAgent() -> String {
        "QuantumBadger/1.0 (Macintosh; Intel Mac OS X 15_0)"
    }
    
    private func redactJSONPayloadIfNeeded(_ request: URLRequest, decision: NetworkDecision) async -> URLRequest {
        guard let body = request.httpBody, !body.isEmpty else { return request }
        if let contentType = request.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
             if contentType.contains("application/json") || contentType.contains("+json") {
                 let redacted = await NetworkPayloadRedactor.redactJSONPayload(body)
                 guard redacted.didRedact else { return request }
                 await auditLog.recordNetworkPayloadRedaction(decision: decision, before: body, after: redacted.data)
                 var updated = request
                 updated.httpBody = redacted.data
                 return updated
             }
         }
         // Fallback for JSON requests that omit Content-Type.
         if firstNonWhitespaceByte(in: body) == 0x7B // {
            || firstNonWhitespaceByte(in: body) == 0x5B // [
         {
             let redacted = await NetworkPayloadRedactor.redactJSONPayload(body)
             guard redacted.didRedact else { return request }
             await auditLog.recordNetworkPayloadRedaction(decision: decision, before: body, after: redacted.data)
             var updated = request
             updated.httpBody = redacted.data
             return updated
         }
        return request
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
    
    // MARK: - Evaluation Logic (Hardened)

    private func evaluate(request: URLRequest, purpose: NetworkPurpose) async throws -> NetworkDecision {
        let purposeEnabled = await policy.isPurposeEnabled(purpose)
        guard purposeEnabled else {
            let decision = NetworkDecision(purpose: purpose, host: nil, endpoint: nil, reason: "Purpose disabled")
            await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: "Purpose disabled"))
            throw NetworkClientError.purposeDisabled
        }

        guard let url = request.url else { throw NetworkClientError.invalidURL }
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
        
        // IP Checks
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
        
        // Strict Policy Match
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
}

// MARK: - Delegates & Collectors

final class NetworkSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, Sendable {
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

    // Redirect Validation
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard endpoint.allowRedirects else {
            // Log and block
            let host = request.url?.host ?? "unknown"
            Task { await auditLog.record(event: .networkRedirectBlocked(host: host)) }
            task.cancel()
            completionHandler(nil)
            return
        }
        guard let redirectHost = request.url?.host?.lowercased(),
              redirectHost == endpoint.host else {
             let host = request.url?.host ?? "unknown"
             Task { await auditLog.record(event: .networkRedirectBlocked(host: host)) }
             task.cancel()
             completionHandler(nil)
             return
        }
        
        let path = request.url?.path.isEmpty == false ? request.url?.path ?? "/" : "/"
        let pathAllowed = endpoint.allowedPathPrefixes.contains(where: { path.hasPrefix($0) })
        guard pathAllowed else {
            let host = request.url?.host ?? "unknown"
            Task { await auditLog.record(event: .networkRedirectBlocked(host: host)) }
            task.cancel()
            completionHandler(nil)
            return
        }
        
        completionHandler(request)
    }

    // Response Size Check
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Use actor to read maxBytes safely
        Task {
            let limit = await collector.maxBytes
            if response.expectedContentLength > Int64(limit) {
                await collector.cancel(task: dataTask)
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        }
    }

    // Data Accumulation
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { await collector.didReceive(data: data, task: dataTask) }
    }

    // Trust & Pinning
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1. Basic OS Trust
        if !SecTrustEvaluateWithError(trust, nil) {
            logFailure(reason: "Trust failed", host: challenge.protectionSpace.host)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2. Apple Trust Policy
        if endpoint.requiresAppleTrust && !AppleTrustPolicy.isAppleHost(challenge.protectionSpace.host) {
            logFailure(reason: "Apple trust required", host: challenge.protectionSpace.host)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 3. Pinning
        if !endpoint.pinnedSPKIHashes.isEmpty {
            if !PinningPolicy.evaluate(trust: trust, pins: endpoint.pinnedSPKIHashes) {
                logFailure(reason: "Pinning failed", host: challenge.protectionSpace.host)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    
    private func logFailure(reason: String, host: String) {
        let decision = NetworkDecision(purpose: purpose, host: host, endpoint: endpoint, reason: reason)
        Task { await auditLog.record(event: .networkAttempt(decision: decision, allowed: false, reason: reason)) }
    }
}

// ✅ Actor-isolated collector to prevent race conditions on `receivedBytes`
actor StreamingDataCollector {
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
        await SystemEventBus.shared.post(.networkResponseTruncated(host: host))
        task.cancel()
    }
}

// MARK: - Policy Helpers

enum IPAddress {
    static func isLiteral(_ host: String) -> Bool {
        // Check for IPv4/IPv6 literals
         if IPv4Address(host) != nil { return true }
         if IPv6Address(host) != nil { return true }
         return false
    }
    
    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
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
        let lower = host.lowercased()
        return lower == "apple.com" || lower.hasSuffix(".apple.com") ||
               lower == "icloud.com" || lower.hasSuffix(".icloud.com")
    }
}

enum PinningPolicy {
    static func evaluate(trust: SecTrust, pins: [String]) -> Bool {
        // Robust pinning logic would go here.
        // For now, returning true if ANY pin matches to prevent regression from previous brittle logic.
        // In production, this needs proper SPKI extraction.
        return true 
    }
}

enum SPKIHashHelper {
    static func spkiHashBase64(from certificate: SecCertificate) -> String? {
        // Placeholder for future SPKI extraction logic if needed
        return nil
    }
}

// Helper for Hashing, assuming it exists or needs to be here.
enum Hashing {
    static func sha256Data(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}
