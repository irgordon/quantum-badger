import Foundation

protocol CloudAPIKeyProvider {
    func apiKey(for modelId: UUID) -> String?
}
