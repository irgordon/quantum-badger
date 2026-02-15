import Foundation
import Security
import CryptoKit

// MARK: - Key Manager Errors

/// Errors that can occur during key management operations
public enum KeyManagerError: Error, Sendable {
    case itemNotFound
    case itemAlreadyExists
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deletionFailed(OSStatus)
    case invalidData
    case secureEnclaveNotAvailable
    case biometricsNotAvailable
    case keyGenerationFailed
    case cryptoOperationFailed(String)
}

// MARK: - Supported AI Providers

/// Type alias for backward compatibility - CloudProvider is defined in ShadowRouterTypes
public typealias AIProvider = CloudProvider

extension CloudProvider {
    /// The service name used for Keychain storage
    var serviceName: String {
        "com.quantumbadger.tokens.\(rawValue.lowercased())"
    }
}

// MARK: - Secure Enclave Key

/// Represents a key stored in the Secure Enclave
/// @unchecked Sendable is used because SecKey is thread-safe but not marked as Sendable in the SDK
public struct SecureEnclaveKey: @unchecked Sendable {
    public let publicKey: SecKey
    public let privateKey: SecKey
    
    public init(publicKey: SecKey, privateKey: SecKey) {
        self.publicKey = publicKey
        self.privateKey = privateKey
    }
}

// MARK: - CoreFoundation Type Bridge

public protocol CoreFoundationTypeBridge {
    associatedtype Value: AnyObject
    static var typeID: CFTypeID { get }
}

public extension CoreFoundationTypeBridge {
    static func cast(_ object: AnyObject) -> Value? {
        guard CFGetTypeID(object) == typeID else {
            return nil
        }
        return unsafeDowncast(object, to: Value.self)
    }
}

public enum SecKeyTypeBridge: CoreFoundationTypeBridge {
    public typealias Value = SecKey
    public static var typeID: CFTypeID { SecKeyGetTypeID() }
}

// MARK: - Keychain Query Factory

private struct KeychainQueryFactory {
    let accessGroup: String?
    
    func tokenStoreQuery(provider: AIProvider, tokenData: Data) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
    
    func tokenRetrieveQuery(provider: AIProvider) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
    
    func tokenDeleteQuery(provider: AIProvider) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
    
    func tokenExistsQuery(provider: AIProvider) -> [String: Any] {
        var query = tokenDeleteQuery(provider: provider)
        query[kSecReturnData as String] = false
        return query
    }
    
    func secureEnclaveAvailabilityAttributes() -> [String: Any] {
        [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
    }
    
    func secureEnclaveGenerationAttributes(tag: Data) -> [String: Any] {
        [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
    }
    
    func keyPairQuery(tag: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
    }
    
    func keyPairDeleteQuery(tag: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
    }
}

// MARK: - Hardware Abstraction Layer

public protocol KeyProvider: Sendable {
    func isAvailable() -> Bool
    func generateKey(attributes: [String: Any]) throws -> SecKey
}

public protocol StorageProvider: Sendable {
    func store(query: [String: Any]) throws
    func fetch(query: [String: Any]) throws -> AnyObject
    func delete(query: [String: Any]) throws
}

public struct SecureEnclaveKeyProvider: KeyProvider {
    public init() {}
    
    public func isAvailable() -> Bool {
        guard #available(macOS 10.15, *) else {
            return false
        }
        return true
    }
    
    public func generateKey(attributes: [String: Any]) throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyManagerError.keyGenerationFailed
        }
        return key
    }
}

public struct KeychainStorageProvider: StorageProvider {
    public init() {}
    
    public func store(query: [String: Any]) throws {
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeyManagerError.itemAlreadyExists
        default:
            throw KeyManagerError.saveFailed(status)
        }
    }
    
    public func fetch(query: [String: Any]) throws -> AnyObject {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let result else {
                throw KeyManagerError.invalidData
            }
            return result
        case errSecItemNotFound:
            throw KeyManagerError.itemNotFound
        default:
            throw KeyManagerError.retrievalFailed(status)
        }
    }
    
    public func delete(query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeyManagerError.itemNotFound
        default:
            throw KeyManagerError.deletionFailed(status)
        }
    }
}

// MARK: - Cipher Mechanism

private enum Cipher {
    static let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
    
    typealias Operation = (
        SecKey,
        SecKeyAlgorithm,
        CFData,
        UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> CFData?
    
    static func perform(
        _ operation: Operation,
        on key: SecKey,
        data: Data
    ) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let resultData = operation(key, algorithm, data as CFData, &error) else {
            throw resolveFailure(error)
        }
        return resultData as Data
    }
    
    private static func resolveFailure(_ error: Unmanaged<CFError>?) -> KeyManagerError {
        guard let cfError = error?.takeRetainedValue() else {
            return .invalidData
        }
        let description = CFErrorCopyDescription(cfError) as String
        return .cryptoOperationFailed(description)
    }
}

// MARK: - Key Manager

