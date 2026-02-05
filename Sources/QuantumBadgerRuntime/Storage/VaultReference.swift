import Foundation

struct VaultReference: Codable, Hashable, Identifiable {
    let id: UUID
    let label: String

    init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}
