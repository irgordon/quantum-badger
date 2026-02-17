import Foundation
import Testing
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

@Suite("App Coordinator Tests")
struct AppCoordinatorTests {
    
    @Test("Execution Context creation")
    func testExecutionContext() async throws {
        let context = ExecutionContext(
            source: .shortcuts,
            originalInput: "Test command",
            userID: "user123",
            conversationID: "conv456"
        )
        
        #expect(context.source == .shortcuts)
        #expect(context.originalInput == "Test command")
        #expect(context.userID == "user123")
        #expect(context.conversationID == "conv456")
    }
    
    @Test("Command Source enum values")
    func testCommandSource() async throws {
        let sources: [ExecutionContext.CommandSource] = [
            .shortcuts, .siri, .imessage, .whatsapp,
            .telegram, .slack, .internalApp, .widget
        ]
        
        #expect(sources.count == 8)
        
        // Test raw values
        #expect(ExecutionContext.CommandSource.shortcuts.rawValue == "Shortcuts")
        #expect(ExecutionContext.CommandSource.siri.rawValue == "Siri")
        #expect(ExecutionContext.CommandSource.imessage.rawValue == "iMessage")
    }
    
    @Test("Formatted Output creation")
    func testFormattedOutput() async throws {
        let output = FormattedOutput(
            content: "Test content",
            format: .markdown,
            filename: "test.md",
            fileURL: URL(fileURLWithPath: "/tmp/test.md")
        )
        
        #expect(output.content == "Test content")
        #expect(output.format == .markdown)
        #expect(output.filename == "test.md")
    }
    
    @Test("Command Execution Result creation")
    func testCommandExecutionResult() async throws {
        let formattedOutput = FormattedOutput(
            content: "Response",
            format: .plainText,
            filename: "response.txt"
        )
        
        let result = CommandExecutionResult(
            output: "Response",
            formattedOutput: formattedOutput,
            executionTime: 1.5,
            routingDecision: .local(.phi4),
            wasSanitized: false,
            metadata: ["key": "value"]
        )
        
        #expect(result.output == "Response")
        #expect(result.executionTime == 1.5)
        #expect(result.routingDecision.isLocal == true)
        #expect(result.wasSanitized == false)
        #expect(result.metadata["key"] == "value")
    }
    
    @Test("App Coordinator initialization")
    func testAppCoordinatorInitialization() async throws {
        let coordinator = AppCoordinator()
        #expect(true) // Should initialize without crashing
    }
    
    @Test("App Coordinator Errors")
    func testAppCoordinatorErrors() async throws {
        let errors: [AppCoordinatorError] = [
            .executionFailed("Test"),
            .sanitizationFailed("Test"),
            .invalidInput,
            .engineNotAvailable,
            .securityViolation("Test"),
            .formattingFailed
        ]
        
        #expect(errors.count == 6)
    }
}

@Suite("Response Formatter Tests")
struct ResponseFormatterTests {
    
    @Test("Format Detection Result creation")
    func testFormatDetectionResult() async throws {
        let detection = FormatDetectionResult(
            containsCode: true,
            containsTable: false,
            containsMarkdown: true,
            estimatedCharacterCount: 1500,
            recommendedFormat: .markdownFile
        )
        
        #expect(detection.containsCode == true)
        #expect(detection.containsTable == false)
        #expect(detection.containsMarkdown == true)
        #expect(detection.estimatedCharacterCount == 1500)
        #expect(detection.exceedsMessageLimit == false) // 1500 < 4000
    }
    
    @Test("Format detection - code blocks")
    func testCodeBlockDetection() async throws {
        let formatter = ResponseFormatter()
        
        let codeContent = """
        Here's a Swift function:
        ```swift
        func greet() {
            print("Hello")
        }
        ```
        """
        
        let detection = await formatter.detectFormat(in: codeContent)
        #expect(detection.containsCode == true)
    }
    
    @Test("Format detection - tables")
    func testTableDetection() async throws {
        let formatter = ResponseFormatter()
        
        let tableContent = """
        | Name | Value |
        |------|-------|
        | A    | 1     |
        | B    | 2     |
        """
        
        let detection = await formatter.detectFormat(in: tableContent)
        #expect(detection.containsTable == true)
    }
    
    @Test("Format detection - character limit")
    func testCharacterLimitDetection() async throws {
        let formatter = ResponseFormatter()
        
        let longContent = String(repeating: "A", count: 5000)
        let detection = await formatter.detectFormat(in: longContent)
        
        #expect(detection.estimatedCharacterCount == 5000)
        #expect(detection.exceedsMessageLimit == true)
    }
    
