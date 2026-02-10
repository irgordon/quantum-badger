import Foundation

/// Structured representation of a securely ingested file.
public struct IngestedFile: Sendable, Codable, Equatable, Hashable {
    /// Source filename as provided by the user.
    public let sourceFilename: String

    /// Detected file type.
    public let fileType: SupportedFileType

    /// Extracted and sanitized text content.
    public let textContent: String

    /// Optional thumbnail data (PNG bytes) for images and PDF pages.
    public let thumbnailData: Data?

    /// When the file was ingested.
    public let ingestedAt: Date

    /// SHA‑256 hash of the original file data for integrity tracking.
    public let contentHash: String

    public init(
        sourceFilename: String,
        fileType: SupportedFileType,
        textContent: String,
        thumbnailData: Data? = nil,
        ingestedAt: Date = Date(),
        contentHash: String
    ) {
        self.sourceFilename = sourceFilename
        self.fileType = fileType
        self.textContent = textContent
        self.thumbnailData = thumbnailData
        self.ingestedAt = ingestedAt
        self.contentHash = contentHash
    }
}
