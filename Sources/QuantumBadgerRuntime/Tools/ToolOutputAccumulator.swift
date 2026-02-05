import Foundation

final class ToolOutputAccumulator {
    private let maxBytes: Int
    private var values: [String: String] = [:]
    private var valueSizes: [String: Int] = [:]
    private var arrayBuffers: [String: [String]] = [:]
    private var arraySizes: [String: Int] = [:]
    private let lock = NSLock()

    private(set) var truncated: Bool = false

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func setValue(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
        valueSizes[key] = value.utf8.count
        try enforceLimitLocked()
    }

    func appendJSONElement(_ elementJSON: String, toArrayKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var buffer = arrayBuffers[key] ?? []
        buffer.append(elementJSON)
        arrayBuffers[key] = buffer
        arraySizes[key] = estimateArraySize(buffer)
        try enforceLimitLocked()
    }

    func markTruncated() {
        lock.lock()
        truncated = true
        lock.unlock()
    }

    func finish() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        var output = values
        for (key, buffer) in arrayBuffers {
            let arrayString = "[\(buffer.joined(separator: ","))]"
            output[key] = arrayString
        }
        if truncated {
            output["truncated"] = "true"
        }
        return output
    }

    private func enforceLimitLocked() throws {
        guard maxBytes > 0 else { return }
        let total = valueSizes.values.reduce(0, +) + arraySizes.values.reduce(0, +)
        if total > maxBytes {
            truncated = true
            throw ToolRuntimeError.outputTooLarge
        }
    }

    private func estimateArraySize(_ buffer: [String]) -> Int {
        guard !buffer.isEmpty else { return 2 }
        let contentBytes = buffer.reduce(0) { $0 + $1.utf8.count }
        let commas = buffer.count - 1
        return contentBytes + commas + 2
    }
}
