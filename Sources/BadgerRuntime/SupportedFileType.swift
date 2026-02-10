import Foundation

/// Supported file types for ingestion and generation.
@frozen
public enum SupportedFileType: String, Sendable, Codable, Equatable, Hashable {
    case pdf
    case png
    case jpg
    case txt
    case markdown
    case rtf
}

/// The origin LLM that produced generated output.
@frozen
public enum LLMSource: String, Sendable, Codable, Equatable, Hashable {
    case local
    case cloud
}
