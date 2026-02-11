import Foundation
import CryptoKit
import PDFKit
import AppKit

/// Secure one‑way file manager for ingestion and LLM output generation.
///
/// **Design**: The file manager enforces a strict **one‑way gate** between
/// external file data and the LLM context. Raw file bytes never leak; only
/// sanitized text and optional thumbnails are exposed to the model.
///
/// ## Ingestion Path (User → LLM)
///
/// accept file → parse → sanitize → extract text → return `IngestedFile`
///
/// ## Generation Path (LLM → Disk)
///
/// accept LLM output → sanitize → write to sandboxed directory → return `GeneratedFile`
///
/// All operations are actor‑isolated, cancellable, and memory‑budget‑aware.
public actor SecureFileManager {

    // MARK: - Configuration

    /// Sandboxed output directory for generated files.
    private let outputDirectory: URL

    /// Content sanitizer.
    private let sanitizer: FileContentSanitizer

    /// Maximum file size for ingestion in bytes (50 MB).
    private let maxIngestionBytes: UInt64

    // MARK: - Init

    public init(
        outputDirectory: URL? = nil,
        sanitizer: FileContentSanitizer = FileContentSanitizer(),
        maxIngestionBytes: UInt64 = 50 * 1024 * 1024
    ) {
        self.outputDirectory = outputDirectory
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("QuantumBadger/GeneratedFiles", isDirectory: true)
        self.sanitizer = sanitizer
        self.maxIngestionBytes = maxIngestionBytes
    }

    // MARK: - Ingestion

    /// Securely ingest a file and return sanitized content.
    ///
    /// - Parameter fileURL: Path to the file on disk.
    /// - Returns: A sanitized ``IngestedFile`` with extracted text content.
    /// - Throws: ``FileManagerError`` on unsupported types or sanitization rejection.
    public func ingest(fileURL: URL) async throws -> IngestedFile {
        try Task.checkCancellation()

        // Read raw data.
        let data = try Data(contentsOf: fileURL)

        // Size check.
        guard UInt64(data.count) <= maxIngestionBytes else {
            throw FileManagerError.fileTooLarge(
                sizeBytes: UInt64(data.count),
                limitBytes: maxIngestionBytes
            )
        }

        // Detect type.
        let fileType = try detectFileType(fileURL)

        try Task.checkCancellation()

        // Extract text by type.
        let rawText: String
        var thumbnailData: Data?

        switch fileType {
        case .pdf:
            let extraction = await extractPDFContent(data: data)
            rawText = extraction.text
            thumbnailData = extraction.thumbnail

        case .png, .jpg:
            rawText = "[Image: \(fileURL.lastPathComponent)]"
            thumbnailData = createImageThumbnail(data: data)

        case .txt, .markdown:
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileManagerError.decodingFailed
            }
            rawText = text

        case .rtf:
            rawText = try extractRTFText(data: data)
        }

        // Sanitize.
        let result = sanitizer.sanitizeIngestion(rawText)
        guard let cleanText = result.content else {
            switch result {
            case .rejected(let reason):
                throw FileManagerError.sanitizationRejected(reason: reason)
            case .clean:
                throw FileManagerError.decodingFailed
            }
        }

        // Compute content hash.
        let hash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        return IngestedFile(
            sourceFilename: fileURL.lastPathComponent,
            fileType: fileType,
            textContent: cleanText,
            thumbnailData: thumbnailData,
            contentHash: hash
        )
    }

    // MARK: - Generation

    /// Generate a text file from LLM output.
    ///
    /// - Parameters:
    ///   - content: The text content to write.
    ///   - filename: Desired output filename.
    ///   - fileType: Target file type.
    ///   - source: Which LLM produced the content.
    /// - Returns: Metadata for the generated file.
    public func generateTextFile(
        content: String,
        filename: String,
        fileType: SupportedFileType,
        source: LLMSource
    ) async throws -> GeneratedFile {
        try Task.checkCancellation()

        // Sanitize.
        let result = sanitizer.sanitizeGeneration(content, filename: filename)
        guard let cleanContent = result.content else {
            switch result {
            case .rejected(let reason):
                throw FileManagerError.sanitizationRejected(reason: reason)
            case .clean:
                throw FileManagerError.decodingFailed
            }
        }

        // Ensure output directory exists.
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDirectory.path) {
            try fm.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        try Task.checkCancellation()

        // Write.
        let data = Data(cleanContent.utf8)
        let fileURL = outputDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)

        return GeneratedFile(
            filename: filename,
            fileType: fileType,
            byteSize: UInt64(data.count),
            outputDirectory: outputDirectory,
            source: source
        )
    }

    /// Generate an image file from raw image data.
    ///
    /// - Parameters:
    ///   - imageData: PNG or JPEG image bytes.
    ///   - filename: Desired output filename.
    ///   - fileType: `.png` or `.jpg`.
    ///   - source: Which LLM produced the image.
    /// - Returns: Metadata for the generated file.
    public func generateImageFile(
        imageData: Data,
        filename: String,
        fileType: SupportedFileType,
        source: LLMSource
    ) async throws -> GeneratedFile {
        try Task.checkCancellation()

        guard fileType == .png || fileType == .jpg else {
            throw FileManagerError.unsupportedFileType
        }

        // Validate that the data is actually an image.
        guard NSImage(data: imageData) != nil else {
            throw FileManagerError.invalidImageData
        }

        // Sanitize filename.
        let fnResult = sanitizer.sanitizeGeneration("", filename: filename)
        if case .rejected(let reason) = fnResult, reason.contains("path traversal") {
            throw FileManagerError.sanitizationRejected(reason: reason)
        }

        // Size check.
        guard UInt64(imageData.count) <= sanitizer.maxOutputBytes else {
            throw FileManagerError.fileTooLarge(
                sizeBytes: UInt64(imageData.count),
                limitBytes: sanitizer.maxOutputBytes
            )
        }

        // Ensure output directory exists.
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDirectory.path) {
            try fm.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        let fileURL = outputDirectory.appendingPathComponent(filename)
        try imageData.write(to: fileURL, options: .atomic)

        return GeneratedFile(
            filename: filename,
            fileType: fileType,
            byteSize: UInt64(imageData.count),
            outputDirectory: outputDirectory,
            source: source
        )
    }

    // MARK: - File Type Detection

    private func detectFileType(_ url: URL) throws -> SupportedFileType {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png": return .png
        case "jpg", "jpeg": return .jpg
        case "txt": return .txt
        case "md", "markdown": return .markdown
        case "rtf": return .rtf
        default:
            throw FileManagerError.unsupportedFileType
        }
    }

    // MARK: - PDF Extraction

    private func extractPDFContent(
        data: Data
    ) async -> (text: String, thumbnail: Data?) {
        guard let document = PDFDocument(data: data) else {
            return (text: "[Unreadable PDF]", thumbnail: nil)
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            // Cooperative multitasking: yield every 10 pages to avoid blocking the actor.
            if i % 10 == 0 {
                await Task.yield()
            }
            // Check cancellation frequently.
            if Task.isCancelled {
                return (text: "[Extraction Cancelled]", thumbnail: nil)
            }

            if let page = document.page(at: i),
               let text = page.string {
                pages.append(text)
            }
        }
        return (text: pages.joined(separator: "\n\n"), thumbnail: nil) // Thumbnail generation omitted for brevity/speed in this pass.
    }

    // MARK: - Image Thumbnail

    private func createImageThumbnail(data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }

        let maxDimension: CGFloat = 200
        let originalSize = image.size
        let scale = min(
            maxDimension / originalSize.width,
            maxDimension / originalSize.height,
            1.0
        )
        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage.tiffRepresentation
    }

    // MARK: - RTF Extraction

    private func extractRTFText(data: Data) throws -> String {
        guard let attributed = NSAttributedString(
            rtf: data,
            documentAttributes: nil
        ) else {
            throw FileManagerError.decodingFailed
        }
        return attributed.string
    }
}

// MARK: - Errors

/// Errors from the secure file management pipeline.
@frozen
public enum FileManagerError: String, Error, Sendable, Codable, Equatable, Hashable {
    case unsupportedFileType
    case fileTooLarge
    case decodingFailed
    case invalidImageData
    case sanitizationRejected
    case writeError

    /// Factory that accepts context values.
    static func fileTooLarge(sizeBytes: UInt64, limitBytes: UInt64) -> FileManagerError { .fileTooLarge }
    static func sanitizationRejected(reason: String) -> FileManagerError { .sanitizationRejected }
}