    @Test("Response Formatter initialization")
    func testResponseFormatterInitialization() async throws {
        let formatter = ResponseFormatter()
        #expect(true) // Should initialize without crashing
    }
}

@Suite("Search Indexer Tests")
struct SearchIndexerTests {
    
    @Test("Indexed Item creation")
    func testIndexedItem() async throws {
        let item = IndexedItem(
            id: "test-id",
            query: "How do I write a function?",
            response: "Here's how to write a function...",
            source: .shortcuts,
            timestamp: Date(),
            category: .question,
            metadata: ["key": "value"]
        )
        
        #expect(item.id == "test-id")
        #expect(item.query == "How do I write a function?")
        #expect(item.category == .question)
        #expect(item.source == .shortcuts)
    }
    
    @Test("Indexed Item categories")
    func testIndexedItemCategories() async throws {
        let categories: [IndexedItem.InteractionCategory] = [
            .question, .code, .creative, .analysis, .summary, .general
        ]
        
        #expect(categories.count == 6)
        
        // Test keywords exist
        #expect(IndexedItem.InteractionCategory.code.keywords.contains("code"))
        #expect(IndexedItem.InteractionCategory.question.keywords.contains("question"))
    }
    
    @Test("Search Result creation")
    func testSearchResult() async throws {
        let result = SearchResult(
            id: "result-1",
            query: "Test query",
            response: "Test response",
            relevance: 0.95,
            timestamp: Date(),
            source: .internalApp
        )
        
        #expect(result.id == "result-1")
        #expect(result.relevance == 0.95)
    }
    
    @Test("Search Indexer initialization")
    func testSearchIndexerInitialization() async throws {
        let indexer = SearchIndexer()
        #expect(true) // Should initialize without crashing
    }
    
    @Test("Search Indexer in-memory caching")
    func testRecentItemsCache() async throws {
        let indexer = SearchIndexer()
        
        // Add items to cache
        await indexer.quickIndex(query: "Query 1", response: "Response 1")
        await indexer.quickIndex(query: "Query 2", response: "Response 2")
        
        let recent = await indexer.getRecentItems(limit: 10)
        #expect(recent.count == 2)
        
        // Search in cache
        let results = await indexer.searchRecent(query: "Query", limit: 5)
        #expect(results.count == 2)
    }
    
    @Test("Interaction categorization")
    func testCategorization() async throws {
        let indexer = SearchIndexer()
        
        // These would be tested via the internal categorizeInteraction method
        // Just verify the categories exist and have expected properties
        let codeCategory = IndexedItem.InteractionCategory.code
        #expect(codeCategory.keywords.contains("code"))
        #expect(codeCategory.keywords.contains("programming"))
        
        let questionCategory = IndexedItem.InteractionCategory.question
        #expect(questionCategory.keywords.contains("question"))
    }
}

@Suite("Integration Tests")
struct BadgerAppIntegrationTests {
    
    @Test("PII Sanitization in Coordinator")
    func testPIISanitization() async throws {
        let commandWithPII = "My email is test@example.com and phone is 555-123-4567"
        
        let sanitizer = InputSanitizer()
        let result = sanitizer.sanitize(commandWithPII)
        
        #expect(result.wasSanitized == true)
        #expect(result.sanitized.contains("test@example.com") == false)
    }
    
    @Test("Command Source Parameter mapping")
    func testCommandSourceMapping() async throws {
        // Test that all CommandSourceParameter values map correctly
        let mappings: [(CommandSourceParameter, ExecutionContext.CommandSource)] = [
            (.shortcuts, .shortcuts),
            (.siri, .siri),
            (.imessage, .imessage),
            (.whatsapp, .whatsapp),
            (.telegram, .telegram),
            (.slack, .slack)
        ]
        
        for (param, expected) in mappings {
            #expect(param.toCommandSource() == expected)
        }
    }
    
    @Test("Response Formatter file creation decision")
    func testFileCreationDecision() async throws {
        let formatter = ResponseFormatter()
        
        // Short text should not become file
        let shortText = "Hello world"
        let shouldFile = await formatter.shouldReturnAsFile(shortText, source: .imessage)
        #expect(shouldFile == false)
        
        // Long text should become file
        let longText = String(repeating: "A", count: 5000)
        let shouldFileLong = await formatter.shouldReturnAsFile(longText, source: .imessage)
        #expect(shouldFileLong == true)
    }
    
    @Test("BadgerApp static methods")
    func testBadgerAppStatics() async throws {
        #expect(BadgerApp.version == "0.1.1")
    }
}
