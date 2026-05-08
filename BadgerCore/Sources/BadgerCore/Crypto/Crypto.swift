import Foundation
import CryptoKit

/// Core cryptographic utilities for Quantum Badger
public enum Crypto {

    /// AES-GCM Encryption/Decryption
    public enum AESGCM {

        /// Encrypt data using AES-GCM
        /// - Parameters:
        ///   - data: The plaintext data to encrypt
        ///   - key: The symmetric key to use
        /// - Returns: The combined ciphertext, nonce, and tag
        public static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
            let sealedBox = try CryptoKit.AES.GCM.seal(data, using: key)
            return sealedBox.combined!
        }

        /// Decrypt data using AES-GCM
        /// - Parameters:
        ///   - combinedData: The combined ciphertext, nonce, and tag
        ///   - key: The symmetric key to use
        /// - Returns: The decrypted plaintext data
        public static func decrypt(_ combinedData: Data, using key: SymmetricKey) throws -> Data {
            let sealedBox = try CryptoKit.AES.GCM.SealedBox(combined: combinedData)
            return try CryptoKit.AES.GCM.open(sealedBox, using: key)
        }

        /// Generate a new random 256-bit symmetric key
        public static func generateKey() -> SymmetricKey {
            return SymmetricKey(size: .bits256)
        }
    }
}
