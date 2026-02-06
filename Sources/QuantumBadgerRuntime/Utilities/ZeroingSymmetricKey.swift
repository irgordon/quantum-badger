import Foundation
import CryptoKit

struct ZeroingSymmetricKey {
    private var keyData: Data

    init?(data: Data) {
        guard !data.isEmpty else { return nil }
        self.keyData = data
    }

    mutating func withKey<T>(_ block: (SymmetricKey) throws -> T) rethrows -> T {
        let key = SymmetricKey(data: keyData)
        let result = try block(key)
        zero()
        return result
    }

    mutating func zero() {
        keyData.resetBytes(in: 0..<keyData.count)
    }

    mutating func withBytes<R>(_ block: (Data) throws -> R) rethrows -> R {
        let result = try block(keyData)
        zero()
        return result
    }
}
