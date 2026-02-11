import Foundation

/// A single error log entry.
///
/// All entries use plain‑language summaries — no stack traces,
/// no internal terminology, no error codes.
public struct ErrorEntry: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: AppLogger.Category
    public let severity: AppLogger.Severity
    public let summary: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: AppLogger.Category,
        severity: AppLogger.Severity,
        summary: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.severity = severity
        self.summary = summary
    }
}

/// Filter criteria for querying the error log.
public struct ErrorLogFilter: Sendable {
    public let category: AppLogger.Category?
    public let severity: AppLogger.Severity?
    public let since: Date?

    public init(
        category: AppLogger.Category? = nil,
        severity: AppLogger.Severity? = nil,
        since: Date? = nil
    ) {
        self.category = category
        self.severity = severity
        self.since = since
    }
}

/// Actor‑isolated, append‑only persistent error log.
public actor ErrorLog {

    private let maxEntries: Int
    private let logFileURL: URL
    private var entries: [ErrorEntry] = []
    private var isLoaded: Bool = false
    
    // Cache the file handle to avoid opening/closing it constantly
    private var fileHandle: FileHandle?

    public init(maxEntries: Int = 5000) {
        self.maxEntries = maxEntries
        
        // 🔒 SAFETY: Safe unwrap of App Support directory
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = paths.first ?? FileManager.default.temporaryDirectory
        self.logFileURL = root.appendingPathComponent("QuantumBadger/error_log.jsonl")
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    public func append(_ entry: ErrorEntry) {
        ensureLoaded()
        
        entries.append(entry)
        
        // ⚡️ PERF: Append single line to file instead of rewriting everything
        if let data = try? JSONEncoder.iso8601.encode(entry),
           let string = String(data: data, encoding: .utf8) {
            
            let line = string + "\n"
            if let lineData = line.data(using: .utf8) {
                appendToFile(lineData)
            }
        }

        // Rotate only if absolutely necessary (expensive operation)
        if entries.count > maxEntries {
            rotateLog()
        }
    }

    public func entries(filter: ErrorLogFilter = ErrorLogFilter()) -> [ErrorEntry] {
        ensureLoaded()
        return entries.filter { entry in
            if let category = filter.category, entry.category != category { return false }
            if let severity = filter.severity, entry.severity != severity { return false }
            if let since = filter.since, entry.timestamp < since { return false }
            return true
        }
    }
    
    public func entryCount() -> Int {
        ensureLoaded()
        return entries.count
    }
    
    public func exportAsJSON() -> Data? {
        ensureLoaded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(entries)
    }

    // MARK: - Private Persistence

    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true
        
        // Create directory if missing
        let dir = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

        // Load existing
        do {
            let data = try Data(contentsOf: logFileURL)
            let decoder = JSONDecoder.iso8601
            // Simple split by newline
            let lines = data.split(separator: 10) // 10 is '\n'
            
            self.entries = lines.compactMap { line in
                try? decoder.decode(ErrorEntry.self, from: line)
            }
        } catch {
            print("Failed to load error log: \(error)")
            self.entries = []
        }
    }
    
    private func appendToFile(_ data: Data) {
        do {
            if fileHandle == nil {
                // Open for writing, create if needed
                let dir = logFileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                
                if !FileManager.default.fileExists(atPath: logFileURL.path) {
                     try "".write(to: logFileURL, atomically: true, encoding: .utf8)
                }
                fileHandle = try FileHandle(forWritingTo: logFileURL)
                fileHandle?.seekToEndOfFile()
            }
            fileHandle?.write(data)
        } catch {
            print("Failed to write to error log: \(error)")
        }
    }

    private func rotateLog() {
        let keepCount = maxEntries / 2
        entries = Array(entries.suffix(keepCount))
        
        // Close handle to allow safe rewrite
        try? fileHandle?.close()
        fileHandle = nil
        
        // Rewrite the truncated log to disk (Expensive but rare)
        let encoder = JSONEncoder.iso8601
        let combinedData = entries
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
            .data(using: .utf8)
        
        try? combinedData?.write(to: logFileURL, options: .atomic)
    }
}

// Helper extensions for consistent encoding
private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
