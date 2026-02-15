import Foundation
import CoreSpotlight
import UniformTypeIdentifiers // Replaces MobileCoreServices
import BadgerCore

// MARK: - Search Index Errors

public enum SearchIndexerError: Error, Sendable {
    case indexCreationFailed
    case indexingFailed(String)
    case deletionFailed(String)
    case invalidDomain
}

// MARK: - Indexed Item

/// Represents an item indexed for search
public struct IndexedItem: Sendable, Identifiable {
    public let id: String
    public let query: String
    public let response: String
    public let source: ExecutionContext.CommandSource
    public let timestamp: Date
    public let category: InteractionCategory
    public let metadata: [String: String]
    
    public enum InteractionCategory: String, Sendable, CaseIterable {
        case question = "Question"
        case code = "Code"
        case creative = "Creative"
        case analysis = "Analysis"
        case summary = "Summary"
        case general = "General"
        
        public var keywords: [String] {
            switch self {
            case .question:
                return ["question", "answer", "help", "what", "how", "why"]
            case .code:
                return ["code", "programming", "function", "script", "swift", "python"]
            case .creative:
                return ["creative", "story", "poem", "write", "draft"]
            case .analysis:
                return ["analysis", "analyze", "review", "evaluate"]
            case .summary:
                return ["summary", "summarize", "brief", "overview"]
            case .general:
                return ["general", "chat", "conversation"]
            }
        }
    }
    
    public init(
        id: String = UUID().uuidString,
        query: String,
        response: String,
        source: ExecutionContext.CommandSource,
        timestamp: Date = Date(),
        category: InteractionCategory,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.query = query
        self.response = response
        self.source = source
        self.timestamp = timestamp
        self.category = category
        self.metadata = metadata
    }
}

// MARK: - Search Query Result

/// Result from a search query
public struct SearchResult: Sendable, Identifiable {
    public let id: String
    public let query: String
    public let response: String
    public let relevance: Double
    public let timestamp: Date
    public let source: ExecutionContext.CommandSource
    
    public init(
        id: String,
        query: String,
        response: String,
        relevance: Double,
        timestamp: Date,
        source: ExecutionContext.CommandSource
    ) {
        self.id = id
        self.query = query
        self.response = response
        self.relevance = relevance
        self.timestamp = timestamp
        self.source = source
    }
}

// MARK: - Search Indexer

