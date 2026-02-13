import Foundation
import AppIntents
import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Process Remote Command Intent

/// AppIntent that accepts remote commands from Shortcuts, Siri, and other automations
/// Sanitizes input and executes through the AppCoordinator
public struct ProcessRemoteCommand: AppIntent {
    
    // MARK: - Intent Configuration
    
    public static var title: LocalizedStringResource = "Process Remote Command"
    public static var description: IntentDescription = IntentDescription(
        "Sends a command to Quantum Badger. Input is sanitized and routed securely.",
        categoryName: "Quantum Badger",
        searchKeywords: ["AI", "assistant", "command", "query", "ask"]
    )
    
    // SECURITY: Require unlock to process commands containing potentially sensitive PII/Actions
    public static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalAuthentication
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Ask Quantum Badger to \($command)") {
            \.$source
            \.$returnAsFile
        }
    }
    
    // MARK: - Parameters
    
    @Parameter(title: "Command", requestValueDialog: IntentDialog("What do you want to do?"))
    var command: String
    
    @Parameter(title: "Source", default: .shortcuts)
    var source: CommandSourceParameter
    
    @Parameter(title: "Return as File", default: false)
    var returnAsFile: Bool
    
    // MARK: - Initialization
    
    public init() {}
    
    public init(command: String, source: CommandSourceParameter = .shortcuts, returnAsFile: Bool = false) {
        self.command = command
        self.source = source
        self.returnAsFile = returnAsFile
    }
    
    // MARK: - Execution
    
    public func perform() async throws -> some IntentResult & ReturnsValue<BadgerResult> {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppCoordinatorError.invalidInput
        }
        
        // 1. Setup Context
        let context = ExecutionContext(
            source: source.toCommandSource(),
            originalInput: command
        )
        
        // 2. Execute on Main Actor
        let result = try await AppCoordinator.shared.execute(command: command, context: context)
        
        // 3. Prepare Result
        // We use a custom TransientAppEntity to handle both Text and File scenarios uniformly
        let responseEntity: BadgerResult
        let dialog: IntentDialog
        
        if returnAsFile,
           let formatted = result.formattedOutput,
           let url = formatted.fileURL {
            
            // File Case
            let file = IntentFile(fileURL: url, filename: formatted.filename)
            responseEntity = BadgerResult(
                text: "Result attached as file.",
                file: file
            )
            dialog = IntentDialog("I've processed that. The result is attached as a file.")
            
        } else {
            // Text Case
            responseEntity = BadgerResult(text: result.output)
            
            // Concise dialog for Siri
            let spoken = result.output.count > 100 
                ? "Here is the result." 
                : result.output
            dialog = IntentDialog(stringLiteral: spoken)
        }
        
        return .result(value: responseEntity, dialog: dialog)
    }
}

// MARK: - Result Entity

/// A transient entity that can hold either text or a file, solving the return type dilemma.
public struct BadgerResult: TransientAppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Quantum Badger Result"
    
    @Property(title: "Response Text")
    public var text: String
    
    @Property(title: "Response File")
    public var file: IntentFile?
    
    public init(text: String, file: IntentFile? = nil) {
        self.text = text
        self.file = file
    }
    
    public var displayRepresentation: DisplayRepresentation {
        if let file = file {
            return DisplayRepresentation(
                title: "\(text)",
                subtitle: "Contains attachment: \(file.filename)"
            )
        } else {
            return DisplayRepresentation(title: "\(text)")
        }
    }
}

// MARK: - Command Source Parameter

/// Enum for command source selection in Shortcuts
public enum CommandSourceParameter: String, AppEnum, Sendable {
    case shortcuts = "Shortcuts"
    case siri = "Siri"
    case imessage = "iMessage"
    case whatsapp = "WhatsApp"
    case telegram = "Telegram"
    case slack = "Slack"
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Command Source"
    
    public static var caseDisplayRepresentations: [CommandSourceParameter: DisplayRepresentation] {
        [
            .shortcuts: "Shortcuts",
            .siri: "Siri",
            .imessage: "iMessage",
            .whatsapp: "WhatsApp",
            .telegram: "Telegram",
            .slack: "Slack"
        ]
    }
    
    func toCommandSource() -> ExecutionContext.CommandSource {
        ExecutionContext.CommandSource(rawValue: self.rawValue) ?? .shortcuts
    }
}



// MARK: - Additional Intents

public struct GetSystemStatus: AppIntent {
    public static var title: LocalizedStringResource = "Get System Status"
    public static var description = IntentDescription("Checks VRAM and Thermal status.")
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let vramMonitor = VRAMMonitor()
        let thermalGuard = ThermalGuard()
        
        // Parallel fetch for performance
        let vramStatus = await vramMonitor.getCurrentStatus()
        let thermalStatus = await thermalGuard.getCurrentStatus()
        
        let availGB = Double(vramStatus.availableVRAM) / (1024 * 1024 * 1024)
        let message = "VRAM: \(String(format: "%.1f", availGB))GB available. Thermal: \(thermalStatus.state.rawValue)."
        
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

public struct AskQuestion: AppIntent {
    public static var title: LocalizedStringResource = "Ask Question"
    public static var description = IntentDescription("Quickly ask a question.")
    
    @Parameter(title: "Question")
    var question: String
    
    public init() {}
    public init(question: String) { self.question = question }
    
    public func perform() async throws -> some IntentResult & ReturnsValue<BadgerResult> {
        // Delegate to the main intent
        let intent = ProcessRemoteCommand(command: question, source: .siri, returnAsFile: false)
        return try await intent.perform()
    }
}

// MARK: - Intent Provider

public struct BadgerAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskQuestion(),
            phrases: [
                "Ask Quantum Badger \($question)",
                "Ask Badger \($question)"
            ],
            shortTitle: "Ask Badger",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: GetSystemStatus(),
            phrases: [
                "Check Quantum Badger status",
                "Quantum Badger health"
            ],
            shortTitle: "System Status",
            systemImageName: "cpu"
        )
    }
}
