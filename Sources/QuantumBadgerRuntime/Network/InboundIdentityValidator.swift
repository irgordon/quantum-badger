import Foundation
import CryptoKit

final class InboundIdentityValidator {
    static let shared = InboundIdentityValidator()

    private static let accessGroup = "$(AppIdentifierPrefix)com.quantumbadger.shared"
    private static let serviceName = "com.quantumbadger.identity"
    private static let accountName = "scout.signature"
    private static let signaturePrefix = "v1"

    private let keychain: KeychainStore
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?
    private var hashThresholdBytes: Int = 128 * 1024

    private init() {
        self.keychain = KeychainStore(
            service: Self.serviceName,
            account: Self.accountName,
            accessGroup: Self.accessGroup
        )
    }

    func sign(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return signPayload(data)
    }

    func signPayload(_ data: Data) -> String? {
        guard let key = loadKey() else { return nil }
        let mode = signatureMode(for: data)
        let payload = mode == .hashed ? Hashing.sha256Data(data) : data
        let signature = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return "\(Self.signaturePrefix):\(mode.rawValue):\(Data(signature).base64EncodedString())"
    }

    func signPayloadZeroing(_ data: Data) -> String? {
        guard let keyData = try? keychain.loadOrCreateKeyData(),
              var zeroingKey = ZeroingSymmetricKey(data: keyData) else { return nil }
        let mode = signatureMode(for: data)
        let payload = mode == .hashed ? Hashing.sha256Data(data) : data
        do {
            let signature = try zeroingKey.withKey { key in
                HMAC<SHA256>.authenticationCode(for: payload, using: key)
            }
            return "\(Self.signaturePrefix):\(mode.rawValue):\(Data(signature).base64EncodedString())"
        } catch {
            return nil
        }
    }

    func verify(_ payload: String, signature: String) -> Bool {
        guard let data = payload.data(using: .utf8) else { return false }
        return verifyPayload(data, signature: signature)
    }

    func verifyPayload(_ data: Data, signature: String) -> Bool {
        guard let key = loadKey(),
              let parsed = parseSignature(signature) else { return false }
        let payload = parsed.mode == .hashed ? Hashing.sha256Data(data) : data
        let expected = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(expected) == parsed.signature
    }

    func signPrehashed(_ digest: Data) -> String? {
        guard let key = loadKey() else { return nil }
        let signature = HMAC<SHA256>.authenticationCode(for: digest, using: key)
        return "\(Self.signaturePrefix):\(SignatureMode.hashed.rawValue):\(Data(signature).base64EncodedString())"
    }

    func verifyPrehashed(_ digest: Data, signature: String) -> Bool {
        guard let key = loadKey(),
              let parsed = parseSignature(signature),
              parsed.mode == .hashed else { return false }
        let expected = HMAC<SHA256>.authenticationCode(for: digest, using: key)
        return Data(expected) == parsed.signature
    }

    func signFile(url: URL) -> String? {
        guard let digest = Hashing.sha256File(url) else { return nil }
        return signPrehashed(digest)
    }

    func verifyFile(url: URL, signature: String) -> Bool {
        guard let digest = Hashing.sha256File(url) else { return false }
        return verifyPrehashed(digest, signature: signature)
    }

    func updateHashThresholdBytes(_ value: Int) {
        lock.lock()
        hashThresholdBytes = value
        lock.unlock()
    }

    private func loadKey() -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey {
            return cachedKey
        }
        guard let key = try? keychain.loadOrCreateKey() else {
            return nil
        }
        cachedKey = key
        return key
    }

    private func signatureMode(for data: Data) -> SignatureMode {
        data.count > hashThresholdBytes ? .hashed : .raw
    }

    private func parseSignature(_ signature: String) -> (mode: SignatureMode, signature: Data)? {
        let parts = signature.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == Self.signaturePrefix else { return nil }
        guard let mode = SignatureMode(rawValue: parts[1]),
              let sigData = Data(base64Encoded: parts[2]) else { return nil }
        return (mode, sigData)
    }
}

private enum SignatureMode: String {
    case raw
    case hashed
}
