import Foundation
import CryptoKit

// MARK: - Audit Event Types

/// Types of events that can be logged by the AuditLogService
public enum AuditEventType: String, Sendable, Codable, CaseIterable {
    case remoteCommandReceived = "RemoteCommandReceived"
    case shadowRouterDecision = "ShadowRouterDecision"
    case piiRedaction = "PIIRedaction"
    case policyChange = "PolicyChange"
    case keyAccess = "KeyAccess"
    case sanitizationTriggered = "SanitizationTriggered"
    case authenticationFailure = "AuthenticationFailure"
}

// MARK: - Audit Event

/// Represents a single audit log entry
public struct AuditEvent: Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let type: AuditEventType
    public let source: String
    public let details: String
    public let previousHash: String
    public let hash: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: AuditEventType,
        source: String,
        details: String,
        previousHash: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.source = source
        self.details = details
        self.previousHash = previousHash
        self.hash = Self.computeHash(
            id: id,
            timestamp: timestamp,
            type: type,
            source: source,
            details: details,
            previousHash: previousHash
        )
    }
    
    /// Computes SHA-256 hash of the event data including the previous hash for chaining
    static func computeHash(
        id: UUID,
        timestamp: Date,
        type: AuditEventType,
        source: String,
        details: String,
        previousHash: String
    ) -> String {
        var hasher = SHA256()
        
        hasher.update(data: id.uuidString.data(using: .utf8)!)
        hasher.update(data: String(timestamp.timeIntervalSince1970).data(using: .utf8)!)
        hasher.update(data: type.rawValue.data(using: .utf8)!)
        hasher.update(data: source.data(using: .utf8)!)
        hasher.update(data: details.data(using: .utf8)!)
        hasher.update(data: previousHash.data(using: .utf8)!)
        
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Verifies the integrity of this event's hash
    public func verifyHash() -> Bool {
        let computed = Self.computeHash(
            id: id,
            timestamp: timestamp,
            type: type,
            source: source,
            details: details,
            previousHash: previousHash
        )
        return computed == hash
    }
}

// MARK: - Audit Log Configuration

/// Configuration for the AuditLogService
public struct AuditLogConfiguration: Sendable {
    public let logDirectory: URL
    public let maxFileSize: Int
    public let maxArchivedFiles: Int
    
    public init(
        logDirectory: URL? = nil,
        maxFileSize: Int = 10 * 1024 * 1024, // 10MB
        maxArchivedFiles: Int = 10
    ) {
        if let logDirectory = logDirectory {
            self.logDirectory = logDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.logDirectory = appSupport
                .appendingPathComponent("QuantumBadger")
                .appendingPathComponent("AuditLogs")
        }
        self.maxFileSize = maxFileSize
        self.maxArchivedFiles = maxArchivedFiles
    }
}

// MARK: - Audit Log Errors

/// Errors that can occur during audit logging operations
public enum AuditLogError: Error, Sendable {
    case directoryCreationFailed
    case writeFailed
    case readFailed
    case hashChainBroken
    case invalidLogFormat
}

// MARK: - Audit Log Service

