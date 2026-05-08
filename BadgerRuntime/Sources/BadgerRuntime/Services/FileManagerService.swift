import Foundation
import BadgerCore

// MARK: - File Manager Errors

public enum FileManagerError: Error, Sendable {
    case invalidPath(String)
    case accessDenied(String)
    case fileNotFound(URL)
    case sizeLimitExceeded(limit: Int64, observed: Int64)
    case typeMismatched(expected: String, observed: String)
    case writeFailed(String)
    case deletionFailed(String)
}

// MARK: - File Validation Policy

public struct FileValidationPolicy: Sendable {
    public let allowedRoots: [URL]
    public let maxFileSize: Int64
    public let allowedExtensions: Set<String>
    public let blockedExtensions: Set<String>
    public let requireMagicNumberMatch: Bool

    public init(
        allowedRoots: [URL] = [],
        maxFileSize: Int64 = 10 * 1024 * 1024 * 1024, // 10GB default for models
        allowedExtensions: Set<String> = [],
        blockedExtensions: Set<String> = [".exe", ".sh", ".py", ".php", ".js"],
        requireMagicNumberMatch: Bool = true
    ) {
        self.allowedRoots = allowedRoots
        self.maxFileSize = maxFileSize
        self.allowedExtensions = allowedExtensions
        self.blockedExtensions = blockedExtensions
        self.requireMagicNumberMatch = requireMagicNumberMatch
    }

    public static let `default` = FileValidationPolicy()

    public static let models = FileValidationPolicy(
        allowedExtensions: ["json", "txt", "model", "safetensors", "tiktoken", "bin"],
        blockedExtensions: [".sh", ".py"]
    )
}

// MARK: - FileManagerService

/// Actor responsible for sandboxed, validated file system access.
/// Ensures all I/O is restricted to allowed roots and adheres to safety policies.
public actor FileManagerService {

    private let fileManager: FileManager
    private let policy: FileValidationPolicy
    private let auditService: AuditLogService

    public init(
        policy: FileValidationPolicy = .default,
        fileManager: FileManager = .default,
        auditService: AuditLogService = AuditLogService()
    ) {
        self.policy = policy
        self.fileManager = fileManager
        self.auditService = auditService
    }

    // MARK: - Public API

    public func fileExists(at url: URL, isDirectory: UnsafeMutablePointer<ObjCBool>? = nil) -> Bool {
        guard (try? validatePath(url)) != nil else { return false }
        return fileManager.fileExists(atPath: url.path, isDirectory: isDirectory)
    }

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool = true) throws {
        try validatePath(url)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }

    public func removeItem(at url: URL) throws {
        try validatePath(url)
        try fileManager.removeItem(at: url)
    }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        // Source might be outside if it's a temp download
        try validatePath(dstURL)

        if fileManager.fileExists(atPath: dstURL.path) {
            try fileManager.removeItem(at: dstURL)
        }

        try fileManager.moveItem(at: srcURL, to: dstURL)
    }

    public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil) throws -> [URL] {
        try validatePath(url)
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
    }

    public func readFile(at url: URL) throws -> Data {
        try validatePath(url)
        try validateFileAttributes(url)
        return try Data(contentsOf: url)
    }

    public func readFileMapped(at url: URL) throws -> Data {
        try validatePath(url)
        try validateFileAttributes(url)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    // MARK: - Internal Validation

    private func validatePath(_ url: URL) throws {
        let normalizedPath = url.standardized.path

        // Block path traversal attempts
        if normalizedPath.contains("..") {
            throw FileManagerError.accessDenied("Path traversal detected")
        }

        // If allowedRoots is specified, ensure normalizedPath is within one of them
        if !policy.allowedRoots.isEmpty {
            let isAllowed = policy.allowedRoots.contains { root in
                normalizedPath.hasPrefix(root.standardized.path)
            }
            if !isAllowed {
                throw FileManagerError.accessDenied("Path is outside of allowed roots: \(normalizedPath)")
            }
        }

        // Extension check
        let ext = url.pathExtension.lowercased()
        if !policy.allowedExtensions.isEmpty && !policy.allowedExtensions.contains(ext) {
            throw FileManagerError.accessDenied("Extension not allowed: \(ext)")
        }

        if policy.blockedExtensions.contains(".\(ext)") {
            throw FileManagerError.accessDenied("Extension is blocked: \(ext)")
        }
    }

    private func validateFileAttributes(_ url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int64 else {
            throw FileManagerError.invalidPath("Could not determine file size")
        }

        if size > policy.maxFileSize {
            throw FileManagerError.sizeLimitExceeded(limit: policy.maxFileSize, observed: size)
        }

        if policy.requireMagicNumberMatch {
            try validateMagicNumber(at: url)
        }
    }

    private func validateMagicNumber(at url: URL) throws {
        // Very basic implementation: check if JSON files actually start with { or [
        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            if let firstByte = try handle.read(upToCount: 1)?.first {
                if firstByte != 123 && firstByte != 91 { // { or [
                    throw FileManagerError.typeMismatched(expected: "JSON", observed: "Unknown (Magic number mismatch)")
                }
            }
        }
        // Safetensors and other formats would have more complex magic number checks here
    }
}