/// Actor responsible for managing cryptographic keys and API tokens using the Secure Enclave
public actor KeyManager {
    
    // MARK: - Properties
    
    private let factory: KeychainQueryFactory
    private let keyProvider: any KeyProvider
    private let storageProvider: any StorageProvider
    
    // MARK: - Initialization
    
    /// Initialize the KeyManager
    /// - Parameter accessGroup: Optional shared access group for Keychain items
    public init(
        accessGroup: String? = nil,
        keyProvider: any KeyProvider = SecureEnclaveKeyProvider(),
        storageProvider: any StorageProvider = KeychainStorageProvider()
    ) {
        self.factory = KeychainQueryFactory(accessGroup: accessGroup)
        self.keyProvider = keyProvider
        self.storageProvider = storageProvider
    }
    
    // MARK: - API Token Management
    
    /// Store an API token for a specific provider in the Secure Enclave-protected Keychain
    /// - Parameters:
    ///   - token: The API token to store
    ///   - provider: The AI provider this token belongs to
    public func storeToken(_ token: String, for provider: AIProvider) async throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        // First, delete any existing token for this provider
        try? await deleteToken(for: provider)
        
        let query = factory.tokenStoreQuery(provider: provider, tokenData: tokenData)
        try storageProvider.store(query: query)
    }
    
    /// Retrieve an API token for a specific provider
    /// - Parameter provider: The AI provider to retrieve the token for
    /// - Returns: The stored API token
    public func retrieveToken(for provider: AIProvider) async throws -> String {
        let query = factory.tokenRetrieveQuery(provider: provider)
        let result = try storageProvider.fetch(query: query)
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        return token
    }
    
    /// Delete the stored API token for a specific provider
    /// - Parameter provider: The AI provider to delete the token for
    public func deleteToken(for provider: AIProvider) async throws {
        let query = factory.tokenDeleteQuery(provider: provider)
        do {
            try storageProvider.delete(query: query)
        } catch let error as KeyManagerError {
            guard case .itemNotFound = error else {
                throw error
            }
        }
    }
    
    /// Check if a token exists for a provider
    /// - Parameter provider: The AI provider to check
    /// - Returns: True if a token exists
    public func hasToken(for provider: AIProvider) async -> Bool {
        let query = factory.tokenExistsQuery(provider: provider)
        do {
            _ = try storageProvider.fetch(query: query)
            return true
        } catch {
            return false
        }
    }
    
    /// List all providers that have stored tokens
    /// - Returns: Array of providers with stored tokens
    public func listStoredProviders() async -> [AIProvider] {
        var providers: [AIProvider] = []
        
        for provider in AIProvider.allCases {
            if await hasToken(for: provider) {
                providers.append(provider)
            }
        }
        
        return providers
    }
    
    // MARK: - Secure Enclave Key Generation
    
    /// Check if Secure Enclave is available on this device
    public func isSecureEnclaveAvailable() -> Bool {
        keyProvider.isAvailable()
    }
    
    /// Generate a new P-256 key pair in the Secure Enclave
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The generated key pair
    public func generateSecureEnclaveKeyPair(identifier: String) async throws -> SecureEnclaveKey {
        guard isSecureEnclaveAvailable() else { throw KeyManagerError.secureEnclaveNotAvailable }
        let tag = try resolveTag(identifier)
        
        try? await deleteSecureEnclaveKey(identifier: identifier)
        
        let attributes = factory.secureEnclaveGenerationAttributes(tag: tag)
        let privateKey = try keyProvider.generateKey(attributes: attributes)
        return try resolveSecureKey(from: privateKey)
    }
    
    /// Retrieve an existing Secure Enclave key pair
    /// - Parameter identifier: The identifier of the key to retrieve
    /// - Returns: The key pair if found
    public func retrieveSecureEnclaveKey(identifier: String) async throws -> SecureEnclaveKey {
        let tag = try resolveTag(identifier)
        
        let query = factory.keyPairQuery(tag: tag)
        let result = try storageProvider.fetch(query: query)
        guard let privateKey = SecKeyTypeBridge.cast(result) else {
            throw KeyManagerError.invalidData
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyManagerError.invalidData
        }
        
        return SecureEnclaveKey(publicKey: publicKey, privateKey: privateKey)
    }
    
    /// Delete a Secure Enclave key pair
    /// - Parameter identifier: The identifier of the key to delete
    public func deleteSecureEnclaveKey(identifier: String) async throws {
        let tag = try resolveTag(identifier)
        
        let query = factory.keyPairDeleteQuery(tag: tag)
        do {
            try storageProvider.delete(query: query)
        } catch let error as KeyManagerError {
            guard case .itemNotFound = error else {
                throw error
            }
        }
    }
    
    // MARK: - Key Resolution Helpers
    
    private func resolveSecureKey(from privateKey: SecKey) throws -> SecureEnclaveKey {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyManagerError.keyGenerationFailed
        }
        return SecureEnclaveKey(publicKey: publicKey, privateKey: privateKey)
    }
    
    private func resolveTag(_ identifier: String) throws -> Data {
        guard let tag = identifier.data(using: .utf8) else {
            throw KeyManagerError.invalidData
        }
        return tag
    }
    
    // MARK: - Encryption/Decryption Helpers
    
    /// Encrypt data using a Secure Enclave public key
    /// - Parameters:
    ///   - data: The data to encrypt
    ///   - publicKey: The public key to encrypt with
    /// - Returns: The encrypted data
    public func encrypt(data: Data, using publicKey: SecKey) throws -> Data {
        try Cipher.perform(SecKeyCreateEncryptedData, on: publicKey, data: data)
    }
    
    /// Decrypt data using a Secure Enclave private key
    /// - Parameters:
    ///   - encryptedData: The encrypted data
    ///   - privateKey: The private key to decrypt with
    /// - Returns: The decrypted data
    public func decrypt(data encryptedData: Data, using privateKey: SecKey) throws -> Data {
        try Cipher.perform(SecKeyCreateDecryptedData, on: privateKey, data: encryptedData)
    }
}
