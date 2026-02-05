import Foundation
import CommonCrypto

enum PBKDF2 {
    static func deriveKey(password: String, salt: Data, iterations: Int, keyByteCount: Int) throws -> Data {
        let passwordData = Data(password.utf8)
        var derivedKey = Data(count: keyByteCount)
        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    keyByteCount
                )
            }
        }
        guard status == kCCSuccess else {
            throw PBKDF2Error.deriveFailed
        }
        return derivedKey
    }
}

enum PBKDF2Error: Error {
    case deriveFailed
}
