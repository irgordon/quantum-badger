import Foundation
import Security
import CryptoKit
import LocalAuthentication

final class KeychainStore {
    private let service: String
    private let account: String
    private let wrappedAccount: String
    private let secureEnclaveTag: Data
    private let secretsService: String

    init(service: String = "com.quantumbadger.vault", account: String = "primary") {
        self.service = service
        self.account = account
        self.wrappedAccount = "\(account).wrapped"
        self.secureEnclaveTag = "\(service).kek".data(using: .utf8) ?? Data()
        self.secretsService = "\(service).secrets"
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        if let wrapped = try loadKeyData(account: wrappedAccount),
           let unwrapped = try decryptWrappedKeyData(wrapped) {
            return SymmetricKey(data: unwrapped)
        }

        if let data = try loadKeyData(account: account) {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        if let wrapped = try encryptKeyDataForSecureEnclave(data) {
            try saveKeyData(wrapped, account: wrappedAccount)
            return key
        }

        try saveKeyData(data, account: account)
        return key
    }

    private func loadKeyData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
        return item as? Data
    }

    private func saveKeyData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try updateKeyData(data, account: account)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private func updateKeyData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    func saveSecret(_ value: String, label: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try updateSecret(data, label: label)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    func loadSecret(label: String, context: LAContext? = nil) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: label,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        query[kSecUseOperationPrompt as String] = "Authenticate to access your secure item."

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: label
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandled(status: status)
        }
    }

    func saveSecretOwner(_ userIdentifier: String, label: String) throws {
        try saveSecret(userIdentifier, label: "\(label).owner")
    }

    func loadSecretOwner(label: String) throws -> String? {
        try loadSecret(label: "\(label).owner")
    }

    func loadSecretIfOwner(label: String, userIdentifier: String, context: LAContext? = nil) throws -> String? {
        guard let owner = try loadSecretOwner(label: label), owner == userIdentifier else {
            return nil
        }
        return try loadSecret(label: label, context: context)
    }

    func deleteSecretOwner(label: String) throws {
        try deleteSecret(label: "\(label).owner")
    }

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        let wrappedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wrappedAccount
        ]
        SecItemDelete(wrappedQuery as CFDictionary)
    }

    private func updateSecret(_ data: Data, label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretsService,
            kSecAttrAccount as String: label
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private func encryptKeyDataForSecureEnclave(_ data: Data) throws -> Data? {
        guard let keyPair = try loadOrCreateSecureEnclaveKey() else {
            return nil
        }
        let publicKey = keyPair.publicKey
        let algorithm = selectEncryptionAlgorithm(for: publicKey, operation: .encrypt)
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &error) else {
            if let error = error?.takeRetainedValue() {
                AppLogger.security.error("Secure Enclave encryption failed: \(error.localizedDescription, privacy: .private)")
            }
            return nil
        }
        return encrypted as Data
    }

    private func decryptWrappedKeyData(_ wrapped: Data) throws -> Data? {
        guard let keyPair = try loadOrCreateSecureEnclaveKey() else {
            return nil
        }
        let privateKey = keyPair.privateKey
        let algorithm = selectEncryptionAlgorithm(for: privateKey, operation: .decrypt)
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(privateKey, algorithm, wrapped as CFData, &error) else {
            if let error = error?.takeRetainedValue() {
                AppLogger.security.error("Secure Enclave decryption failed: \(error.localizedDescription, privacy: .private)")
            }
            return nil
        }
        return decrypted as Data
    }

    private func loadOrCreateSecureEnclaveKey() throws -> (privateKey: SecKey, publicKey: SecKey)? {
        if let existing = try loadSecureEnclavePrivateKey() {
            return (existing, SecKeyCopyPublicKey(existing))
        }

        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        ) else {
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: secureEnclaveTag,
                kSecAttrAccessControl as String: access
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                AppLogger.security.error("Secure Enclave key creation failed: \(error.localizedDescription, privacy: .private)")
            }
            return nil
        }

        return (privateKey, SecKeyCopyPublicKey(privateKey))
    }

    private func loadSecureEnclavePrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: secureEnclaveTag,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
        return item as! SecKey
    }

    private func selectEncryptionAlgorithm(for key: SecKey, operation: SecKeyOperationType) -> SecKeyAlgorithm {
        let preferred: [SecKeyAlgorithm] = [
            .eciesEncryptionStandardX963SHA256AESGCM,
            .eciesEncryptionCofactorX963SHA256AESGCM
        ]
        for algorithm in preferred {
            if SecKeyIsAlgorithmSupported(key, operation, algorithm) {
                return algorithm
            }
        }
        return .eciesEncryptionStandardX963SHA256AESGCM
    }
}

enum KeychainError: Error {
    case unhandled(status: OSStatus)
}
