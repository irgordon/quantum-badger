import Foundation
import Security
import CryptoKit

/// Structural sovereignty through Secure Enclave–backed identity.
///
/// `IdentityFingerprinter` creates or retrieves a persistent **NIST P‑256**
/// key inside the Secure Enclave and derives a **Stable Identity Fingerprint**
/// by hashing the public key's raw bytes with SHA‑256. The fingerprint is
/// idempotent across iCloud sync and keychain wrapping churn because it is
/// derived from the key material itself, not from keychain metadata.
///
/// ## Key Rotation Detection
///
/// The last‑known fingerprint is persisted in the keychain under a separate
/// service tag. On every access the current fingerprint is compared against
/// the stored reference. If they diverge, ``SecurityGateError/keyRotated``
/// is returned, forcing a re‑audit / re‑onboarding flow.
public struct IdentityFingerprinter: Sendable {

    // MARK: - Constants

    private static let keyTag = "com.quantumbadger.identity.p256"
    private static let fingerprintService = "com.quantumbadger.identity.fingerprint"
    private static let fingerprintAccount = "stable-fingerprint"

    // MARK: - Public API

    /// Retrieve (or create) the Stable Identity Fingerprint.
    ///
    /// - Returns: A 64‑character hex string representing the SHA‑256 hash of
    ///   the Secure Enclave public key's raw representation.
    /// - Throws: ``SecurityGateError`` on enclave or keychain failures.
    public func fingerprint() throws -> String {
        let publicKey = try retrieveOrCreatePublicKey()
        let currentFingerprint = try deriveFingerprint(from: publicKey)

        // Compare against last‑known fingerprint.
        if let stored = try storedFingerprint() {
            guard stored == currentFingerprint else {
                throw SecurityGateError.keyRotated
            }
            return currentFingerprint
        }

        // First run — persist the fingerprint.
        try storeFingerprint(currentFingerprint)
        return currentFingerprint
    }

    /// Force‑update the stored fingerprint after a successful re‑onboarding.
    public func acceptCurrentFingerprint() throws {
        let publicKey = try retrieveOrCreatePublicKey()
        let current = try deriveFingerprint(from: publicKey)
        try storeFingerprint(current)
    }

    // MARK: - Secure Enclave Key Management

    private func retrieveOrCreatePublicKey() throws -> SecKey {
        if let existing = try retrievePrivateKey() {
            guard let pub = SecKeyCopyPublicKey(existing) else {
                throw SecurityGateError.publicKeyExportFailed
            }
            return pub
        }
        return try createEnclaveKey()
    }

    private func retrievePrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            // item is guaranteed non‑nil here by the Security framework
            // contract when errSecSuccess is returned with kSecReturnRef.
            return (item as! SecKey) // swiftlint:disable:this force_cast
        case errSecItemNotFound:
            return nil
        default:
            throw SecurityGateError.enclaveUnavailable
        }
    }

    private func createEnclaveKey() throws -> SecKey {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &accessError
        ) else {
            throw SecurityGateError.enclaveUnavailable
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: access,
            ] as [String: Any],
        ]

        var createError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(
            attributes as CFDictionary,
            &createError
        ) else {
            throw SecurityGateError.enclaveUnavailable
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecurityGateError.publicKeyExportFailed
        }
        return publicKey
    }

    // MARK: - Fingerprint Derivation

    private func deriveFingerprint(from publicKey: SecKey) throws -> String {
        var exportError: Unmanaged<CFError>?
        guard let rawData = SecKeyCopyExternalRepresentation(
            publicKey,
            &exportError
        ) as Data? else {
            throw SecurityGateError.publicKeyExportFailed
        }
        let digest = SHA256.hash(data: rawData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Signing

    /// Sign data using the Secure Enclave private key (NIST P‑256).
    ///
    /// - Parameter data: The data digest to sign.
    /// - Returns: The DER‑encoded ECDSA signature.
    /// - Throws: ``SecurityGateError`` if the private key cannot be accessed or signing fails.
    public func sign(_ data: Data) throws -> Data {
        guard let privateKey = try retrievePrivateKey() else {
            throw SecurityGateError.enclaveUnavailable
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw SecurityGateError.signingFailed
        }
        return signature
    }

    /// Verify a signature against the Secure Enclave public key.
    public func verify(signature: Data, for data: Data) -> Bool {
        guard let publicKey = try? retrieveOrCreatePublicKey() else { return false }
        
        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            &error
        )
        return result
    }

    // MARK: - Fingerprint Persistence

    private func storedFingerprint() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.fingerprintService,
            kSecAttrAccount as String: Self.fingerprintAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                throw SecurityGateError.keychainOperationFailed
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            throw SecurityGateError.keychainOperationFailed
        }
    }

    private func storeFingerprint(_ value: String) throws {
        let data = Data(value.utf8)

        // Try update first.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.fingerprintService,
            kSecAttrAccount as String: Self.fingerprintAccount,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(
            updateQuery as CFDictionary,
            updateAttrs as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecurityGateError.keychainOperationFailed
            }
        } else if updateStatus != errSecSuccess {
            throw SecurityGateError.keychainOperationFailed
        }
    }
}