/// Actor responsible for writing tamper-evident audit logs using chained SHA-256 hashing
public actor AuditLogService {
    
    private let configuration: AuditLogConfiguration
    private var lastHash: String
    private var currentLogFile: URL
    private var isInitialized: Bool = false
    
    /// Initialize the audit log service
    /// - Parameter configuration: Configuration for log storage and rotation
    public init(configuration: AuditLogConfiguration = AuditLogConfiguration()) {
        self.configuration = configuration
        self.lastHash = String(repeating: "0", count: 64) // Genesis hash
        self.currentLogFile = configuration.logDirectory.appendingPathComponent("audit.log")
    }
    
    /// Initialize the log directory and verify/load existing chain
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        try createLogDirectoryIfNeeded()
        try await loadLastHashFromExistingLogs()
        isInitialized = true
    }
    
    /// Log a new audit event with tamper-evident chaining
    /// - Parameters:
    ///   - type: The type of event being logged
    ///   - source: The source component that generated the event
    ///   - details: Additional details about the event
    /// - Returns: The logged audit event
    @discardableResult
    public func log(
        type: AuditEventType,
        source: String,
        details: String
    ) async throws -> AuditEvent {
        if !isInitialized {
            try await initialize()
        }
        
        // Check if log rotation is needed
        try await rotateLogIfNeeded()
        
        let event = AuditEvent(
            type: type,
            source: source,
            details: details,
            previousHash: lastHash
        )
        
        // Append to log file
        try await appendEvent(event)
        
        // Update the chain
        lastHash = event.hash
        
        return event
    }
    
    /// Verify the integrity of the entire log chain
    /// - Returns: True if the chain is intact, false if tampering is detected
    public func verifyChain() async throws -> Bool {
        let logFiles = try getAllLogFiles()
        var expectedPreviousHash = String(repeating: "0", count: 64)
        
        for logFile in logFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let event = try? JSONDecoder().decode(AuditEvent.self, from: data) else {
                    continue
                }
                
                // Verify chain continuity
                guard event.previousHash == expectedPreviousHash else {
                    return false
                }
                
                // Verify event hash
                guard event.verifyHash() else {
                    return false
                }
                
                expectedPreviousHash = event.hash
            }
        }
        
        return true
    }
    
    /// Get all audit events from the logs
    /// - Returns: Array of all logged events
    public func getAllEvents() async throws -> [AuditEvent] {
        let logFiles = try getAllLogFiles()
        var events: [AuditEvent] = []
        
        for logFile in logFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                if let event = try? JSONDecoder().decode(AuditEvent.self, from: data) {
                    events.append(event)
                }
            }
        }
        
        return events.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Export logs to a specified URL
    /// - Parameter destination: URL to export logs to
    public func exportLogs(to destination: URL) async throws {
        let events = try await getAllEvents()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(events)
        try data.write(to: destination)
    }
    
    // MARK: - Private Methods
    
    private func createLogDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: configuration.logDirectory.path) {
            try fileManager.createDirectory(
                at: configuration.logDirectory,
                withIntermediateDirectories: true,
                attributes: [
                    FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen
                ]
            )
        }
    }
    
    private func loadLastHashFromExistingLogs() async throws {
        let logFiles = try getAllLogFiles()
        
        guard let latestLog = logFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last,
              FileManager.default.fileExists(atPath: latestLog.path) else {
            return
        }
        
        let content = try String(contentsOf: latestLog, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if let lastLine = lines.last,
           let data = lastLine.data(using: .utf8),
           let event = try? JSONDecoder().decode(AuditEvent.self, from: data) {
            lastHash = event.hash
            currentLogFile = latestLog
        }
    }
    
    private func appendEvent(_ event: AuditEvent) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        let data = try encoder.encode(event)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AuditLogError.writeFailed
        }
        
        let fileHandle = try FileHandle(forWritingTo: currentLogFile)
        defer { try? fileHandle.close() }
        
        try fileHandle.seekToEnd()
        
        guard let lineData = (jsonString + "\n").data(using: .utf8) else {
            throw AuditLogError.writeFailed
        }
        
        try fileHandle.write(contentsOf: lineData)
    }
    
    private func rotateLogIfNeeded() async throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: currentLogFile.path) else {
            return
        }
        
        let attributes = try fileManager.attributesOfItem(atPath: currentLogFile.path)
        if let fileSize = attributes[.size] as? Int,
           fileSize >= configuration.maxFileSize {
            
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let archivedName = "audit_\(timestamp).log"
            let archivedPath = configuration.logDirectory.appendingPathComponent(archivedName)
            
            try fileManager.moveItem(at: currentLogFile, to: archivedPath)
            
            // Clean up old archived files
            try cleanupOldArchives()
        }
    }
    
    private func cleanupOldArchives() throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: configuration.logDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )
        
        let archiveFiles = files.filter { $0.lastPathComponent.hasPrefix("audit_") && $0 != currentLogFile }
        
        guard archiveFiles.count > configuration.maxArchivedFiles else { return }
        
        let sortedArchives = try archiveFiles.sorted {
            let attrs1 = try fileManager.attributesOfItem(atPath: $0.path)
            let attrs2 = try fileManager.attributesOfItem(atPath: $1.path)
            let date1 = attrs1[.creationDate] as? Date ?? Date.distantPast
            let date2 = attrs2[.creationDate] as? Date ?? Date.distantPast
            return date1 < date2
        }
        
        let filesToDelete = sortedArchives.dropLast(configuration.maxArchivedFiles)
        for file in filesToDelete {
            try fileManager.removeItem(at: file)
        }
    }
    
    private func getAllLogFiles() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configuration.logDirectory.path) else {
            return []
        }
        
        let files = try fileManager.contentsOfDirectory(
            at: configuration.logDirectory,
            includingPropertiesForKeys: nil
        )
        
        return files.filter { $0.pathExtension == "log" }
    }
}
