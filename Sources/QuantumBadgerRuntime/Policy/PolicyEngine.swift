import Foundation

enum Permission: String, Codable, CaseIterable, Identifiable {
    case filesystemWrite = "filesystem.write"

    var id: String { rawValue }
}

actor PolicyEngine {
    private struct ApprovalToken {
        let token: String
        let toolName: String
        let resourceKey: String?
        let expiresAt: Date
    }

    private var grants: Set<Permission> = []
    private var toolSessionGrants: Set<String> = []
    private var approvalTokens: [String: ApprovalToken] = [:]
    private let auditLog: AuditLog
    private let messagingPolicy: MessagingPolicyStore

    init(auditLog: AuditLog, messagingPolicy: MessagingPolicyStore) {
        self.auditLog = auditLog
        self.messagingPolicy = messagingPolicy
    }

    func grant(_ permission: Permission) {
        grants.insert(permission)
        auditLog.record(event: .permissionGranted(permission.rawValue))
    }

    func revoke(_ permission: Permission) {
        grants.remove(permission)
        auditLog.record(event: .permissionRevoked(permission.rawValue))
    }

    func hasGrant(_ permission: Permission) -> Bool {
        grants.contains(permission)
    }

    func grantToolSession(_ toolName: String) {
        toolSessionGrants.insert(toolName)
        auditLog.record(event: .permissionGranted("tool.session.\(toolName)"))
        SystemEventBus.shared.post(.toolSessionGrantChanged(toolName: toolName))
    }

    func revokeToolSession(_ toolName: String) {
        toolSessionGrants.remove(toolName)
        auditLog.record(event: .permissionRevoked("tool.session.\(toolName)"))
        SystemEventBus.shared.post(.toolSessionGrantChanged(toolName: toolName))
    }

    func isToolSessionGranted(_ toolName: String) -> Bool {
        toolSessionGrants.contains(toolName)
    }

    func issueApprovalToken(toolName: String, resourceKey: String?) -> String {
        let token = UUID().uuidString
        let approval = ApprovalToken(
            token: token,
            toolName: toolName,
            resourceKey: resourceKey,
            expiresAt: Date().addingTimeInterval(60 * 5)
        )
        approvalTokens[token] = approval
        return token
    }

    func evaluate(request: ToolRequest, contract: ToolContract?) async -> PolicyDecision {
        guard contract != nil else {
            return PolicyDecision(isAllowed: false, reason: "Unauthorized tool identifier.")
        }
        if request.toolName == "filesystem.write" {
            guard grants.contains(.filesystemWrite) else {
                return PolicyDecision(isAllowed: false, reason: "Missing filesystem write grant.")
            }
            guard let resourceKey = request.input["pathRef"], !resourceKey.isEmpty else {
                return PolicyDecision(isAllowed: false, reason: "Missing target path reference.")
            }
            if !isToolSessionGranted(request.toolName),
               !consumeApprovalToken(
                request.input["approvalToken"],
                toolName: request.toolName,
                resourceKey: resourceKey
               ) {
                return PolicyDecision(isAllowed: false, reason: "Approval required for filesystem write.")
            }
        }

        if let contract, contract.riskLevel == .medium || contract.riskLevel == .high {
            if !toolSessionGrants.contains(contract.name)
                && !consumeApprovalToken(
                    request.input["approvalToken"],
                    toolName: contract.name,
                    resourceKey: request.input["pathRef"] ?? request.input["connectionRef"]
                ) {
                return PolicyDecision(isAllowed: false, reason: "Approval required for \(contract.name).")
            }
        }

        if request.toolName == "local.search" {
            if !toolSessionGrants.contains("local.search")
                && !consumeApprovalToken(
                    request.input["approvalToken"],
                    toolName: "local.search",
                    resourceKey: nil
                ) {
                return PolicyDecision(isAllowed: false, reason: "Local search requires approval.")
            }
        }

        if request.toolName == "message.send" {
            let recipient = request.input["recipient"] ?? ""
            guard let resolved = await messagingPolicy.resolveRecipient(recipient) else {
                return PolicyDecision(isAllowed: false, reason: "Recipient is not in trusted contacts.")
            }
            if let contact = await messagingPolicy.contact(for: resolved) {
                let requiredKey = contact.conversationKey
                if let requiredKey, !requiredKey.isEmpty {
                    let provided = request.input["conversationKey"] ?? ""
                    if provided != requiredKey {
                        return PolicyDecision(isAllowed: false, reason: "Conversation is not trusted.")
                    }
                } else {
                    return PolicyDecision(isAllowed: false, reason: "Conversation is not trusted.")
                }
            }
            if !(await messagingPolicy.canSendMessageNow()) {
                return PolicyDecision(isAllowed: false, reason: "Message rate limit reached.")
            }
        }

        return PolicyDecision(isAllowed: true, reason: "Allowed by policy.")
    }

    func snapshot() -> PolicySnapshot {
        PolicySnapshot(
            grants: grants.map { $0.rawValue }.sorted(),
            toolSessionGrants: toolSessionGrants.sorted()
        )
    }

    private func consumeApprovalToken(_ token: String?, toolName: String, resourceKey: String?) -> Bool {
        guard let token, let approval = approvalTokens[token] else { return false }
        guard approval.expiresAt > Date() else {
            approvalTokens[token] = nil
            return false
        }
        guard approval.toolName == toolName else { return false }
        if let resourceKey {
            guard approval.resourceKey == resourceKey else { return false }
        }
        approvalTokens[token] = nil
        return true
    }
}

