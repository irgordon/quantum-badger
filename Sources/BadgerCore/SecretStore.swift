import Foundation
import Security
import CryptoKit

/// A modern, type‑safe wrapper for the Secret Store (Keychain).
///
/// `SecretStore` enforces:
/// 1. **Scoped Access**: Secrets are stored under a specific service UUID to prevent collisions.
/// 2. **Hardware Binding**: Items are set to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
/// 3. **Type Safety**: Generic support for `Codable` values (wrapped as Data).
public struct SecretStore: Sendable {
    
    // MARK: - Types
    
    public enum SecretError: Error, LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedData
        case unhandledError(status: OSStatus)
        case encodingFailed
        case decodingFailed
        
        public var errorDescription: String? {
            switch self {
            case .itemNotFound: return "Secret not found in Keychain."
            case .duplicateItem: return "Secret already exists."
            case .unexpectedData: return "Data retrieved was corrupted or invalid."
            case .unhandledError(let status): return "Keychain error: \(status)"
            case .encodingFailed: return "Failed to encode value."
            case .decodingFailed: return "Failed to decode value."
            }
        }
    }
    
    // MARK: - State
    
    /// The service namespace for this store.
    public let serviceUUID: UUID
    
    // MARK: - Init
    
    /// Create a new secret store scope.
    /// - Parameter scope: A unique identifier for this collection of secrets.
    public init(scope: UUID) {
        self.serviceUUID = scope
    }
    
    // MARK: - Public API
    
    /// Store a Codable value securely.
    public func store<T: Codable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        try storeData(data, key: key)
    }
    
    /// Retrieve a Codable value.
    public func retrieve<T: Codable>(key: String) throws -> T {
        let data = try retrieveData(key: key)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Delete a secret.
    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceUUID.uuidString,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.unhandledError(status: status)
        }
    }
    
    // MARK: - Helpers
    
    private func storeData(_ data: Data, key: String) throws {
        // Prepare query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceUUID.uuidString,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Try add
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Update existing
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceUUID.uuidString,
                kSecAttrAccount as String: key
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecretError.unhandledError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw SecretError.unhandledError(status: status)
        }
    }
    
    private func retrieveData(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceUUID.uuidString,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status != errSecItemNotFound else {
            throw SecretError.itemNotFound
        }
        
        guard status == errSecSuccess else {
            throw SecretError.unhandledError(status: status)
        }
        
        guard let data = item as? Data else {
            throw SecretError.unexpectedData
        }
        
        return data
    }
}
