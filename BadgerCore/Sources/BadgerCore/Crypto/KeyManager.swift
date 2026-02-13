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

// MARK: - Key Manager

/// Actor responsible for managing cryptographic keys and API tokens using the Secure Enclave
public actor KeyManager {
    
    // MARK: - Properties
    
    private let accessGroup: String?
    
    // MARK: - Initialization
    
    /// Initialize the KeyManager
    /// - Parameter accessGroup: Optional shared access group for Keychain items
    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
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
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeyManagerError.saveFailed(status)
        }
    }
    
    /// Retrieve an API token for a specific provider
    /// - Parameter provider: The AI provider to retrieve the token for
    /// - Returns: The stored API token
    public func retrieveToken(for provider: AIProvider) async throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeyManagerError.itemNotFound
            }
            throw KeyManagerError.retrievalFailed(status)
        }
        
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        return token
    }
    
    /// Delete the stored API token for a specific provider
    /// - Parameter provider: The AI provider to delete the token for
    public func deleteToken(for provider: AIProvider) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecUseDataProtectionKeychain as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.deletionFailed(status)
        }
    }
    
    /// Check if a token exists for a provider
    /// - Parameter provider: The AI provider to check
    /// - Returns: True if a token exists
    public func hasToken(for provider: AIProvider) async -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.serviceName,
            kSecAttrAccount as String: "api_token",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: false
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
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
        // Check if the device supports Secure Enclave (all Apple Silicon Macs do)
        guard #available(macOS 10.15, *) else {
            return false
        }
        
        // Attempt to create a test key to verify Secure Enclave availability
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            return false
        }
        
        return true
    }
    
    /// Generate a new P-256 key pair in the Secure Enclave
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The generated key pair
    public func generateSecureEnclaveKeyPair(identifier: String) async throws -> SecureEnclaveKey {
        guard isSecureEnclaveAvailable() else {
            throw KeyManagerError.secureEnclaveNotAvailable
        }
        
        // Remove any existing key with this identifier
        try? await deleteSecureEnclaveKey(identifier: identifier)
        
        guard let tag = identifier.data(using: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyManagerError.keyGenerationFailed
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyManagerError.keyGenerationFailed
        }
        
        return SecureEnclaveKey(publicKey: publicKey, privateKey: privateKey)
    }
    
    /// Retrieve an existing Secure Enclave key pair
    /// - Parameter identifier: The identifier of the key to retrieve
    /// - Returns: The key pair if found
    public func retrieveSecureEnclaveKey(identifier: String) async throws -> SecureEnclaveKey {
        guard let tag = identifier.data(using: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeyManagerError.itemNotFound
            }
            throw KeyManagerError.retrievalFailed(status)
        }
        
        // AUDIT FIX: Handle CoreFoundation type safely
        // SecKey is a CFTypeRef; we verify the type by checking the result is not nil
        guard let cfResult = result else {
            throw KeyManagerError.invalidData
        }
        // CoreFoundation bridging requires explicit unsafeBitCast for type safety
        let privateKey = unsafeBitCast(cfResult, to: SecKey.self)
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyManagerError.invalidData
        }
        
        return SecureEnclaveKey(publicKey: publicKey, privateKey: privateKey)
    }
    
    /// Delete a Secure Enclave key pair
    /// - Parameter identifier: The identifier of the key to delete
    public func deleteSecureEnclaveKey(identifier: String) async throws {
        guard let tag = identifier.data(using: .utf8) else {
            throw KeyManagerError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.deletionFailed(status)
        }
    }
    
    // MARK: - Encryption/Decryption Helpers
    
    /// Encrypt data using a Secure Enclave public key
    /// - Parameters:
    ///   - data: The data to encrypt
    ///   - publicKey: The public key to encrypt with
    /// - Returns: The encrypted data
    public func encrypt(data: Data, using publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionCofactorX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            if error != nil {
                throw KeyManagerError.invalidData
            }
            throw KeyManagerError.invalidData
        }
        
        return encryptedData as Data
    }
    
    /// Decrypt data using a Secure Enclave private key
    /// - Parameters:
    ///   - encryptedData: The encrypted data
    ///   - privateKey: The private key to decrypt with
    /// - Returns: The decrypted data
    public func decrypt(data encryptedData: Data, using privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .eciesEncryptionCofactorX963SHA256AESGCM,
            encryptedData as CFData,
            &error
        ) else {
            if error != nil {
                throw KeyManagerError.invalidData
            }
            throw KeyManagerError.invalidData
        }
        
        return decryptedData as Data
    }
}
