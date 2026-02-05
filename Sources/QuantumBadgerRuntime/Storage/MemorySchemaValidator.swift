import Foundation

enum MemoryValidationError: LocalizedError {
    case emptyContent
    case preferenceFormat
    case contextFormat
    case tooLong
    case containsSensitiveData

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Content can’t be empty."
        case .preferenceFormat:
            return "Preferences must use the format “key: value”."
        case .contextFormat:
            return "Context entries must start with “Summary:”."
        case .tooLong:
            return "This entry is too long for its type."
        case .containsSensitiveData:
            return "This entry appears to contain sensitive data."
        }
    }
}

enum MemorySchemaValidator {
    static func validate(_ entry: MemoryEntry) throws {
        let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryValidationError.emptyContent }

        switch entry.trustLevel {
        case .level0Ephemeral:
            if trimmed.count > 800 { throw MemoryValidationError.tooLong }
        case .level1UserAuthored:
            guard entry.sourceType == .user else { throw MemoryValidationError.preferenceFormat }
            if trimmed.count > 4000 { throw MemoryValidationError.tooLong }
        case .level2UserConfirmed:
            guard entry.isConfirmed, entry.confirmedAt != nil else { throw MemoryValidationError.contextFormat }
            if trimmed.count > 2000 { throw MemoryValidationError.tooLong }
        case .level3Observational:
            guard entry.expiresAt != nil else { throw MemoryValidationError.contextFormat }
            if trimmed.count > 1200 { throw MemoryValidationError.tooLong }
        case .level4Summary:
            guard entry.sourceType == .model else { throw MemoryValidationError.contextFormat }
            if trimmed.count > 4000 { throw MemoryValidationError.tooLong }
        case .level5External:
            guard entry.sourceType == .tool || entry.sourceType == .external else { throw MemoryValidationError.contextFormat }
            if trimmed.count > 4000 { throw MemoryValidationError.tooLong }
        }
    }
}
