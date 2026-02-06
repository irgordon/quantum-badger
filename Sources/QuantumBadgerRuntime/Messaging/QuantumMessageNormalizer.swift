import Foundation

enum QuantumMessageNormalizer {
    static func normalize(result: ToolResult) -> [QuantumMessage] {
        var messages: [QuantumMessage] = []
        let finishedAt = result.finishedAt

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
                    let summary = "Found \(matches.count) matches."
                    messages.append(
                        QuantumMessage(
                            kind: .localSearchResults,
                            source: .tool,
                            toolName: result.toolName,
                            content: summary,
                            createdAt: finishedAt,
                            localMatches: matches
                        )
                    )
                }
            }
        case "web.scout":
            if let json = result.output["cards"] {
                let cards = WebScoutACL.decodeResultsJSON(json)
                let verified = isVerifiedPayload(json: json, signature: result.output["cardsSignature"])
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
                            webCards: cards
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
                        createdAt: finishedAt
                    )
                )
            }
        }

        return messages
    }

    private static func isVerifiedPayload(json: String, signature: String?) -> Bool {
        guard let signature, let data = json.data(using: .utf8) else { return false }
        return InboundIdentityValidator.shared.verifyPayload(data, signature: signature)
    }
}
