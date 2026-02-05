import Foundation
import QuantumBadgerRuntime
import Security

final class UntrustedParsingService: NSObject, UntrustedParsingXPCProtocol {
    private let maxInputBytes = 1_000_000
    private let maxResults = 10

    func parse(_ data: Data, withReply reply: @escaping (String?, String?) -> Void) {
        guard data.count <= maxInputBytes else {
            reply(nil, "Input too large for safe parsing.")
            return
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        let parsedResults = parseDuckDuckGoResults(html: text)
        let output = parsedResults.isEmpty ? sanitizeHTML(text) : parsedResults
        let preview = String(output.prefix(1_000_000))
        reply(preview, nil)
    }

    private func parseDuckDuckGoResults(html: String) -> String {
        guard html.contains("result__a") else { return "" }
        var results: [[String: String]] = []
        var index = html.startIndex

        while results.count < maxResults,
              let anchorRange = html.range(of: "result__a", range: index..<html.endIndex) {
            guard let tagStart = html.range(of: "<a", range: html.startIndex..<anchorRange.lowerBound) else {
                index = anchorRange.upperBound
                continue
            }
            guard let tagEnd = html.range(of: ">", range: anchorRange.upperBound..<html.endIndex) else {
                index = anchorRange.upperBound
                continue
            }

            let tagSlice = html[tagStart.lowerBound..<tagEnd.upperBound]
            let href = extractAttribute("href", from: String(tagSlice)) ?? ""

            let titleStart = tagEnd.upperBound
            guard let titleEnd = html.range(of: "</a>", range: titleStart..<html.endIndex) else {
                index = tagEnd.upperBound
                continue
            }
            let rawTitle = String(html[titleStart..<titleEnd.lowerBound])
            let title = stripTags(rawTitle)

            let snippet = extractSnippet(after: titleEnd.upperBound, html: html)

            if !title.isEmpty {
                var item: [String: String] = ["title": title]
                if !href.isEmpty { item["url"] = href }
                if !snippet.isEmpty { item["snippet"] = snippet }
                results.append(item)
            }

            index = titleEnd.upperBound
        }

        let data = (try? JSONSerialization.data(withJSONObject: results, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractSnippet(after index: String.Index, html: String) -> String {
        let snippetMarkers = ["result__snippet", "result__snippet", "result__snippet"]
        var searchIndex = index
        for marker in snippetMarkers {
            if let markerRange = html.range(of: marker, range: searchIndex..<html.endIndex) {
                if let tagStart = html.range(of: ">", range: markerRange.upperBound..<html.endIndex),
                   let tagEnd = html.range(of: "<", range: tagStart.upperBound..<html.endIndex) {
                    let raw = String(html[tagStart.upperBound..<tagEnd.lowerBound])
                    let cleaned = stripTags(raw)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
                searchIndex = markerRange.upperBound
            }
        }
        return ""
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let needle = "\(name)=\""
        guard let start = tag.range(of: needle) else { return nil }
        let valueStart = start.upperBound
        guard let end = tag.range(of: "\"", range: valueStart..<tag.endIndex) else { return nil }
        return String(tag[valueStart..<end.lowerBound])
    }

    private func stripTags(_ input: String) -> String {
        var output = ""
        var insideTag = false
        for char in input {
            if char == "<" { insideTag = true; continue }
            if char == ">" { insideTag = false; continue }
            if !insideTag {
                output.append(char)
            }
        }
        return output.replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeHTML(_ html: String) -> String {
        var result = html
        let patterns = [
            "<script[\\s\\S]*?>[\\s\\S]*?<\\/script>",
            "<iframe[\\s\\S]*?>[\\s\\S]*?<\\/iframe>",
            "<object[\\s\\S]*?>[\\s\\S]*?<\\/object>",
            "<style[\\s\\S]*?>[\\s\\S]*?<\\/style>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
            }
        }
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = tagRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        result = result.replacingOccurrences(of: "\u{0}", with: "")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class UntrustedParsingListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let allowedTeamIDs: Set<String>

    override init() {
        let configIds = loadAllowedTeamIds()
        if !configIds.isEmpty {
            allowedTeamIDs = Set(configIds)
        } else if let selfTeam = currentTeamIdentifier() {
            allowedTeamIDs = [selfTeam]
        } else {
            allowedTeamIDs = []
        }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        if let teamID = auditTeamIdentifier(for: newConnection), !allowedTeamIDs.contains(teamID) {
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: UntrustedParsingXPCProtocol.self)
        newConnection.exportedObject = UntrustedParsingService()
        newConnection.resume()
        return true
    }

    private func auditTeamIdentifier(for connection: NSXPCConnection) -> String? {
        var token = audit_token_t()
        connection.getAuditToken(&token)
        var pid: pid_t = 0
        pid = audit_token_to_pid(token)
        let attributes: [String: Any] = [kSecGuestAttributePid as String: pid]
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest)
        guard status == errSecSuccess, let guest else { return nil }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(guest, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        if let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String {
            return teamID
        }
        return nil
    }

    private func currentTeamIdentifier() -> String? {
        var code: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func loadAllowedTeamIds() -> [String] {
        guard let url = Bundle.main.url(forResource: "UntrustedParserConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoded = try? JSONDecoder().decode(UntrustedParserConfig.self, from: data)
        return decoded?.allowedTeamIds ?? []
    }
}

private struct UntrustedParserConfig: Codable {
    let allowedTeamIds: [String]
}

let delegate = UntrustedParsingListenerDelegate()
let listener = NSXPCListener(machServiceName: "com.quantumbadger.UntrustedParser")
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
