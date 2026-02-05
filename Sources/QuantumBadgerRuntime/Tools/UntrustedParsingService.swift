import Foundation

protocol UntrustedParsingService {
    func parse(_ data: Data) async throws -> String
}

struct DisabledUntrustedParsingService: UntrustedParsingService {
    func parse(_ data: Data) async throws -> String {
        throw UntrustedParsingError.unavailable
    }
}

enum UntrustedParsingError: Error {
    case unavailable
    case remote(String)
}
