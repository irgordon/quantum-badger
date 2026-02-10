import Foundation

/// Metadata for a file generated from LLM output.
public struct GeneratedFile: Sendable, Codable, Equatable, Hashable {
    /// Output filename.
    public let filename: String

    /// File type.
    public let fileType: SupportedFileType

    /// Size of the generated file in bytes.
    public let byteSize: UInt64

    /// Directory where the file was written.
    public let outputDirectory: URL

    /// When the file was generated.
    public let generatedAt: Date

    /// Which LLM produced the content.
    public let source: LLMSource

    /// Full path to the generated file.
    public var fileURL: URL {
        outputDirectory.appendingPathComponent(filename)
    }

    public init(
        filename: String,
        fileType: SupportedFileType,
        byteSize: UInt64,
        outputDirectory: URL,
        generatedAt: Date = Date(),
        source: LLMSource
    ) {
        self.filename = filename
        self.fileType = fileType
        self.byteSize = byteSize
        self.outputDirectory = outputDirectory
        self.generatedAt = generatedAt
        self.source = source
    }
}
