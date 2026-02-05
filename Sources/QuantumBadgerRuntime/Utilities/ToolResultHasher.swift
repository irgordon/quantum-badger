import Foundation

public enum ToolResultHasher {
    public static func hash(_ result: ToolResult) -> String {
        let fingerprint = ToolResultFingerprint(from: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(fingerprint)) ?? Data()
        return Hashing.sha256(data)
    }
}

private struct ToolResultFingerprint: Codable {
    let id: UUID
    let toolName: String
    let succeeded: Bool
    let finishedAt: Date
    let output: [KeyValue]

    init(from result: ToolResult) {
        id = result.id
        toolName = result.toolName
        succeeded = result.succeeded
        finishedAt = result.finishedAt
        output = result.output
            .map { KeyValue(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }
}

private struct KeyValue: Codable {
    let key: String
    let value: String
}
