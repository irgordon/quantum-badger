import Foundation
import QuantumBadgerRuntime

final class KeychainCloudKeyProvider: CloudAPIKeyProvider {
    private let keychain = KeychainStore()

    func apiKey(for modelId: UUID) -> String? {
        let label = "cloud-api-key-\(modelId.uuidString)"
        return try? keychain.loadSecret(label: label)
    }
}
