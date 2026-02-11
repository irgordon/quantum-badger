import Foundation
import BadgerCore

// MARK: - The Interface

/// Represents a capability the agent can invoke.
public protocol AgentTool: Sendable {
    /// The unique identifier used by the LLM (e.g., "filesystem.read").
    var name: String { get }
    
    /// A human-readable description of what this tool does.
    /// Used to generate the system prompt for the Planner.
    var description: String { get }
    
    /// The JSON Schema defining the expected arguments.
    /// Used to validate input before execution.
    var inputSchema: String { get }
    
    /// The logic to execute the tool.
    /// - Parameters:
    ///   - payload: The raw arguments from the LLM.
    ///   - context: Execution context (security tokens, vault refs, etc.).
    /// - Returns: A stream of output strings.
    func execute(payload: ToolCallPayload, context: ToolContext) -> AsyncThrowingStream<String, Error>
}

extension AgentTool {
    /// Helper to wrap a synchronous result into a stream.
    public func instream(_ block: @escaping () async throws -> String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await block()
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Execution Context

/// Context passed to every tool execution.
/// Contains security boundaries and environment data.
public struct ToolContext: Sendable {
    public let vaultReferences: [VaultReference]
    public let workingDirectory: URL?
    
    public init(vaultReferences: [VaultReference] = [], workingDirectory: URL? = nil) {
        self.vaultReferences = vaultReferences
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Errors

public enum ToolError: Error, LocalizedError {
    case toolNotFound(String)
    case invalidArguments(String)
    case executionFailed(String)
    case securityViolation(String)
    
    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name): return "Tool '\(name)' is not registered."
        case .invalidArguments(let reason): return "Invalid arguments: \(reason)"
        case .executionFailed(let reason): return "Tool execution failed: \(reason)"
        case .securityViolation(let reason): return "Security Violation: \(reason)"
        }
    }
}

// MARK: - The Runtime (Registry)

public actor ToolRuntime {
    
    /// Registry of available tools.
    private var tools: [String: any AgentTool] = [:]
    
    public init() {}
    
    /// Register a new capability.
    public func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }
    
    /// Returns a stream so the caller (Orchestrator) can observe progress.
    public func runStream(_ request: ToolRequest) -> AsyncThrowingStream<String, Error> {
        guard let tool = tools[request.toolName] else {
            return .failed(with: ToolError.toolNotFound(request.toolName))
        }
        
        // Build Context
        // In a real app, you might derive the working directory from the `activePlan`.
        let context = ToolContext(vaultReferences: request.vaultReferences ?? [])
        
        // Execute and return the tool's native stream
        return tool.execute(payload: request.payload, context: context)
    }
}

// Helper to create a failed stream immediately
extension AsyncThrowingStream where Element == String, Failure == Error {
    static func failed(with error: Error) -> Self {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - Request Model

public struct ToolRequest: Sendable {
    public let id: UUID
    public let toolName: String
    public let payload: ToolCallPayload
    public let vaultReferences: [VaultReference]?
    public let requestedAt: Date
    
    public init(id: UUID, toolName: String, payload: ToolCallPayload, vaultReferences: [VaultReference]?, requestedAt: Date) {
        self.id = id
        self.toolName = toolName
        self.payload = payload
        self.vaultReferences = vaultReferences
        self.requestedAt = requestedAt
    }
}

// MARK: - Example Tools

// Example 1: Simple Echo (Debugging)
public struct EchoTool: AgentTool {
    public let name = "system.echo"
    public let description = "Returns the input back to the user. Useful for testing."
    public let inputSchema = "{ \"message\": \"string\" }"
    
    public init() {}
    
    public func execute(payload: ToolCallPayload, context: ToolContext) -> AsyncThrowingStream<String, Error> {
        instream {
            // Use our generic helper from earlier to decode safely
            struct Args: Decodable { let message: String }
            let args = try payload.arguments(as: Args.self)
            return "Echo: \(args.message)"
        }
    }
}

// Example 2: Secure File Reading (Stub)
public struct ReadFileTool: AgentTool {
    public let name = "fs.read"
    public let description = "Reads text content from a file path."
    public let inputSchema = "{ \"path\": \"string\" }"
    
    public init() {}
    
    public func execute(payload: ToolCallPayload, context: ToolContext) -> AsyncThrowingStream<String, Error> {
        instream {
            struct Args: Decodable { let path: String }
            let args = try payload.arguments(as: Args.self)
            
            // SECURITY CHECK: Verify access via Vault
            // The path must match a label in the allowed vault references.
            guard let _ = context.vaultReferences.first(where: { args.path.contains($0.label) }) else {
                throw ToolError.securityViolation("Access to '\(args.path)' is not authorized by the user.")
            }
            
            // Simulation of reading a file
            return "Contents of \(args.path): [Mock Data for Security Safety]"
        }
    }
}

// Example 3: Deep Thought (Streaming Simulation)
public struct SimulateDeepThoughtTool: AgentTool {
    public let name = "ai.think"
    public let description = "Simulates a complex reasoning task."
    public let inputSchema = "{}"
    
    public init() {}
    
    public func execute(payload: ToolCallPayload, context: ToolContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let thoughts = [
                    "Analyzing input vectors...",
                    "Checking constraints...",
                    "Optimizing query...",
                    "Validating security context...",
                    "Done."
                ]
                
                for thought in thoughts {
                    // Yield the text + a newline
                    continuation.yield(thought + "\n")
                    
                    // Artificial delay to look cool
                    try? await Task.sleep(for: .milliseconds(400))
                }
                
                continuation.finish()
            }
        }
    }
}