/// Actor responsible for indexing interactions for local Spotlight search
public actor SearchIndexer {
    
    // MARK: - Properties
    
    // Constants made static/nonisolated so helpers can access them safely
    private static let domainIdentifier = "com.quantumbadger.interactions"
    private static let maxIndexedCharacters = 50000
    
    private let index: CSSearchableIndex
    private let maxResults = 100
    private let auditService: AuditLogService
    private let clock: FunctionClock
    
    // In-memory cache for recently indexed items
    private var recentItems: [IndexedItem] = []
    private let maxRecentItems = 50
    
    // MARK: - Initialization
    
    public init(
        index: CSSearchableIndex? = nil,
        auditService: AuditLogService = AuditLogService(),
        clock: FunctionClock = SystemFunctionClock()
    ) {
        self.index = index ?? CSSearchableIndex.default()
        self.auditService = auditService
        self.clock = clock
    }
    
    // MARK: - Indexing
    
    /// Index an interaction for search
    /// - Parameters:
    ///   - query: The user's query
    ///   - response: The AI's response
    ///   - context: Execution context
    public func indexInteraction(
        query: String,
        response: String,
        context: ExecutionContext
    ) async {
        _ = await indexInteractionWithSLA(query: query, response: response, context: context)
    }
    
    public func indexInteractionWithSLA(
        query: String,
        response: String,
        context: ExecutionContext,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_000,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 2,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput("Query cannot be empty"))
        }
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput("Response cannot be empty"))
        }
        
        let category = Self.categorizeInteraction(query: query, response: response)
        let item = IndexedItem(
            query: query,
            response: response,
            source: context.source,
            timestamp: context.timestamp,
            category: category,
            metadata: [
                "source": context.source.rawValue,
                "userID": context.userID ?? "anonymous",
                "conversationID": context.conversationID ?? "single"
            ]
        )
        
        return await SLARuntimeGuard.run(
            functionName: "SearchIndexer.indexInteractionWithSLA",
            inputMaterial: "\(query)#\(response)#\(context.source.rawValue)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.indexItemCore(item)
            },
            outputMaterial: { _ in "indexed" }
        )
    }
    
    /// Index a complete interaction item
    public func indexItem(_ item: IndexedItem) async throws {
        let result = await indexItemWithSLA(item)
        switch result {
        case .success:
            return
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func indexItemWithSLA(
        _ item: IndexedItem,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_000,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 2,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        await SLARuntimeGuard.run(
            functionName: "SearchIndexer.indexItemWithSLA",
            inputMaterial: "\(item.id)#\(item.query)#\(item.source.rawValue)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.indexItemCore(item)
            },
            outputMaterial: { _ in "indexed" }
        )
    }
    
    /// Batch index multiple items
    public func indexItems(_ items: [IndexedItem]) async throws {
        let result = await indexItemsWithSLA(items)
        switch result {
        case .success:
            return
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func indexItemsWithSLA(
        _ items: [IndexedItem],
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 2_000,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 3,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        guard !items.isEmpty else {
            return .failure(.invalidInput("Items cannot be empty"))
        }
        
        return await SLARuntimeGuard.run(
            functionName: "SearchIndexer.indexItemsWithSLA",
            inputMaterial: items.map(\.id).joined(separator: ","),
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.indexItemsCore(items)
            },
            outputMaterial: { _ in "indexed-batch" }
        )
    }
    
    private func indexItemCore(_ item: IndexedItem) async throws {
        addToRecentItems(item)
        try await indexToSpotlight(item: item)
    }
    
    private func indexItemsCore(_ items: [IndexedItem]) async throws {
        for item in items {
            addToRecentItems(item)
        }
        let searchableItems = items.map { Self.createSearchableItem(from: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(searchableItems) { error in
                if let error = error {
                    continuation.resume(throwing: SearchIndexerError.indexingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Search
    
    /// Search indexed interactions
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results
    /// - Returns: Array of search results
    public func search(
        query: String,
        limit: Int = 20
    ) async throws -> [SearchResult] {
        let result = await searchWithSLA(query: query, limit: limit)
        switch result {
        case .success(let results):
            return results
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func searchWithSLA(
        query: String,
        limit: Int = 20,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_000,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 2,
            version: "v1"
        )
    ) async -> Result<[SearchResult], FunctionError> {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput("Query cannot be empty"))
        }
        guard limit > 0 && limit <= maxResults else {
            return .failure(.invalidInput("Limit must be between 1 and \(maxResults)"))
        }
        
        return await SLARuntimeGuard.run(
            functionName: "SearchIndexer.searchWithSLA",
            inputMaterial: "\(query)#\(limit)",
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.searchCore(query: query, limit: limit)
            },
            outputMaterial: { results in
                results.map(\.id).joined(separator: ",")
            }
        )
    }
    
    private func searchCore(query: String, limit: Int) async throws -> [SearchResult] {
        let queryString = Self.buildSearchQuery(query: query)
        let queryContext = CSSearchQueryContext()
        queryContext.fetchAttributes = ["title", "contentDescription", "keywords"]
        let searchQuery = CSSearchQuery(queryString: queryString, queryContext: queryContext)
        let accumulator = ResultAccumulator(limit: limit)
        
        return try await withCheckedThrowingContinuation { continuation in
            searchQuery.foundItemsHandler = { items in
                for item in items {
                    if let result = Self.parseSearchableItem(item) {
                        accumulator.add(result)
                        if accumulator.count >= limit {
                            searchQuery.cancel()
                            break
                        }
                    }
                }
            }
            
            searchQuery.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let finalResults = accumulator.getResults()
                    continuation.resume(returning: finalResults.sorted { $0.relevance > $1.relevance })
                }
            }
            
            searchQuery.start()
        }
    }
    
    /// Quick search in recent items (in-memory, faster)
    public func searchRecent(query: String, limit: Int = 10) -> [SearchResult] {
        let lowercasedQuery = query.lowercased()
        
        let matches = recentItems.filter { item in
            item.query.lowercased().contains(lowercasedQuery) ||
            item.response.lowercased().contains(lowercasedQuery)
        }
        
        return matches.prefix(limit).map { item in
            SearchResult(
                id: item.id,
                query: item.query,
                response: String(item.response.prefix(200)),
                relevance: 1.0, // High relevance for recent
                timestamp: item.timestamp,
                source: item.source
            )
        }
    }
    
    /// Get all recent items
    public func getRecentItems(limit: Int = 20) -> [IndexedItem] {
        Array(recentItems.prefix(limit))
    }
    
    // MARK: - Deletion
    
    /// Remove an item from the index
    public func removeItem(id: String) async throws {
        let result = await removeItemWithSLA(id: id)
        switch result {
        case .success:
            return
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func removeItemWithSLA(
        id: String,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_000,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 2,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        guard !id.isEmpty else {
            return .failure(.invalidInput("ID cannot be empty"))
        }
        
        return await SLARuntimeGuard.run(
            functionName: "SearchIndexer.removeItemWithSLA",
            inputMaterial: id,
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.removeItemCore(id: id)
            },
            outputMaterial: { _ in "deleted-item" }
        )
    }
    
    /// Remove all items for a specific domain
    public func removeAllItems() async throws {
        let result = await removeAllItemsWithSLA()
        switch result {
        case .success:
            return
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func removeAllItemsWithSLA(
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_500,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 3,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        await SLARuntimeGuard.run(
            functionName: "SearchIndexer.removeAllItemsWithSLA",
            inputMaterial: Self.domainIdentifier,
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.removeAllItemsCore()
            },
            outputMaterial: { _ in "deleted-all" }
        )
    }
    
    /// Remove old items (older than specified interval)
    public func removeOldItems(olderThan interval: TimeInterval) async throws {
        let result = await removeOldItemsWithSLA(olderThan: interval)
        switch result {
        case .success:
            return
        case .failure(let error):
            throw mapFunctionError(error)
        }
    }
    
    public func removeOldItemsWithSLA(
        olderThan interval: TimeInterval,
        sla: FunctionSLA = FunctionSLA(
            maxLatencyMs: 1_500,
            maxMemoryMb: 256,
            deterministic: true,
            timeoutSeconds: 3,
            version: "v1"
        )
    ) async -> Result<Void, FunctionError> {
        guard interval > 0 else {
            return .failure(.invalidInput("Interval must be greater than zero"))
        }
        
        return await SLARuntimeGuard.run(
            functionName: "SearchIndexer.removeOldItemsWithSLA",
            inputMaterial: String(interval),
            sla: sla,
            auditService: auditService,
            clock: clock,
            operation: {
                try await self.removeOldItemsCore(interval: interval)
            },
            outputMaterial: { _ in "deleted-old" }
        )
    }
    
    // MARK: - Statistics
    
    /// Get index statistics
    public func getStatistics() async -> [String: Int] {
        [
            "recentItems": recentItems.count,
            "maxRecentItems": maxRecentItems
        ]
    }
    
    private func mapFunctionError(_ error: FunctionError) -> SearchIndexerError {
        switch error {
        case .invalidInput(let message):
            return .indexingFailed(message)
        case .timeoutExceeded(let seconds):
            return .indexingFailed("Operation timed out after \(seconds)s")
        case .cancellationRequested:
            return .indexingFailed("Operation cancelled")
        case .memoryBudgetExceeded(let limit, let observed):
            return .indexingFailed("Memory budget exceeded \(observed)MB > \(limit)MB")
        case .deterministicViolation(let message):
            return .indexingFailed(message)
        case .executionFailed(let message):
            return .indexingFailed(message)
        }
    }
    
    private func removeItemCore(id: String) async throws {
        recentItems.removeAll { $0.id == id }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: [id]) { error in
                if let error = error {
                    continuation.resume(throwing: SearchIndexerError.deletionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func removeAllItemsCore() async throws {
        recentItems.removeAll()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                if let error = error {
                    continuation.resume(throwing: SearchIndexerError.deletionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func removeOldItemsCore(interval: TimeInterval) async throws {
        let cutoffDate = clock.now().addingTimeInterval(-interval)
        let itemsToRemove = recentItems.filter { $0.timestamp < cutoffDate }
        recentItems.removeAll { $0.timestamp < cutoffDate }
        let idsToRemove = itemsToRemove.map { $0.id }
        guard !idsToRemove.isEmpty else {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: idsToRemove) { error in
                if let error = error {
                    continuation.resume(throwing: SearchIndexerError.deletionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func addToRecentItems(_ item: IndexedItem) {
        recentItems.insert(item, at: 0)
        if recentItems.count > maxRecentItems {
            recentItems = Array(recentItems.prefix(maxRecentItems))
        }
    }
    
    private func indexToSpotlight(item: IndexedItem) async throws {
        let searchableItem = Self.createSearchableItem(from: item)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems([searchableItem]) { error in
                if let error = error {
                    continuation.resume(throwing: SearchIndexerError.indexingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // Made nonisolated to allow safe access from closures and background threads
    nonisolated private static func createSearchableItem(from item: IndexedItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
        
        // Truncate if needed
        let truncatedQuery = String(item.query.prefix(200))
        let truncatedResponse = String(item.response.prefix(Self.maxIndexedCharacters))
        
        // Title is the query
        attributeSet.title = truncatedQuery
        
        // Content is the response
        attributeSet.contentDescription = truncatedResponse
        
        // Keywords for better searchability
        var keywords: [String] = []
        keywords.append(contentsOf: item.category.keywords)
        keywords.append(item.source.rawValue)
        keywords.append(contentsOf: truncatedQuery.split(separator: " ").map { String($0) })
        attributeSet.keywords = keywords
        
        // Timestamp
        attributeSet.contentCreationDate = item.timestamp
        attributeSet.contentModificationDate = item.timestamp
        
        // Add metadata
        attributeSet.addedDate = item.timestamp
        attributeSet.creator = "Quantum Badger"
        
        return CSSearchableItem(
            uniqueIdentifier: item.id,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )
    }
    
    nonisolated private static func parseSearchableItem(_ item: CSSearchableItem) -> SearchResult? {
        let attributeSet = item.attributeSet
        
        return SearchResult(
            id: item.uniqueIdentifier,
            query: attributeSet.title ?? "",
            response: attributeSet.contentDescription ?? "",
            relevance: 0.5, // Default relevance
            timestamp: attributeSet.contentCreationDate ?? Date(),
            source: .internalApp // Source not stored in attribute set, default to internal
        )
    }
    
    nonisolated private static func buildSearchQuery(query: String) -> String {
        // Build a search query that looks in title and content
        let sanitizedQuery = query
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
        
        return "(title == \"*\(sanitizedQuery)*\" || contentDescription == \"*\(sanitizedQuery)*\" || keywords == \"*\(sanitizedQuery)*\")"
    }
    
    nonisolated private static func categorizeInteraction(query: String, response: String) -> IndexedItem.InteractionCategory {
        let combinedText = (query + " " + response).lowercased()
        
        // Check for code indicators
        if combinedText.contains("```") ||
           combinedText.contains("func ") ||
           combinedText.contains("def ") ||
           combinedText.contains("class ") ||
           combinedText.contains("import ") {
            return .code
        }
        
        // Check for questions
        if query.hasSuffix("?") ||
           combinedText.contains("what is") ||
           combinedText.contains("how to") ||
           combinedText.contains("why ") {
            return .question
        }
        
        // Check for creative writing
        if combinedText.contains("story") ||
           combinedText.contains("poem") ||
           combinedText.contains("write a") ||
           combinedText.contains("creative") {
            return .creative
        }
        
        // Check for analysis
        if combinedText.contains("analyze") ||
           combinedText.contains("analysis") ||
           combinedText.contains("evaluate") ||
           combinedText.contains("review") {
            return .analysis
        }
        
        // Check for summarization
        if combinedText.contains("summarize") ||
           combinedText.contains("summary") ||
           combinedText.contains("brief") ||
           combinedText.contains("tl;dr") {
            return .summary
        }
        
        return .general
    }
}

// MARK: - Thread-Safe Result Accumulator

/// Helper class to accumulate results safely from concurrent query callbacks
private final class ResultAccumulator: @unchecked Sendable {
    private var results: [SearchResult] = []
    private let limit: Int
    private let lock = NSLock()
    
    init(limit: Int) {
        self.limit = limit
    }
    
    func add(_ result: SearchResult) {
        lock.lock()
        defer { lock.unlock() }
        if results.count < limit {
            results.append(result)
        }
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.count
    }
    
    func getResults() -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

// MARK: - Convenience Extensions

extension SearchIndexer {
    /// Quick index a simple query-response pair
    public func quickIndex(query: String, response: String) async {
        let context = ExecutionContext(
            source: .internalApp,
            originalInput: query
        )
        await indexInteraction(query: query, response: response, context: context)
    }
    
    /// Search and return just the queries (for autocomplete)
    public func searchQueries(matching prefix: String, limit: Int = 10) -> [String] {
        let lowercasedPrefix = prefix.lowercased()
        return recentItems
            .filter { $0.query.lowercased().hasPrefix(lowercasedPrefix) }
            .prefix(limit)
            .map { $0.query }
    }
}
