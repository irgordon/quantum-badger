import AppIntents
import BadgerRuntime // Was QuantumBadgerRuntime in user input, assuming BadgerRuntime is correct module based on project structure.

@available(macOS 16.0, *)
@AssistantIntent(schema: .system.search)
struct WebScoutSearchIntent: ShowInAppSearchResultsIntent {
    static var title: LocalizedStringResource = "WebScout Search"
    static var description = IntentDescription("Search the web via Quantum Badger’s secure WebScout.")

    static var searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Query")
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        // IntentOrchestrator.shared provides the search functionality
        // Assuming fulfillSearch returns [QuantumMessage] or similar
        let messages = try await IntentOrchestrator.shared.fulfillSearch(criteria.term)
        
        var results: [String] = []
        results.reserveCapacity(messages.count)
        
        for message in messages {
            // IntentResultNormalizer is used to sanitize/format the output
            // If it doesn't exist, we might need to implement it or use a simpler approach.
            // For now, assuming it exists as per user request.
            let normalized = await IntentResultNormalizer.normalize(
                rawText: message.content,
                kind: message.kind,
                source: message.source,
                toolName: message.toolName,
                createdAt: message.createdAt
            )
            results.append(normalized.message.content)
        }
        
        return .result(value: results)
    }
}

@available(macOS 16.0, *)
struct WebScoutSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: WebScoutSearchIntent(),
                phrases: [
                    "Search the web with \(.applicationName)",
                    "Find results using \(.applicationName)"
                ],
                shortTitle: "WebScout Search",
                systemImageName: "magnifyingglass"
            )
        ]
    }
}

// Stub for IntentResultNormalizer if missing, to ensure compilation or context
// This should ideally be in BadgerRuntime/Core if used widely.
// Placing here as private/internal stub if needed, or commenting out if real one exists.
/*
struct IntentResultNormalizer {
    static func normalize(rawText: String, kind: QuantumMessage.Kind, source: String, toolName: String?, createdAt: Date) async -> NormalizedResult {
        // Implementation stub
        return NormalizedResult(message: QuantumMessage(content: rawText, ...))
    }
}
*/
