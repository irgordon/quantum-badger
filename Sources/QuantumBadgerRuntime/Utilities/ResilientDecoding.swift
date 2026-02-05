import Foundation

@propertyWrapper
struct Coerced<Value: LosslessStringConvertible & Codable>: Codable {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Value.self) {
            wrappedValue = value
            return
        }
        if let stringValue = try? container.decode(String.self),
           let value = Value(stringValue) {
            wrappedValue = value
            return
        }
        throw DecodingError.typeMismatch(
            Value.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Could not coerce value to \(Value.self)"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

struct SafeCollection<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var index = 0
        var skipped = 0

        while !container.isAtEnd {
            do {
                let element = try container.decode(Element.self)
                elements.append(element)
            } catch {
                SafeDecodingLog.recordSkippedElement(
                    codingPath: decoder.codingPath,
                    index: index,
                    error: error
                )
                skipped += 1
                _ = try? container.decode(EmptyCodable.self)
            }
            index += 1
        }
        if skipped > 0 {
            SafeDecodingLog.recordSkippedSummary(count: skipped)
        }
        items = elements
    }
}

private struct EmptyCodable: Decodable {}

enum SafeDecodingLog {
    static var auditLog: AuditLog?
    @TaskLocal static var sourceLabel: String?

    static func withSource<T>(_ label: String, _ operation: () throws -> T) rethrows -> T {
        try $sourceLabel.withValue(label) {
            try operation()
        }
    }

    static func recordSkippedElement(codingPath: [CodingKey], index: Int, error: Error) {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        auditLog?.record(event: .decodingSkipped(path: path, index: index, reason: error.localizedDescription))
    }

    static func recordSkippedSummary(count: Int) {
        SystemEventBus.shared.post(.decodingSkipped(count: count, source: sourceLabel))
    }
}

@propertyWrapper
struct FlexibleBool: Codable {
    var wrappedValue: Bool

    init(wrappedValue: Bool) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            wrappedValue = value
            return
        }
        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue != 0
            return
        }
        if let stringValue = try? container.decode(String.self) {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1", "y", "on"].contains(normalized) {
                wrappedValue = true
                return
            }
            if ["false", "no", "0", "n", "off"].contains(normalized) {
                wrappedValue = false
                return
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Could not coerce value to Bool"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
