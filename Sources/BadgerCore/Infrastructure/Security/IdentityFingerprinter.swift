import Foundation
import Security
import CryptoKit

/// Structural sovereignty through Secure Enclave–backed identity.
public struct IdentityFingerprinter: Sendable {

    // MARK: - Constants

    private static let keyTag = "com.quantumbadger.identity.p256"
    private static let fingerprintService = "com.quantumbadger.identity.fingerprint"
    private static let fingerprintAccount = "stable-fingerprint"

    // MARK: - Public API

    public func fingerprint() throws -> String {
        let publicKey = try retrieveOrCreatePublicKey()
        let currentFingerprint = try deriveFingerprint(from: publicKey)

        if let stored = try storedFingerprint() {
            guard stored == currentFingerprint else {
                throw SecurityGateError.keyRotated
            }
            return currentFingerprint
        }

        try storeFingerprint(currentFingerprint)
        return currentFingerprint
    }

    public func acceptCurrentFingerprint() throws {
        let publicKey = try retrieveOrCreatePublicKey()
        let current = try deriveFingerprint(from: publicKey)
        try storeFingerprint(current)
    }

    // MARK: - Secure Enclave Key Management

    private func retrieveOrCreatePublicKey() throws -> SecKey {
        // 1. Try to get existing private key reference
        if let privateKey = try retrievePrivateKey() {
            // 2. Derive public key from it
            guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                throw SecurityGateError.publicKeyExportFailed
            }
            return publicKey
        }
        // 3. Create new if missing
        return try createEnclaveKey()
    }

    private func retrievePrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecurityGateError.enclaveUnavailable }
        
        // CFTypeRef is not automatically bridged to SecKey in all contexts,
        // but guaranteed by kSecReturnRef + kSecClassKey.
        return (item as! SecKey)
    }

    private func createEnclaveKey() throws -> SecKey {
        // Create Access Control: User must unlock device to use private key.
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &error
        ) else {
            throw SecurityGateError.enclaveUnavailable
        }

        // Attributes for the PRIVATE key (stored in Enclave)
        let privateKeyAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
            kSecAttrAccessControl as String: access
        ]

        // Top-level attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateKeyAttrs
        ]

        var createError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &createError) else {
            throw SecurityGateError.enclaveUnavailable
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecurityGateError.publicKeyExportFailed
        }
        return publicKey
    }

    // MARK: - Fingerprint Derivation

    private func deriveFingerprint(from publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        // Exports ANSI X9.63 format (04 || X || Y)
        guard let rawData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SecurityGateError.publicKeyExportFailed
        }
        
        let digest = SHA256.hash(data: rawData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Signing

    /// Sign data using the Secure Enclave private key.
    ///
    /// - Parameter data: The **raw message data** to sign. The Secure Enclave
    ///   will compute the SHA-256 hash internally.
    /// - Returns: The DER-encoded ECDSA signature.
    public func sign(_ data: Data) throws -> Data {
        guard let privateKey = try retrievePrivateKey() else {
            throw SecurityGateError.enclaveUnavailable
        }

        var error: Unmanaged<CFError>?
        // Logic fix: Ensure algorithm matches input type (Message vs Digest)
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256, // Hashes the input data
            data as CFData,
            &error
        ) as Data? else {
            throw SecurityGateError.signingFailed
        }
        return signature
    }

    public func verify(signature: Data, for data: Data) -> Bool {
        guard let publicKey = try? retrieveOrCreatePublicKey() else { return false }
        
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            &error
        )
    }

    // MARK: - Fingerprint Persistence

    private func storedFingerprint() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.fingerprintService,
            kSecAttrAccount as String: Self.fingerprintAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8)
        else {
            throw SecurityGateError.keychainOperationFailed
        }
        return str
    }

    private func storeFingerprint(_ value: String) throws {
        let data = Data(value.utf8)
        
        // Define base attributes
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.fingerprintService,
            kSecAttrAccount as String: Self.fingerprintAccount
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        // Attempt update
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        
        if status == errSecItemNotFound {
            // Add if missing
            var newItem = query
            newItem[kSecValueData as String] = data
            // Optional: Accessible only when unlocked to match key security
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecurityGateError.keychainOperationFailed }
        } else if status != errSecSuccess {
            throw SecurityGateError.keychainOperationFailed
        }
    }
}
