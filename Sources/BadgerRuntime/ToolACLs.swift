import Foundation
import BadgerCore

/// Access Control Logic for Local Search content.
public enum LocalSearchACL {
    public static func decodeMatches(from json: String) -> [LocalSearchMatch] {
        guard let data = json.data(using: .utf8) else { return [] }
        // Determine structure later. For now, assume simple array of objects.
        // Or specific structure.
        struct RawMatch: Decodable {
            let path: String
            let snippet: String?
            let score: Double?
        }
        
        guard let raw = try? JSONDecoder().decode([RawMatch].self, from: data) else { return [] }
        return raw.map { LocalSearchMatch(path: $0.path, snippet: $0.snippet, score: $0.score ?? 0) }
    }
}

/// Access Control Logic for Web Scout content.
public enum WebScoutACL {
    public static func decodeResultsJSON(_ json: String) -> [WebScoutResult] {
        guard let data = json.data(using: .utf8) else { return [] }
        
        struct RawCard: Decodable {
            let url: String
            let title: String
            let snippet: String
        }
        
        guard let raw = try? JSONDecoder().decode([RawCard].self, from: data) else { return [] }
        return raw.map { WebScoutResult(url: $0.url, title: $0.title, snippet: $0.snippet) }
    }
}
