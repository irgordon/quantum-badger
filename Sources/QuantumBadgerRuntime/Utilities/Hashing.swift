import Foundation
import CryptoKit

enum Hashing {
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return hexString(from: digest)
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return hexString(from: digest)
    }

    static func sha256Data(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    // Performance: avoid String(format:) per byte by using a lookup table.
    private static func hexString(from digest: SHA256.Digest) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digest.count * 2)
        for byte in digest {
            bytes.append(hexLookup[Int(byte >> 4)])
            bytes.append(hexLookup[Int(byte & 0x0f)])
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static let hexLookup: [UInt8] = Array("0123456789abcdef".utf8)
}
