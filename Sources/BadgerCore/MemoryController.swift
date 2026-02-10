import Foundation

/// Versioned conversation memory with compaction, archival, and purge.
///
/// `MemoryController` enforces bounded context growth by:
/// - Versioning every entry with a monotonic counter
/// - Compacting older entries into summaries once the entry count
///   exceeds a configurable window
/// - Archiving full conversations to disk
/// - Allowing user‑initiated restore or purge
///
/// The controller is actor‑isolated to guarantee thread‑safe mutation
/// of the conversation buffer.
public actor MemoryController {

    // MARK: - Configuration

    /// Maximum number of entries before compaction is triggered.
    public let maxEntries: Int

    /// Maximum number of entries to keep verbatim after compaction.
    /// Older entries beyond this window are replaced with a summary.
    public let compactionRetainCount: Int

    /// Directory for archived conversations.
    private let archiveDirectory: URL

    // MARK: - State

    /// The live conversation buffer.
    private var entries: [QuantumMessage] = []

    /// Monotonically increasing version counter.
    private var nextVersion: UInt64 = 0

    /// Identifiers of archived conversations.
    private var archivedConversationIDs: [UUID] = []

    /// The current conversation identifier.
    public let conversationID: UUID
    
    /// Identity signer.
    private let signer = IdentityFingerprinter()

    // MARK: - Init

    public init(
        conversationID: UUID = UUID(),
        maxEntries: Int = 200,
        compactionRetainCount: Int = 50,
        archiveDirectory: URL? = nil
    ) {
        self.conversationID = conversationID
        self.maxEntries = maxEntries
        self.compactionRetainCount = compactionRetainCount
        self.archiveDirectory = archiveDirectory
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("QuantumBadger/ConversationArchive", isDirectory: true)
    }

    // MARK: - Public API

    // MARK: - Public API

    /// Append a new entry to the conversation.
    public func append(source: QuantumMessageSource, content: String) {
        // Structural Sovereignty: Sign every message.
        var signature: String?
        if let data = content.data(using: .utf8),
           let sigData = try? signer.sign(data) {
            signature = sigData.map { String(format: "%02x", $0) }.joined()
        }
        
        let entry = QuantumMessage(
            kind: .text, // Default to text for standard appends
            source: source,
            content: content,
            createdAt: Date(),
            version: nextVersion,
            isVerified: signature != nil,
            signature: signature
        )
        nextVersion += 1
        entries.append(entry)

        if entries.count > maxEntries {
            compact()
        }
    }

    /// Return the current conversation entries.
    public func currentEntries() -> [QuantumMessage] {
        entries
    }

    /// Return the number of entries in the live buffer.
    public func entryCount() -> Int {
        entries.count
    }

    /// Whether the conversation has undergone compaction.
    ///
    /// Returns `true` if any entry has the `.summary` source,
    /// indicating older entries were condensed.
    public func hasCompacted() -> Bool {
        entries.contains { $0.source == .summary }
    }

    /// Archive the current conversation to disk and reset the buffer.
    public func archiveAndReset() throws {
        try archiveToDisk()
        archivedConversationIDs.append(conversationID)
        entries.removeAll()
        nextVersion = 0
    }

    /// Purge the current conversation without archiving.
    public func purge() {
        entries.removeAll()
        nextVersion = 0
    }

    /// Restore entries from a previously archived conversation file.
    public func restore(from fileURL: URL) throws -> [QuantumMessage] {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(
            [QuantumMessage].self,
            from: data
        )
        return decoded
    }
    
    /// List all available archives.
    public func listArchives() throws -> [ConversationArchiveMetadata] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            else { return nil }
            
            // In a real app we'd peek at the file content for a summary.
            // Here we use filename as ID.
            let idString = url.deletingPathExtension().lastPathComponent
            guard let uuid = UUID(uuidString: idString) else { return nil }
            
            return ConversationArchiveMetadata(
                id: uuid,
                date: date,
                summary: "Session \(date.formatted(date: .numeric, time: .shortened))"
            )
        }
    }
    
    /// Load a specific archive by ID, replacing valid entries.
    public func loadArchive(id: UUID) throws {
        let url = archiveDirectory.appendingPathComponent("\(id.uuidString).json")
        let loaded = try restore(from: url)
        self.entries = loaded
        self.nextVersion = (loaded.max(by: { $0.version < $1.version })?.version ?? 0) + 1
    }
}

/// Metadata for a stored conversation.
public struct ConversationArchiveMetadata: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let date: Date
    public let summary: String
}

    // MARK: - Compaction

    /// Replace the oldest entries with a single summary entry,
    /// retaining only the most recent `compactionRetainCount` entries.
    private func compact() {
        guard entries.count > compactionRetainCount else { return }

        let cutoff = entries.count - compactionRetainCount
        let older = entries.prefix(cutoff)

        let summaryText = older.map { "[\($0.source.rawValue)] \($0.content)" }
            .joined(separator: "\n")
  
        let compactedSummary = "--- Compacted \(older.count) entries ---\n" + summaryText

        // Summaries are also signed.
        var signature: String?
        if let data = compactedSummary.data(using: .utf8),
           let sigData = try? signer.sign(data) {
            signature = sigData.map { String(format: "%02x", $0) }.joined()
        }
        
        let summaryEntry = QuantumMessage(
            kind: .text,
            source: .summary,
            content: compactedSummary,
            createdAt: Date(),
            version: nextVersion,
            isVerified: signature != nil,
            signature: signature
        )
        nextVersion += 1

        entries = [summaryEntry] + Array(entries.suffix(compactionRetainCount))
    }

    // MARK: - Disk Archival

    private func archiveToDisk() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: archiveDirectory.path) {
            try fm.createDirectory(
                at: archiveDirectory,
                withIntermediateDirectories: true
            )
        }
        let fileURL = archiveDirectory
            .appendingPathComponent("\(conversationID.uuidString).json")
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
