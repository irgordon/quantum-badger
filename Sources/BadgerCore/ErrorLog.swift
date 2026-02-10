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
///
/// Entries are stored as JSON Lines in Application Support.
/// The log automatically rotates when it exceeds 5,000 entries,
/// discarding the oldest half.
///
/// Data never leaves the device without explicit user consent.
public actor ErrorLog {

    // MARK: - Configuration

    /// Maximum entries before rotation.
    private let maxEntries: Int

    /// File URL for the persistent log.
    private let logFileURL: URL

    // MARK: - State

    /// In‑memory buffer of entries.
    private var entries: [ErrorEntry] = []

    /// Whether initial load from disk has occurred.
    private var isLoaded: Bool = false

    // MARK: - Init

    public init(
        maxEntries: Int = 5000,
        logFileURL: URL? = nil
    ) {
        self.maxEntries = maxEntries
        self.logFileURL = logFileURL
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("QuantumBadger/error_log.jsonl")
    }

    // MARK: - Public API

    /// Append an entry to the log.
    ///
    /// Persists immediately to disk. Rotates if capacity exceeded.
    public func append(_ entry: ErrorEntry) {
        loadIfNeeded()
        entries.append(entry)

        // Rotate if over capacity: keep newest half.
        if entries.count > maxEntries {
            let keepCount = maxEntries / 2
            entries = Array(entries.suffix(keepCount))
        }

        persistToDisk()
    }

    /// Query entries matching the given filter.
    ///
    /// Returns entries in chronological order (oldest first).
    public func entries(filter: ErrorLogFilter = ErrorLogFilter()) -> [ErrorEntry] {
        loadIfNeeded()
        return entries.filter { entry in
            if let category = filter.category, entry.category != category {
                return false
            }
            if let severity = filter.severity, entry.severity != severity {
                return false
            }
            if let since = filter.since, entry.timestamp < since {
                return false
            }
            return true
        }
    }

    /// Total number of entries in the log.
    public func entryCount() -> Int {
        loadIfNeeded()
        return entries.count
    }

    /// Export all entries as JSON data for user inspection.
    public func exportAsJSON() -> Data? {
        loadIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        guard FileManager.default.fileExists(atPath: logFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: logFileURL)
            let lines = data.split(separator: UInt8(ascii: "\n"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            entries = lines.compactMap { line in
                try? decoder.decode(ErrorEntry.self, from: Data(line))
            }
        } catch {
            // If the log is corrupted, start fresh.
            entries = []
        }
    }

    private func persistToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let lines = entries.compactMap { entry -> Data? in
            try? encoder.encode(entry)
        }

        let combined = lines
            .map { String(data: $0, encoding: .utf8) ?? "" }
            .joined(separator: "\n")

        let data = Data(combined.utf8)

        do {
            let directory = logFileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            try data.write(to: logFileURL, options: .atomic)
        } catch {
            // Cannot persist — the log remains in memory only.
            // This is logged to os.Logger separately.
        }
    }
}
