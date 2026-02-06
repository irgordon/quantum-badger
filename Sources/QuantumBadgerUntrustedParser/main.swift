import Foundation
import QuantumBadgerRuntime
import Security

final class UntrustedParsingService: NSObject, UntrustedParsingXPCProtocol {
    private let maxInputBytes = 1_000_000
    private let maxResults = 10
    private let defaultAllowedTags = Set(UntrustedParsingPolicyStore.strictTags)

    func parse(
        _ data: Data,
        allowlist: [String],
        maxParseSeconds: Double,
        maxAnchorScans: Int,
        withReply reply: @escaping (String?, String?) -> Void
    ) {
        guard data.count <= maxInputBytes else {
            reply(nil, "Input too large for safe parsing.")
            return
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        let clampedSeconds = max(0.1, min(maxParseSeconds, 2.0))
        let clampedAnchors = max(50, min(maxAnchorScans, 5000))
        let deadline = Date().addingTimeInterval(clampedSeconds)
        let parsedResults = parseDuckDuckGoResults(
            html: text,
            deadline: deadline,
            maxAnchorScans: clampedAnchors
        )
        let output = parsedResults.isEmpty ? sanitizeHTML(text, allowlist: allowlist) : parsedResults
        let preview = String(output.prefix(1_000_000))
        reply(preview, nil)
    }

    private func parseDuckDuckGoResults(html: String, deadline: Date, maxAnchorScans: Int) -> String {
        guard html.contains("result__a") else { return "" }
        var results: [[String: String]] = []
        var index = html.startIndex
        var scanCount = 0

        while results.count < maxResults {
            if Date() >= deadline { break }
            if scanCount >= maxAnchorScans { break }
            scanCount += 1
            guard let anchor = findNextAnchor(in: html, from: index) else { break }
            index = anchor.searchIndex

            guard let href = anchor.href, isSafeURL(href) else { continue }
            guard let title = anchor.title, !title.isEmpty else { continue }

            var item: [String: String] = [
                "title": title,
                "url": href
            ]

            if let snippet = extractSnippet(after: anchor.anchorCloseIndex, html: html),
               !snippet.isEmpty {
                item["snippet"] = snippet
            }

            results.append(item)
        }

        let data = (try? JSONSerialization.data(withJSONObject: results, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let needle = "\(name)=\""
        guard let start = tag.range(of: needle) else { return nil }
        let valueStart = start.upperBound
        guard let end = tag.range(of: "\"", range: valueStart..<tag.endIndex) else { return nil }
        return String(tag[valueStart..<end.lowerBound])
    }

    private struct AnchorParseResult {
        let href: String?
        let title: String?
        let anchorCloseIndex: String.Index
        let searchIndex: String.Index
    }

    private func findNextAnchor(in html: String, from start: String.Index) -> AnchorParseResult? {
        var index = start
        let end = html.endIndex

        while index < end {
            guard let tagStart = html[index...].firstIndex(of: "<") else { return nil }
            index = tagStart
            let next = html.index(after: tagStart)
            guard next < end else { return nil }
            let char = html[next]
            if char != "a" && char != "A" {
                index = html.index(after: tagStart)
                continue
            }
            guard let tagEnd = html[next...].firstIndex(of: ">") else { return nil }
            if html.distance(from: tagStart, to: tagEnd) > 2048 {
                index = html.index(after: tagEnd)
                continue
            }

            let tagContent = html[html.index(after: tagStart)..<tagEnd]
            guard let tagName = parseTagName(from: tagContent).name, tagName == "a" else {
                index = html.index(after: tagEnd)
                continue
            }
            let attrs = parseAttributes(String(tagContent))
            guard let classValue = attrs["class"],
                  classValue.split(separator: " ").contains(where: { $0 == "result__a" }) else {
                index = html.index(after: tagEnd)
                continue
            }
            let href = attrs["href"]

            let titleStart = html.index(after: tagEnd)
            guard let close = html.range(of: "</a>", range: titleStart..<end) else {
                index = html.index(after: tagEnd)
                continue
            }
            let rawTitle = String(html[titleStart..<close.lowerBound])
            let title = decodeHTMLEntities(in: stripTags(rawTitle))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let searchIndex = close.upperBound
            return AnchorParseResult(
                href: href,
                title: title.isEmpty ? nil : String(title.prefix(300)),
                anchorCloseIndex: close.upperBound,
                searchIndex: searchIndex
            )
        }

        return nil
    }

    private func parseAttributes(_ tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = tag.startIndex
        let end = tag.endIndex

        func skipWhitespace() {
            while index < end, tag[index].isWhitespace { index = tag.index(after: index) }
        }

        while index < end {
            skipWhitespace()
            let nameStart = index
            while index < end, (tag[index].isLetter || tag[index].isNumber || tag[index] == "-" || tag[index] == "_") {
                index = tag.index(after: index)
            }
            let name = String(tag[nameStart..<index]).lowercased()
            skipWhitespace()
            guard !name.isEmpty, index < end, tag[index] == "=" else {
                if index < end { index = tag.index(after: index) }
                continue
            }
            index = tag.index(after: index)
            skipWhitespace()
            guard index < end else { break }
            let quote = tag[index]
            guard quote == "\"" || quote == "'" else {
                while index < end, !tag[index].isWhitespace { index = tag.index(after: index) }
                continue
            }
            index = tag.index(after: index)
            let valueStart = index
            while index < end, tag[index] != quote {
                index = tag.index(after: index)
            }
            let value = String(tag[valueStart..<index])
            attributes[name] = value
            if index < end { index = tag.index(after: index) }
        }

        return attributes
    }

    private func extractSnippet(after start: String.Index, html: String) -> String? {
        let end = html.endIndex
        var index = start
        let allowedSnippetClasses = Set(["result__snippet", "result__content", "result__body"])

        while index < end {
            guard let tagStart = html[index...].firstIndex(of: "<") else { return nil }
            let next = html.index(after: tagStart)
            guard next < end else { return nil }
            if html[next] == "/" {
                index = html.index(after: next)
                continue
            }
            guard let tagEnd = html[next...].firstIndex(of: ">") else { return nil }
            if html.distance(from: tagStart, to: tagEnd) > 2048 {
                index = html.index(after: tagEnd)
                continue
            }
            let tagContent = html[html.index(after: tagStart)..<tagEnd]
            let tagNameInfo = parseTagName(from: tagContent)
            guard let tagName = tagNameInfo.name else {
                index = html.index(after: tagEnd)
                continue
            }
            let attrs = parseAttributes(String(tagContent))
            if let classValue = attrs["class"] {
                let classes = Set(classValue.split(separator: " ").map { String($0) })
                if !classes.isDisjoint(with: allowedSnippetClasses) {
                    let contentStart = html.index(after: tagEnd)
                    if let closeRange = html.range(of: "</\(tagName)>", range: contentStart..<end) {
                        let rawSnippet = String(html[contentStart..<closeRange.lowerBound])
                        let snippet = decodeHTMLEntities(in: stripTags(rawSnippet))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return snippet.isEmpty ? nil : String(snippet.prefix(360))
                    }
                }
            }
            index = html.index(after: tagEnd)
        }
        return nil
    }

    private func isSafeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return url.host != nil
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

    private func sanitizeHTML(_ html: String, allowlist: [String]) -> String {
        let allowedTags = allowlist.isEmpty
            ? defaultAllowedTags
            : Set(allowlist.map { $0.lowercased() })
        let lineBreakTags: Set<String> = ["br", "p", "div", "li", "tr", "hr"]

        var output = ""
        output.reserveCapacity(min(html.count, 1024 * 64))

        var index = html.startIndex
        var blockedDepth = 0

        while index < html.endIndex {
            let char = html[index]
            if char == "<" {
                guard let tagEnd = html[index...].firstIndex(of: ">") else { break }
                let tagContent = html[html.index(after: index)..<tagEnd]
                let tagNameInfo = parseTagName(from: tagContent)
                if let tagName = tagNameInfo.name {
                    let isAllowed = allowedTags.contains(tagName)
                    if !isAllowed {
                        if tagNameInfo.isClosing {
                            if blockedDepth > 0 { blockedDepth -= 1 }
                        } else if !tagNameInfo.isSelfClosing {
                            blockedDepth += 1
                        }
                    } else if blockedDepth == 0, !tagNameInfo.isClosing {
                        if lineBreakTags.contains(tagName) {
                            output.append("\n")
                        }
                    }
                }
                index = html.index(after: tagEnd)
                continue
            }

            if blockedDepth == 0 {
                output.append(char)
            }
            index = html.index(after: index)
        }

        let cleaned = decodeHTMLEntities(in: output)
            .replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    private func decodeHTMLEntities(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                let nextIndex = text.index(after: index)
                if let semicolon = text[nextIndex...].firstIndex(of: ";") {
                    let entity = String(text[nextIndex..<semicolon])
                    if let decoded = decodeEntity(entity) {
                        result.append(decoded)
                        index = text.index(after: semicolon)
                        continue
                    } else {
                        result.append(contentsOf: "&" + entity + ";")
                        index = text.index(after: semicolon)
                        continue
                    }
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private func decodeEntity(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            break
        }
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            let hex = String(entity.dropFirst(2))
            if let value = UInt32(hex, radix: 16),
               let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
        } else if entity.hasPrefix("#") {
            let num = String(entity.dropFirst(1))
            if let value = UInt32(num),
               let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
        }
        return nil
    }

    private func parseTagName(from content: Substring) -> (name: String?, isClosing: Bool, isSelfClosing: Bool) {
        var iterator = content.makeIterator()
        var chars: [Character] = []
        var isClosing = false
        var isSelfClosing = false

        while let char = iterator.next() {
            if char == "/" && chars.isEmpty {
                isClosing = true
                continue
            }
            if char.isLetter || char.isNumber {
                chars.append(char.lowercased())
                continue
            }
            if char == "/" {
                isSelfClosing = true
            }
            if !chars.isEmpty {
                break
            }
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") {
            isSelfClosing = true
        }

        let name = chars.isEmpty ? nil : String(chars)
        return (name, isClosing, isSelfClosing)
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
