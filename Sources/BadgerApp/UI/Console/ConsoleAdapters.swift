import Foundation
import BadgerCore
import BadgerRuntime
import Combine

// Adapters to bridge BadgerCore/App types to ConsoleView expectations.

@MainActor
class ModelRegistry {
    private let catalog: ModelCatalog
    var models: [LocalModel] {
        // Convert ModelDescriptor to LocalModel if needed, or just wrap
        // For now, assuming LocalModel is compatible or we map.
        // Catalog uses ModelDescriptor. LocalModel is in BadgerCore.
        // We probably need to fetch from Catalog.
        // Mocking for view compile:
        return [] 
    }
    
    init(catalog: ModelCatalog) {
        self.catalog = catalog
    }
}

@Observable
class ModelSelectionStore {
    var activeModelId: UUID? = nil
}

@Observable
class NetworkReachabilityMonitor {
    enum Scope {
        case offline, localNetwork, internet
    }
    var scope: Scope = .offline
}

@Observable
class BookmarkStore {
    var entries: [VaultReference] = []
    
    func withResolvedURL<T>(for entry: VaultReference, action: (URL) -> T) -> T? {
        // Mock
        return nil
    }
}

@Observable
class VaultStore {
    func storeBookmark(label: String, url: URL) {}
    func reference(forLabel: String) -> VaultReference? { return nil }
}

@MainActor
class PolicyEngine {
    // Wrapper for NetworkPolicyStore or similar
}

@MainActor
class ToolApprovalManager {
    func requestApproval(policy: PolicyEngine, toolName: String, input: [String: String], onApproved: @escaping (String?) -> Void) async {
        // Auto approve for mock
        onApproved(UUID().uuidString)
    }
}

@Observable
class ToolLimitsStore {
    var dbQueryMaxTokens: Int = 1024
}

@Observable
class MessagingInboxStore {
    var messages: [QuantumMessage] = []
}

@Observable
class ConversationHistoryStore {
    private let memoryController: MemoryController
    
    init(memoryController: MemoryController) {
        self.memoryController = memoryController
    }
    
    func list() async -> [ConversationEntry] {
        // Mock mapping
        return []
    }
    
    func append(_ entry: ConversationEntry) async {
        await memoryController.append(role: entry.role, content: entry.content)
    }
    
    func lastCompactionRecord() async -> CompactionRecord? {
        return nil
    }
    
    func setPinned(id: UUID, pinned: Bool) async {}
    
    func archivedEntries(archiveID: UUID) async -> [ConversationEntry]? { return nil }
}

public struct ConversationEntry: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let source: String
    public let role: ConversationEntryRole
    public let isPinned: Bool
    public let isSummary: Bool
    public let summaryArchiveID: UUID?
    public let toolName: String?
    public let toolCallID: UUID?
    
    public init(id: UUID = UUID(), content: String, source: String, role: ConversationEntryRole, isPinned: Bool = false, isSummary: Bool = false, summaryArchiveID: UUID? = nil, toolName: String? = nil, toolCallID: UUID? = nil) {
        self.id = id
        self.content = content
        self.source = source
        self.role = role
        self.isPinned = isPinned
        self.isSummary = isSummary
        self.summaryArchiveID = summaryArchiveID
        self.toolName = toolName
        self.toolCallID = toolCallID
    }
}

public enum ConversationEntryRole: Sendable {
    case user, assistant, toolCall, toolResult, system
}

public struct CompactionRecord: Sendable {
    public let occurredAt: Date
    public let beforeTokenEstimate: Int
    public let afterTokenEstimate: Int
}

@MainActor
class ExecutionRecoveryManager {
    func startGoal(_ intent: String, plan: [WorkflowStep]) {}
    func updateStep(_ id: UUID, status: StepStatus) {}
    func handleFailure(stepID: UUID, reason: String) async -> RecoveryOption { return .askUser }
}

enum StepStatus {
    case inProgress
    case completed
    case failed(reason: String)
}

enum RecoveryOption {
    case retry, skip, askUser
}

class SystemSearchDonationManager {
    static func donate(messages: [QuantumMessage]) {}
}

class ExportOptionsPrompt {
    struct Options {
        let isEncrypted: Bool
    }
    static func presentPlanReport() async -> Options? { return Options(isEncrypted: false) }
}

class SavePanelPresenter {
    static func present(defaultFileName: String, allowedFileTypes: [String]) async -> URL? { return nil }
}

class PlanExporter {
    static func export(plan: WorkflowPlan, results: [ToolResult?], auditEntries: [AuditEntry], option: ExportOptionsPrompt.Options, to: URL) async -> Bool { return true }
}

class LocalSearchACL {
    static func decodeMatches(from json: String) -> [LocalSearchMatch] { return [] }
}

class WebScoutACL {
    static func decodeResultsJSON(_ json: String) -> [WebScoutResult] { return [] }
}

public struct LocalSearchMatch: Sendable {
    public let filePath: String
    public let lineNumber: Int
    public let linePreview: String
}

public struct WebScoutResult: Sendable {
    public let title: String
    public let url: String
    public let snippet: String
}

class InboundIdentityValidator {
    static let shared = InboundIdentityValidator()
    func verifyPayload(_ data: Data, signature: String) -> Bool { return true }
}