struct PolicyDecision {
    let isAllowed: Bool
    let reason: String
}

struct PolicySnapshot: Codable {
    let grants: [String]
    let toolSessionGrants: [String]
}

struct PromptPolicyDecision {
    let isAllowed: Bool
    let reason: String
    let redactedPrompt: String
}

extension PolicyEngine {
    func evaluatePrompt(_ prompt: String, model: LocalModel?) -> PromptPolicyDecision {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PromptPolicyDecision(isAllowed: false, reason: "Prompt is empty.", redactedPrompt: prompt)
        }
        let lowered = trimmed.lowercased()
        let creepPatterns = [
            "ignore previous instructions",
            "you are now a system administrator",
            "system administrator",
            "sudo rm -rf",
            "run 'sudo",
            "run \"sudo",
            "run sudo",
            "system override",
            "act as root"
        ]
        if creepPatterns.contains(where: { lowered.contains($0) }) {
            return PromptPolicyDecision(
                isAllowed: false,
                reason: "Prompt contains a system override or command injection attempt.",
                redactedPrompt: trimmed
            )
        }
        let maxChars = model?.maxPromptChars ?? 2000
        if trimmed.count > maxChars {
            return PromptPolicyDecision(isAllowed: false, reason: "Prompt is too large.", redactedPrompt: prompt)
        }
        let redaction = PromptRedactor.redact(trimmed)
        if redaction.hadSensitiveData && (model?.redactSensitivePrompts == false) {
            return PromptPolicyDecision(isAllowed: false, reason: "Sensitive data detected.", redactedPrompt: trimmed)
        }
        return PromptPolicyDecision(isAllowed: true, reason: "Allowed by policy.", redactedPrompt: redaction.redactedText)
    }

    func evaluateWebContent(_ text: String) -> PolicyDecision {
        let lowered = text.lowercased()
        let patterns = [
            "ignore previous instructions",
            "system prompt",
            "developer message",
            "you are chatgpt",
            "act as"
        ]
        if patterns.contains(where: { lowered.contains($0) }) {
            return PolicyDecision(isAllowed: false, reason: "Potential prompt injection detected.")
        }
        return PolicyDecision(isAllowed: true, reason: "Allowed by policy.")
    }
}
