import Foundation

enum MemoryWriteSource {
    case userAction
    case system
}

struct MemoryWriteDecision {
    let isAllowed: Bool
    let requiresUserConfirmation: Bool
    let reason: String
}

struct MemoryWritePolicy {
    func evaluate(entry: MemoryEntry, source: MemoryWriteSource) -> MemoryWriteDecision {
        if entry.trustLevel == .level0Ephemeral {
            return MemoryWriteDecision(
                isAllowed: true,
                requiresUserConfirmation: false,
                reason: "Ephemeral memory does not persist."
            )
        }
        if source == .userAction {
            return MemoryWriteDecision(
                isAllowed: true,
                requiresUserConfirmation: false,
                reason: "User initiated memory write."
            )
        }
        return MemoryWriteDecision(
            isAllowed: false,
            requiresUserConfirmation: true,
            reason: "User confirmation required for persistent memory."
        )
    }
}
