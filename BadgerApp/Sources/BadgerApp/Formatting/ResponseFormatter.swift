import Foundation
import BadgerCore

// MARK: - Format Detection Result

/// Result of analyzing content format
public struct FormatDetectionResult: Sendable {
    public let containsCode: Bool
    public let containsTable: Bool
    public let containsMarkdown: Bool
    public let estimatedCharacterCount: Int
    public let recommendedFormat: OutputFormat
    
    public enum OutputFormat: Sendable {
        case plainText
        case markdownFile
        case codeFile(language: String)
    }
    
    public var exceedsMessageLimit: Bool {
        estimatedCharacterCount > ResponseFormatter.messageCharacterLimit
    }
}

// MARK: - Response Formatter

/// Formats responses for messaging platforms, detecting code/tables and creating files when needed
public actor ResponseFormatter {
    
    // MARK: - Constants
    
    /// iMessage character limit (with some buffer)
    public static let messageCharacterLimit = 4000
    
    /// Characters that might indicate code blocks
    private static let codeBlockIndicators = ["```", "~~~"]
    
    /// Table detection patterns
    private static let tablePatterns = [
        #"\|[^\n]+\|"#,  // Pipe-delimited
        #"^\s*[-|]+\s*$"#  // Markdown table separator
    ]
    
    /// Programming language detection
    private static let languageIndicators: [String: [String]] = [
        "swift": ["import Foundation", "func ", "var ", "let ", "class ", "struct "],
        "python": ["import ", "def ", "class ", "print(", "if __name__"],
        "javascript": ["const ", "let ", "function", "=>", "console.log"],
        "json": ["{", "}", "[", "]", "\""],
        "bash": ["#!/bin/bash", "echo ", "cd ", "ls ", "chmod "],
        "sql": ["SELECT ", "INSERT ", "UPDATE ", "DELETE ", "FROM ", "WHERE "],
        "markdown": ["# ", "## ", "### ", "- ", "* ", "> ", "[", "]("]
    ]
    
    // MARK: - Properties
    
    private let tempDirectory: URL
    private let fileManager: FileManager
    
    // MARK: - Initialization
    
    public init(tempDirectory: URL? = nil) {
        self.fileManager = FileManager.default
        
        if let tempDir = tempDirectory {
            self.tempDirectory = tempDir
        } else {
            self.tempDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("BadgerResponses", isDirectory: true)
        }
        
        // Create temp directory if needed
        try? fileManager.createDirectory(
            at: self.tempDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Main Formatting Method
    
    /// Format content for the specified source
    /// - Parameters:
    ///   - content: The raw content to format
    ///   - source: The destination source (determines formatting rules)
    /// - Returns: Formatted output, possibly as a file
    public func format(
        content: String,
        source: ExecutionContext.CommandSource
    ) async throws -> FormattedOutput {
        // Detect format
        let detection = detectFormat(in: content)
        
        // Determine if we need to create a file
        let needsFile = shouldCreateFile(
            detection: detection,
            source: source
        )
        
        if needsFile {
            return try await createFileOutput(
                content: content,
                detection: detection,
                source: source
            )
        } else {
            // Return as plain text
            return FormattedOutput(
                content: content,
                format: detection.containsMarkdown ? .markdown : .plainText,
                filename: "response.txt"
            )
        }
    }
    
    // MARK: - Format Detection
    
    /// Detect what formats are present in the content
    public func detectFormat(in content: String) -> FormatDetectionResult {
        let characterCount = content.count
        
        // Check for code blocks
        let containsCodeBlocks = ResponseFormatter.codeBlockIndicators.contains { indicator in
            content.contains(indicator)
        }
        
        // Check for inline code patterns
        let containsInlineCode = content.contains("`") && !containsCodeBlocks
        
        // Check for tables
        let containsTable = ResponseFormatter.tablePatterns.contains { pattern in
            content.range(of: pattern, options: .regularExpression) != nil
        }
        
        // Check for markdown
        let containsMarkdown = ResponseFormatter.languageIndicators["markdown"]?.contains { indicator in
            content.contains(indicator)
        } ?? false
        
        // Detect primary language if code is present
        let detectedLanguage = detectPrimaryLanguage(in: content)
        
        // Determine recommended format
        let recommendedFormat: FormatDetectionResult.OutputFormat
        if let language = detectedLanguage, containsCodeBlocks || containsInlineCode {
            recommendedFormat = .codeFile(language: language)
        } else if containsMarkdown || containsTable {
            recommendedFormat = .markdownFile
        } else {
            recommendedFormat = .plainText
        }
        
        return FormatDetectionResult(
            containsCode: containsCodeBlocks || containsInlineCode,
            containsTable: containsTable,
            containsMarkdown: containsMarkdown,
            estimatedCharacterCount: characterCount,
            recommendedFormat: recommendedFormat
        )
    }
    
    /// Detect the primary programming language in code
    private func detectPrimaryLanguage(in content: String) -> String? {
        var scores: [String: Int] = [:]
        
        for (language, indicators) in ResponseFormatter.languageIndicators where language != "markdown" {
            let score = indicators.reduce(0) { count, indicator in
                count + content.components(separatedBy: indicator).count - 1
            }
            if score > 0 {
                scores[language] = score
            }
        }
        
        return scores.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - File Creation Logic
    
    private func shouldCreateFile(
        detection: FormatDetectionResult,
        source: ExecutionContext.CommandSource
    ) -> Bool {
        // Always create file if it exceeds character limit
        if detection.exceedsMessageLimit {
            return true
        }
        
        // Create file for code-heavy content on messaging platforms
        switch source {
        case .imessage, .whatsapp, .telegram:
            // Create file if contains code blocks or complex tables
            if detection.containsCode && detection.estimatedCharacterCount > 1000 {
                return true
            }
            if detection.containsTable && detection.estimatedCharacterCount > 500 {
                return true
            }
            return false
            
        case .slack:
            // Slack handles code better, but still file for very long content
            return detection.exceedsMessageLimit
            
        case .shortcuts, .siri, .internalApp, .widget:
            // Let the caller decide for these
            return false
        }
    }
    
    private func createFileOutput(
        content: String,
        detection: FormatDetectionResult,
        source: ExecutionContext.CommandSource
    ) async throws -> FormattedOutput {
        let (filename, fileExtension): (String, String)
        let formattedContent: String
        
        switch detection.recommendedFormat {
        case .plainText:
            filename = "response"
            fileExtension = "txt"
            formattedContent = content
            
        case .markdownFile:
            filename = "response"
            fileExtension = "md"
            formattedContent = formatAsMarkdown(content)
            
        case .codeFile(let language):
            filename = "code_snippet"
            fileExtension = fileExtensionForLanguage(language)
            formattedContent = formatAsCode(content, language: language)
        }
        
        // Add timestamp to filename to avoid collisions
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let uniqueFilename = "\(filename)_\(timestamp).\(fileExtension)"
        let fileURL = tempDirectory.appendingPathComponent(uniqueFilename)
        
        // Write to file
        try formattedContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Add metadata header for messaging platforms
        if source == .imessage || source == .whatsapp || source == .telegram {
            try await addMetadataToFile(fileURL: fileURL, content: formattedContent, detection: detection)
        }
        
        return FormattedOutput(
            content: formattedContent,
            format: fileExtension == "md" ? .markdown : (fileExtension == "txt" ? .plainText : .code),
            filename: uniqueFilename,
            fileURL: fileURL
        )
    }
    
    // MARK: - Formatting Helpers
    
    private func formatAsMarkdown(_ content: String) -> String {
        var formatted = content
        
        // Ensure proper code block formatting
        if !formatted.hasPrefix("#") && !formatted.hasPrefix("```") {
            // Add a title if missing
            formatted = "# Quantum Badger Response\n\n" + formatted
        }
        
        // Add timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        formatted += "\n\n---\n*Generated: \(dateFormatter.string(from: Date()))*"
        
        return formatted
    }
    
    private func formatAsCode(_ content: String, language: String) -> String {
        var formatted = ""
        
        // Add shebang if appropriate
        if language == "swift" {
            formatted = "#!/usr/bin/env swift\n\n"
        } else if language == "python" {
            formatted = "#!/usr/bin/env python3\n\n"
        } else if language == "bash" {
            formatted = "#!/bin/bash\n\n"
        }
        
        formatted += content
        
        // Add footer
        formatted += "\n\n// Generated by Quantum Badger"
        
        return formatted
    }
    
    private func fileExtensionForLanguage(_ language: String) -> String {
        switch language {
        case "swift": return "swift"
        case "python": return "py"
        case "javascript": return "js"
        case "json": return "json"
        case "bash", "shell": return "sh"
        case "sql": return "sql"
        case "markdown": return "md"
        default: return "txt"
        }
    }
    
    private func addMetadataToFile(
        fileURL: URL,
        content: String,
        detection: FormatDetectionResult
    ) async throws {
        var metadata = "<!--\n"
        metadata += "Generated by: Quantum Badger\n"
        metadata += "Timestamp: \(ISO8601DateFormatter().string(from: Date()))\n"
        metadata += "Format: \(detection.recommendedFormat)\n"
        metadata += "Characters: \(detection.estimatedCharacterCount)\n"
        if detection.containsCode {
            metadata += "Contains: Code\n"
        }
        if detection.containsTable {
            metadata += "Contains: Tables\n"
        }
        metadata += "-->\n\n"
        
        let finalContent = metadata + content
        try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Cleanup
    
    /// Clean up old temporary files
    public func cleanupOldFiles(olderThan age: TimeInterval = 86400) async throws {
        let files = try fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )
        
        let now = Date()
        for file in files {
            let attributes = try fileManager.attributesOfItem(atPath: file.path)
            if let creationDate = attributes[.creationDate] as? Date {
                if now.timeIntervalSince(creationDate) > age {
                    try fileManager.removeItem(at: file)
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension ResponseFormatter {
    /// Quick check if content should be returned as file
    public func shouldReturnAsFile(_ content: String, source: ExecutionContext.CommandSource) -> Bool {
        let detection = detectFormat(in: content)
        return shouldCreateFile(detection: detection, source: source)
    }
    
    /// Format for iMessage specifically
    public func formatForMessage(_ content: String) async throws -> FormattedOutput {
        try await format(content: content, source: .imessage)
    }
}
