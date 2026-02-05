import Foundation

struct LocalSearchACL {
    static func decodeMatches(from json: String) -> [LocalSearchMatch] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decodedArray: SafeCollection<LocalSearchMatch>? = SafeDecodingLog.withSource("Local Search") {
            try? JSONDecoder().decode(SafeCollection<LocalSearchMatch>.self, from: data)
        }
        if let array = decodedArray {
            return array.items
        }
        if let single = try? JSONDecoder().decode(LocalSearchMatch.self, from: data) {
            return [single]
        }
        return []
    }
}

struct Failable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
