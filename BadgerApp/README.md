# BadgerApp - macOS System Integration Layer

BadgerApp provides macOS system integrations including Shortcuts/Siri support, message formatting, and Spotlight indexing.

## Components

### 1. ProcessRemoteCommand AppIntent

Exposed to Shortcuts/Siri for remote command processing:

```swift
// Usage in Shortcuts:
ProcessRemoteCommand(command: "Write a Swift function to sort an array")

// Returns:
// - String response (for short answers)
// - File attachment (for long/code responses)
```

**Security Flow:**
1. Input received from Shortcuts/Siri/iMessage
2. Immediately sanitized through `InputSanitizer`
3. Critical violations block execution
4. Execution logged to audit service
5. Response formatted appropriately

### 2. AppCoordinator

Central coordinator managing the execution flow:

```swift
let coordinator = AppCoordinator.shared
let result = try await coordinator.execute(
    command: "Analyze this code",
    context: ExecutionContext(source: .imessage, originalInput: "...")
)

// Access result
print(result.output)              // Raw output
print(result.formattedOutput?.fileURL)  // File if created
print(result.executionTime)       // Performance metric
```

### 3. ResponseFormatter

Detects content type and formats for messaging:

```swift
let formatter = ResponseFormatter()
let formatted = try await formatter.format(
    content: aiResponse,
    source: .imessage  // Adapts formatting for platform
)

// Auto-detects:
// - Code blocks → .swift/.py file
// - Tables → .md file
// - Long text (>4000 chars) → .txt file
```

### 4. SearchIndexer

Indexes interactions for local Spotlight search:

```swift
let indexer = SearchIndexer()

// Index an interaction
await indexer.indexInteraction(
    query: "How do I sort an array?",
    response: "You can use sorted()...",
    context: executionContext
)

// Search past interactions
let results = try await indexer.search(query: "sort array", limit: 10)
```

## Integration Examples

### Shortcuts Workflow

1. **Receive Message** (iMessage trigger)
2. **ProcessRemoteCommand** (this package)
   - Input: Message Content
   - Source: iMessage
3. **Send Message** (back to sender)
   - Input: Command result

### Siri Integration

```swift
// User says: "Ask Quantum Badger how to write a closure"
// Intent: AskQuestion
// Response spoken back to user
```

### Spotlight Search

Indexed items appear in macOS Spotlight:
- Search: "Quantum Badger sort array"
- Shows: Past conversation about sorting
- Opens: Original conversation context

## Security

- **Input Sanitization**: All input sanitized before processing
- **PII Detection**: Emails, phone numbers, SSNs redacted
- **Code Injection Prevention**: Shell/SQL injection patterns blocked
- **Audit Logging**: All commands logged with source and result

## File Output

When responses exceed limits or contain special content:

| Content Type | Format | Extension |
|-------------|--------|-----------|
| Code blocks | Code file | .swift/.py/.js |
| Markdown tables | Markdown | .md |
| Long text (>4000 chars) | Plain text | .txt |
| Mixed content | Markdown | .md |
