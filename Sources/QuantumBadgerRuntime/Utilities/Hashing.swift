import Foundation
import CryptoKit
import Dispatch
import Darwin

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

    static func hexString(from data: Data) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count * 2)
        for byte in data {
            bytes.append(hexLookup[Int(byte >> 4)])
            bytes.append(hexLookup[Int(byte & 0x0f)])
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    // Stream file hashing to avoid loading large payloads into memory.
    static func sha256File(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        let queue = DispatchQueue(label: "com.quantumbadger.hashing.file", qos: .utility)
        let group = DispatchGroup()
        group.enter()

        var hasher = SHA256()
        let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in
            close(fd)
        }
        io.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
            if error != 0 {
                io.close()
                group.leave()
                return
            }
            if let data, data.count > 0 {
                let chunk = Data(data)
                hasher.update(data: chunk)
            }
            if done {
                io.close()
                group.leave()
            }
        }
        group.wait()
        return Data(hasher.finalize())
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
