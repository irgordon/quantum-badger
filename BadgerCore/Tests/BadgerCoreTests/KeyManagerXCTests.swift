import Foundation
import Security
import XCTest
@testable import BadgerCore

final class KeyManagerXCTests: XCTestCase {
    private struct MockKeyProvider: KeyProvider {
        func isAvailable() -> Bool { true }
        
        func generateKey(attributes: [String: Any]) throws -> SecKey {
            let adjustedAttributes = makeSoftwareKeyAttributes(from: attributes)
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey(adjustedAttributes as CFDictionary, &error) else {
                throw KeyManagerError.keyGenerationFailed
            }
            return key
        }
        
        private func makeSoftwareKeyAttributes(from attributes: [String: Any]) -> [String: Any] {
            var adjusted = attributes
            adjusted.removeValue(forKey: kSecAttrTokenID as String)
            return adjusted
        }
    }
    
    private final class MockStorageProvider: StorageProvider, @unchecked Sendable {
        private var tokenStore: [String: Data] = [:]
        private let lock = NSLock()
        
        func store(query: [String: Any]) throws {
            guard let service = query[kSecAttrService as String] as? String,
                  let account = query[kSecAttrAccount as String] as? String,
                  let data = query[kSecValueData as String] as? Data else {
                throw KeyManagerError.invalidData
            }
            let key = cacheKey(service: service, account: account)
            lock.lock()
            tokenStore[key] = data
            lock.unlock()
        }
        
        func fetch(query: [String: Any]) throws -> AnyObject {
            guard let service = query[kSecAttrService as String] as? String,
                  let account = query[kSecAttrAccount as String] as? String else {
                throw KeyManagerError.itemNotFound
            }
            let key = cacheKey(service: service, account: account)
            lock.lock()
            let value = tokenStore[key]
            lock.unlock()
            guard let value else {
                throw KeyManagerError.itemNotFound
            }
            return value as AnyObject
        }
        
        func delete(query: [String: Any]) throws {
            guard let service = query[kSecAttrService as String] as? String,
                  let account = query[kSecAttrAccount as String] as? String else {
                throw KeyManagerError.itemNotFound
            }
            let key = cacheKey(service: service, account: account)
            lock.lock()
            let removed = tokenStore.removeValue(forKey: key)
            lock.unlock()
            guard removed != nil else {
                throw KeyManagerError.itemNotFound
            }
        }
        
        private func cacheKey(service: String, account: String) -> String {
            "\(service)|\(account)"
        }
    }
    
    func testStoreRetrieveAndDeleteToken() async throws {
        let keyManager = KeyManager(storageProvider: MockStorageProvider())
        let provider: AIProvider = .anthropic
        let token = "test-token-\(UUID().uuidString)"
        
        defer {
            Task {
                try? await keyManager.deleteToken(for: provider)
            }
        }
        
        try await keyManager.storeToken(token, for: provider)
        let retrieved = try await keyManager.retrieveToken(for: provider)
        XCTAssertEqual(retrieved, token)
        
        try await keyManager.deleteToken(for: provider)
        
        do {
            _ = try await keyManager.retrieveToken(for: provider)
            XCTFail("Expected retrieval to fail after token deletion")
        } catch let error as KeyManagerError {
            guard case .itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)")
                return
            }
        }
    }
    
    func testGenerateAndRetrieveSecureEnclaveKeyPair() async throws {
        let keyManager = KeyManager(keyProvider: MockKeyProvider())
        
        let identifier = "com.quantumbadger.test.key.\(UUID().uuidString)"
        
        defer {
            Task {
                try? await keyManager.deleteSecureEnclaveKey(identifier: identifier)
            }
        }
        
        let generated = try await keyManager.generateSecureEnclaveKeyPair(identifier: identifier)
        let retrieved = try await keyManager.retrieveSecureEnclaveKey(identifier: identifier)
        
        let payload = Data("quantum-badger".utf8)
        let encrypted = try await keyManager.encrypt(data: payload, using: retrieved.publicKey)
        let decrypted = try await keyManager.decrypt(data: encrypted, using: generated.privateKey)
        
        XCTAssertEqual(decrypted, payload)
    }
    
    func testDeleteSecureEnclaveKeyPreventsFutureRetrieval() async throws {
        let keyManager = KeyManager(keyProvider: MockKeyProvider())
        
        let identifier = "com.quantumbadger.test.delete.\(UUID().uuidString)"
        
        _ = try await keyManager.generateSecureEnclaveKeyPair(identifier: identifier)
        try await keyManager.deleteSecureEnclaveKey(identifier: identifier)
        
        do {
            _ = try await keyManager.retrieveSecureEnclaveKey(identifier: identifier)
            XCTFail("Expected retrieval to fail after key deletion")
        } catch let error as KeyManagerError {
            guard case .itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)")
                return
            }
        }
    }
}
