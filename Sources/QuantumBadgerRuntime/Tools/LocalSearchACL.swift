import Foundation

struct LocalSearchACL {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    static func decodeMatches(from json: String) -> [LocalSearchMatch] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decodedArray: SafeCollection<LocalSearchMatch>? = SafeDecodingLog.withSource("Local Search") {
            try? decoder.decode(SafeCollection<LocalSearchMatch>.self, from: data)
        }
        if let array = decodedArray {
            return array.items
        }
        if let single = try? decoder.decode(LocalSearchMatch.self, from: data) {
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
