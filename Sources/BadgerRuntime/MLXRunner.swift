import Foundation
import BadgerCore

public struct ModelTurnResponse: Sendable {
    public let content: String?
    public let toolCall: ToolCallPayload?
    
    public init(content: String?, toolCall: ToolCallPayload?) {
        self.content = content
        self.toolCall = toolCall
    }
}

/// Drives MLX token streaming and supports early tool-call interception.
public final class MLXRunner {
    private let runtime: LocalMLXRuntimeAdapter
    private let parseTailBytes = 16 * 1024

    public init(runtime: LocalMLXRuntimeAdapter) {
        self.runtime = runtime
    }

    public func runUntilToolCallOrCompletion(
        prompt: String,
        kind: TaskKind = .chat
    ) async throws -> ModelTurnResponse {
        var buffer = ""
        var interceptedCall: ToolCallPayload?
        var sawToolTrigger = false

        // runtime.streamResponse returns AsyncThrowingStream<QuantumMessage, Error>
        // But what if it returns AsyncStream?
        // My adapter defined it as AsyncThrowingStream.
        
        let stream = runtime.streamResponse(for: prompt, kind: kind)
        do {
            for try await message in stream {
                // message is QuantumMessage
                let chunk = message.content
                buffer.append(chunk)

                if !sawToolTrigger {
                    let tail = String(buffer.suffix(256))
                    sawToolTrigger = containsToolTrigger(tail)
                }

                guard shouldAttemptParse(
                    latestChunk: chunk,
                    sawToolTrigger: sawToolTrigger,
                    buffer: buffer
                ) else {
                    continue
                }

                if let call = parseFromTail(of: buffer) {
                    interceptedCall = call
                    runtime.cancelGeneration()
                    break
                }
            }
        } catch {
            throw error
        }

        if let interceptedCall {
            return ModelTurnResponse(content: nil, toolCall: interceptedCall)
        }

        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelTurnResponse(
            content: trimmed.isEmpty ? nil : trimmed,
            toolCall: nil
        )
    }

    private func containsToolTrigger(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("toolcall")
            || lower.contains("tool_call")
            || lower.contains("\"toolname\"")
    }

    private func shouldAttemptParse(
        latestChunk: String,
        sawToolTrigger: Bool,
        buffer: String
    ) -> Bool {
        let hasClosingBrace = latestChunk.contains("}") || buffer.last == "}"
        guard hasClosingBrace else { return false }
        if sawToolTrigger { return true }
        return containsToolTrigger(latestChunk)
    }

    private func parseFromTail(of buffer: String) -> ToolCallPayload? {
        // Prefer a bounded tail to avoid repeatedly parsing the full growing buffer.
        let tail = String(buffer.utf8.suffix(parseTailBytes))

        if let direct = ConstrainedJSONScanner.parseToolCall(from: tail) {
            return direct
        }

        if let marker = tail.range(of: "\"toolCall\"")?.lowerBound {
            let head = tail[..<marker]
            if let start = head.lastIndex(of: "{") {
                let candidate = String(tail[start...])
                return ConstrainedJSONScanner.parseToolCall(from: candidate)
            }
        }
        return nil
    }
}
