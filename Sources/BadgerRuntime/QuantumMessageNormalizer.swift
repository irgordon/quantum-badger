import Foundation
import BadgerCore

/// The "Refinement Gate" translating raw tool outputs to strictly typed messages.
public enum QuantumMessageNormalizer {

    public static func normalize(result: ToolResult) -> [QuantumMessage] {
        var messages: [QuantumMessage] = []
        let finishedAt = result.finishedAt
        let entityIDs = parseAppEntityIDs(from: result.output)

        if !result.succeeded, let error = result.output["error"] {
            messages.append(
                QuantumMessage(
                    kind: .toolError,
                    source: .tool,
                    toolName: result.toolName,
                    content: error,
                    createdAt: finishedAt
                )
            )
            return messages
        }

        switch result.toolName {
        case "local.search":
            if let json = result.output["matches"] {
                let matches = LocalSearchACL.decodeMatches(from: json)
                if !matches.isEmpty {
                    let signature = result.output["matchesSignature"]
                    let verified = isVerifiedPayload(json: json, signature: signature)
                    let summary = "Found \(matches.count) matches."
                    messages.append(
                        QuantumMessage(
                            kind: .localSearchResults,
                            source: .tool,
                            toolName: result.toolName,
                            content: summary,
                            createdAt: finishedAt,
                            isVerified: verified,
                            signature: signature,
                            localMatches: matches,
                            appEntityIds: entityIDs
                        )
                    )
                }
            }
        case "web.scout":
            if let json = result.output["cards"] {
                let cards = WebScoutACL.decodeResultsJSON(json)
                let signature = result.output["cardsSignature"]
                let verified = isVerifiedPayload(json: json, signature: signature)
                if !cards.isEmpty {
                    let summary = "Collected \(cards.count) web result\(cards.count == 1 ? "" : "s")."
                    messages.append(
                        QuantumMessage(
                            kind: .webScoutResults,
                            source: .tool,
                            toolName: result.toolName,
                            content: summary,
                            createdAt: finishedAt,
                            isVerified: verified,
                            signature: signature,
                            webCards: cards,
                            appEntityIds: entityIDs
                        )
                    )
                }
            }
        default:
            if let note = result.output["note"] ?? result.output["status"] {
                messages.append(
                    QuantumMessage(
                        kind: .toolNotice,
                        source: .tool,
                        toolName: result.toolName,
                        content: note,
                        createdAt: finishedAt,
                        appEntityIds: entityIDs
                    )
                )
            }
        }

        if messages.isEmpty, let text = result.output["result"] ?? result.output["message"] {
            messages.append(
                QuantumMessage(
                    kind: .text,
                    source: .tool,
                    toolName: result.toolName,
                    content: text,
                    createdAt: finishedAt,
                    appEntityIds: entityIDs
                )
            )
        }

        return messages
    }
    
    // MARK: - Verification

    private static func isVerifiedPayload(json: String, signature: String?) -> Bool {
        guard let signature, let data = json.data(using: .utf8) else { return false }
        return InboundIdentityValidator.shared.verifyPayload(data, signature: signature)
    }

    // MARK: - Entity Parsing

    private static func parseAppEntityIDs(from output: [String: String]) -> [String]? {
        if let json = output["appEntityIds"],
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let cleaned = dedupeAndClean(decoded)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let csv = output["appEntityIds"] {
            // Note: Use comma separation for CSV
            let cleaned = dedupeAndClean(
                csv.split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            )
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let single = output["appEntityId"] {
            let cleaned = dedupeAndClean([single])
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private static func dedupeAndClean(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
