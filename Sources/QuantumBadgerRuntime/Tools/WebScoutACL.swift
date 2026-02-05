import Foundation

struct WebScoutACL {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    struct Cleaned {
        let results: [WebScoutResult]
        let fallbackText: String

        var renderedText: String {
            if !results.isEmpty {
                return results.map { $0.render() }.joined(separator: "\n\n")
            }
            return fallbackText
        }

        var resultsJSON: String? {
            guard !results.isEmpty else { return nil }
            let data = (try? JSONEncoder().encode(results)) ?? Data()
            return String(data: data, encoding: .utf8)
        }
    }

    static func clean(from payload: String) -> Cleaned {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let results = decodeResults(from: data),
           !results.isEmpty {
            return Cleaned(results: results, fallbackText: trimmed)
        }
        return Cleaned(results: [], fallbackText: trimmed)
    }

    private static func decodeResults(from data: Data) -> [WebScoutResult]? {
        let decodedArray: SafeCollection<WebScoutDTO>? = SafeDecodingLog.withSource("Web Scout") {
            try? decoder.decode(SafeCollection<WebScoutDTO>.self, from: data)
        }
        if let array = decodedArray {
            let decoded = array.items.compactMap { WebScoutResult(dto: $0) }
            return decoded
        }
        if let dto = try? decoder.decode(WebScoutDTO.self, from: data) {
            if let result = WebScoutResult(dto: dto) {
                return [result]
            }
        }
        if let wrapper = try? decoder.decode(WebScoutDTOArrayWrapper.self, from: data) {
            let decoded = wrapper.items.compactMap { WebScoutResult(dto: $0) }
            return decoded
        }
        return nil
    }

    static func decodeResultsJSON(_ json: String) -> [WebScoutResult] {
        guard let data = json.data(using: .utf8) else { return [] }
        return decodeResults(from: data) ?? []
    }
}

struct WebScoutResult: Codable {
    let title: String
    let url: String
    let snippet: String

    init?(dto: WebScoutDTO) {
        guard let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        self.title = title
        self.url = dto.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let snippetArray = dto.snippetArray, !snippetArray.isEmpty {
            self.snippet = snippetArray.joined(separator: " ")
        } else {
            self.snippet = dto.snippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func render() -> String {
        var line = title
        if !url.isEmpty {
            line += " — \(url)"
        }
        if !snippet.isEmpty {
            line += "\n\(snippet)"
        }
        return line
    }
}

struct WebScoutDTO: Codable {
    let title: String?
    let url: String?
    let snippet: String?
    let snippetArray: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        if let array = try? container.decodeIfPresent([String].self, forKey: .snippetArray) {
            snippetArray = array
        } else if let single = try? container.decodeIfPresent(String.self, forKey: .snippetArray) {
            snippetArray = single.map { [$0] } ?? nil
        } else {
            snippetArray = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case url
        case snippet
        case snippetArray = "snippet"
    }
}

struct WebScoutDTOArrayWrapper: Codable {
    let items: [WebScoutDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([WebScoutDTO].self) {
            items = array
        } else if let single = try? container.decode(WebScoutDTO.self) {
            items = [single]
        } else {
            items = []
        }
    }
}
