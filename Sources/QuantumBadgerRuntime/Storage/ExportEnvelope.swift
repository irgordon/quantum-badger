import Foundation
import CryptoKit

struct ExportEnvelope: Codable {
    let version: Int
    let salt: Data
    let iterations: Int
    let sealedData: Data

    static func seal(data: Data, password: String) throws -> ExportEnvelope {
        let salt = CryptoRandom.bytes(count: 16)
        let iterations = 100_000
        let keyData = try PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations, keyByteCount: 32)
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw ExportEnvelopeError.sealFailed
        }
        return ExportEnvelope(version: 1, salt: salt, iterations: iterations, sealedData: combined)
    }
}

enum ExportEnvelopeError: Error {
    case sealFailed
}

enum CryptoRandom {
    static func bytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return data
    }
}
