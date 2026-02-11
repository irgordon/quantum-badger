import Foundation

// MARK: - Protocols

/// Dependency for semantically compressing memory.
public protocol MemorySummarizer: Sendable {
    /// Compresses a list of messages into a concise summary string.
    func summarize(_ messages: [QuantumMessage]) async throws -> String
}

// MARK: - Models

/// Metadata for a stored conversation.
public struct ConversationArchiveMetadata: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let date: Date
    public let summary: String
    public let messageCount: Int
}

// MARK: - Actor

/// Versioned conversation memory with compaction, archival, and purge.
public actor MemoryController {

    // MARK: - Configuration

    public let maxEntries: Int
    public let compactionRetainCount: Int
    private let archiveDirectory: URL
    
    /// Optional: The engine used to semantically compress old memories.
    /// If nil, falls back to simple concatenation.
    private let summarizer: MemorySummarizer?

    // MARK: - State

    private var entries: [QuantumMessage] = []
    private var nextVersion: UInt64 = 0
    private var archivedConversationIDs: [UUID] = []
    
    public let conversationID: UUID
    private let signer = IdentityFingerprinter()

    // MARK: - Init

    public init(
        conversationID: UUID = UUID(),
        maxEntries: Int = 200,
        compactionRetainCount: Int = 50,
        summarizer: MemorySummarizer? = nil, // Injected dependency
        archiveDirectory: URL? = nil
    ) {
        self.conversationID = conversationID
        self.maxEntries = maxEntries
        self.compactionRetainCount = compactionRetainCount
        self.summarizer = summarizer
        
        // Safer directory resolution
        if let customDir = archiveDirectory {
            self.archiveDirectory = customDir
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first 
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.archiveDirectory = base.appendingPathComponent("QuantumBadger/ConversationArchive", isDirectory: true)
        }
    }

    // MARK: - Public API

    /// Append a new entry to the conversation.
    public func append(source: QuantumMessageSource, content: String) async {
        // Sign the message
        let signature = generateSignature(for: content)
        
        let entry = QuantumMessage(
            kind: .text,
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
            await compact()
        }
    }

    public func currentEntries() -> [QuantumMessage] {
        entries
    }

    public func archiveAndReset() throws {
        try archiveToDisk()
        archivedConversationIDs.append(conversationID)
        entries.removeAll()
        nextVersion = 0
    }

    public func loadArchive(id: UUID) throws {
        let url = archiveDirectory.appendingPathComponent("\(id.uuidString).json")
        let loaded = try restore(from: url)
        self.entries = loaded
        // Ensure version continuity prevents collision
        self.nextVersion = (loaded.map(\.version).max() ?? 0) + 1
    }

    public func listArchives() throws -> [ConversationArchiveMetadata] {
        let fm = FileManager.default
        
        // Ensure directory exists before reading
        if !fm.fileExists(atPath: archiveDirectory.path) { return [] }

        let urls = try fm.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
        
        return urls.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            
            // Extract UUID from filename
            let idString = url.deletingPathExtension().lastPathComponent
            guard let uuid = UUID(uuidString: idString) else { return nil }
            
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            
            // In production, you might cache this metadata separately 
            // to avoid reading every JSON file to get the count.
            return ConversationArchiveMetadata(
                id: uuid,
                date: date,
                summary: "Session \(date.formatted(date: .numeric, time: .shortened))",
                messageCount: 0 // Placeholder: would require peeking at JSON
            )
        }
    }

    // MARK: - Internal Logic

    private func compact() async {
        guard entries.count > compactionRetainCount else { return }

        let cutoff = entries.count - compactionRetainCount
        let olderEntries = Array(entries.prefix(cutoff))
        
        var summaryContent: String
        
        if let summarizer = summarizer {
            // A: Semantic Compression (AI)
            // We await the AI to turn the logs into a narrative
            do {
                summaryContent = try await summarizer.summarize(olderEntries)
                summaryContent = "Previously: " + summaryContent
            } catch {
                // Fallback to concatenation if AI fails
                summaryContent = concatenate(olderEntries)
            }
        } else {
            // B: Mechanical Concatenation
            summaryContent = concatenate(olderEntries)
        }

        let signature = generateSignature(for: summaryContent)
        
        let summaryEntry = QuantumMessage(
            kind: .text, // or .summary if your enum supports it
            source: .summary,
            content: summaryContent,
            createdAt: Date(),
            version: nextVersion,
            isVerified: signature != nil,
            signature: signature
        )
        
        nextVersion += 1
        
        // Replace old entries with summary + recent entries
        entries = [summaryEntry] + Array(entries.suffix(compactionRetainCount))
    }
    
    private func concatenate(_ messages: [QuantumMessage]) -> String {
        let text = messages.map { "[\($0.source.rawValue)] \($0.content)" }.joined(separator: "\n")
        return "--- Compacted \(messages.count) entries ---\n" + text
    }

    private func generateSignature(for content: String) -> String? {
        // Assuming IdentityFingerprinter is available in scope or imported
        guard let data = content.data(using: .utf8),
              let sigData = try? signer.sign(data) else { return nil }
        return sigData.map { String(format: "%02x", $0) }.joined()
    }

    private func archiveToDisk() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: archiveDirectory.path) {
            try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        }
        
        let fileURL = archiveDirectory.appendingPathComponent("\(conversationID.uuidString).json")
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func restore(from fileURL: URL) throws -> [QuantumMessage] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([QuantumMessage].self, from: data)
    }
}
