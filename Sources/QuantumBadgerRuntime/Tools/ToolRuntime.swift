import Foundation

actor ToolRuntime {
    let policy: PolicyEngine
    let auditLog: AuditLog
    let bookmarkStore: BookmarkStore
    let memoryManager: MemoryManager
    let untrustedParser: UntrustedParsingService
    let vaultStore: VaultStore
    let messagingAdapter: MessagingAdapter
    let messagingPolicy: MessagingPolicyStore
    let networkClient: NetworkClient
    let webFilterStore: WebFilterStore
    private let secretRedactor = SecretRedactor()

    init(
        policy: PolicyEngine,
        auditLog: AuditLog,
        bookmarkStore: BookmarkStore,
        memoryManager: MemoryManager,
        vaultStore: VaultStore,
        untrustedParser: UntrustedParsingService = UntrustedParsingXPCClient(),
        messagingAdapter: MessagingAdapter = DisabledMessagingAdapter(),
        messagingPolicy: MessagingPolicyStore,
        networkClient: NetworkClient,
        webFilterStore: WebFilterStore
    ) {
        self.policy = policy
        self.auditLog = auditLog
        self.bookmarkStore = bookmarkStore
        self.memoryManager = memoryManager
        self.vaultStore = vaultStore
        self.untrustedParser = untrustedParser
        self.messagingAdapter = messagingAdapter
        self.messagingPolicy = messagingPolicy
        self.networkClient = networkClient
        self.webFilterStore = webFilterStore
    }

    func run(_ request: ToolRequest) async -> ToolResult {
        let contract = ToolCatalog.contract(for: request.toolName)
        let decision = await policy.evaluate(request: request, contract: contract)
        guard decision.isAllowed else {
            let result = ToolResult(id: request.id, toolName: request.toolName, output: ["error": decision.reason], succeeded: false, finishedAt: Date())
            auditLog.record(event: .toolDenied(request, reason: decision.reason))
            return result
        }

        let limits = contract?.limits ?? .default
        auditLog.record(event: .toolStarted(request))

        do {
            let result = try await withTimeout(seconds: limits.timeoutSeconds) {
                try await execute(request, limits: limits)
            }
            let sanitized = sanitize(result)
            auditLog.record(event: .toolFinished(sanitized))
            await memoryManager.proposePromotions(from: sanitized)
            return sanitized
        } catch {
            let result = ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Tool execution timed out or was cancelled."],
                succeeded: false,
                finishedAt: Date()
            )
            let sanitized = sanitize(result)
            auditLog.record(event: .toolFinished(sanitized))
            return sanitized
        }
    }

    private func execute(_ request: ToolRequest, limits: ToolExecutionLimits) async throws -> ToolResult {
        try Task.checkCancellation()
        if let secureTool = SecureToolRegistry.tools[request.toolName] {
            let result = try await secureTool.run(
                request: request,
                vaultStore: vaultStore,
                secretRedactor: secretRedactor,
                limits: limits
            )
            try enforceOutputLimit(result.output, maxBytes: limits.maxOutputBytes)
            return result
        }
        if request.toolName == "local.search", let query = request.input["query"] {
            let accumulator = ToolOutputAccumulator(maxBytes: limits.maxOutputBytes)
            var matchCount = 0
            var stopReason: LocalSearchStopReason = .completed
            do {
                try accumulator.setValue(query, forKey: "query")
                let runResult = LocalSearchTool.runStreaming(
                    query: query,
                    bookmarkStore: bookmarkStore,
                    maxMatches: limits.maxMatches,
                    maxFileBytes: limits.maxFileBytes
                ) { match in
                    do {
                        let data = try JSONEncoder().encode(match)
                        let json = String(data: data, encoding: .utf8) ?? "{}"
                        try accumulator.appendJSONElement(json, toArrayKey: "matches")
                        return true
                    } catch {
                        accumulator.markTruncated()
                        return false
                    }
                }
                matchCount = runResult.count
                stopReason = runResult.stopReason
            } catch {
                accumulator.markTruncated()
            }
            let proposal = "Local search for “\(query)” returned \(matchCount) matches."
            do {
                try accumulator.setValue("\(matchCount)", forKey: "count")
                try accumulator.setValue(encodeProposals([proposal]), forKey: "memoryProposals")
            } catch {
                accumulator.markTruncated()
            }
            if accumulator.truncated {
                stopReason = .limitReached
            }
            if stopReason != .completed {
                let reasonText: String = stopReason == .limitReached ? "Limit Reached" : "Manual Cancel"
                auditLog.record(event: .toolStopped(request.toolName, toolId: request.id, reason: reasonText))
            }
            let output = accumulator.finish()
            if stopReason != .completed {
                var updatedOutput = output
                updatedOutput["stopReason"] = stopReason.rawValue
                try enforceOutputLimit(updatedOutput, maxBytes: limits.maxOutputBytes)
                return ToolResult(id: request.id, toolName: request.toolName, output: updatedOutput, succeeded: true, finishedAt: Date())
            }
            try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
            return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: true, finishedAt: Date())
        } else if request.toolName == "message.send" {
            let recipient = request.input["recipient"] ?? ""
            let body = request.input["body"] ?? ""
            let resolved = await messagingPolicy.resolveRecipient(recipient) ?? recipient
            let success = await messagingAdapter.sendDraft(recipient: resolved, body: body)
            if success {
                await messagingPolicy.recordMessageSent()
                let output = ["status": "drafted", "recipient": resolved]
                try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
                return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: true, finishedAt: Date())
            } else {
                let output = ["error": "Couldn’t open the messaging draft."]
                try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
                return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: false, finishedAt: Date())
            }
        } else if request.toolName == "web.scout", let query = request.input["query"] {
            let searchURL = buildSearchURL(query)
            guard webFilterStore.isDomainAllowed(searchURL.host) else {
                let output = ["error": "Domain is not allowed by your web filters."]
                return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: false, finishedAt: Date())
            }
            let webRequest = URLRequest(url: searchURL)
            let response = try await networkClient.fetch(webRequest, purpose: .webContentRetrieval)
            let sanitized = try await untrustedParser.parse(response.data)
            let cleaned = WebScoutACL.clean(from: sanitized)
            let filtered = await applyWebFilters(cleaned.renderedText)
            let policyDecision = await policy.evaluateWebContent(filtered)
            guard policyDecision.isAllowed else {
                let output = ["error": policyDecision.reason]
                return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: false, finishedAt: Date())
            }
            let redacted = PromptRedactor.redact(filtered).redactedText
            let accumulator = ToolOutputAccumulator(maxBytes: limits.maxOutputBytes)
            try accumulator.setValue(redacted, forKey: "result")
            if let resultsJSON = cleaned.resultsJSON {
                try accumulator.setValue(resultsJSON, forKey: "cards")
            }
            let output = accumulator.finish()
            try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
            return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: true, finishedAt: Date())
        } else if request.toolName == "untrusted.parse" {
            let payload = request.input["payload"] ?? ""
            let parsed = try await untrustedParser.parse(payload.data(using: .utf8) ?? Data())
            if limits.maxOutputBytes > 0 && parsed.utf8.count > limits.maxOutputBytes {
                throw ToolRuntimeError.outputTooLarge
            }
            let output = ["result": parsed]
            try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
            return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: true, finishedAt: Date())
        } else {
            let output = ["status": "ok", "note": "Stubbed execution for \(request.toolName)."]
            try enforceOutputLimit(output, maxBytes: limits.maxOutputBytes)
            return ToolResult(id: request.id, toolName: request.toolName, output: output, succeeded: true, finishedAt: Date())
        }
    }

    private func encodeMatches(_ matches: [LocalSearchMatch]) -> String {
        guard let data = try? JSONEncoder().encode(matches) else { return \"[]\" }
        return String(data: data, encoding: .utf8) ?? \"[]\"
    }

    private func encodeProposals(_ proposals: [String]) -> String {
        guard let data = try? JSONEncoder().encode(proposals) else { return \"[]\" }
        return String(data: data, encoding: .utf8) ?? \"[]\"
    }

    private func buildSearchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url ?? URL(string: "https://duckduckgo.com/html/") ?? URL(fileURLWithPath: "/")
    }

    private func applyWebFilters(_ text: String) async -> String {
        var result = text
        let compiled = await MainActor.run { webFilterStore.compiledFilters() }
        for entry in compiled {
            switch entry.rule.type {
            case .word:
                result = result.replacingOccurrences(
                    of: entry.rule.pattern,
                    with: "[FILTERED]",
                    options: .caseInsensitive
                )
            case .regex:
                if let regex = entry.regex {
                    let range = NSRange(location: 0, length: result.utf16.count)
                    result = regex.stringByReplacingMatches(
                        in: result,
                        options: [],
                        range: range,
                        withTemplate: "[FILTERED]"
                    )
                }
            }
        }
        return result
    }

    private func enforceOutputLimit(_ output: [String: String], maxBytes: Int) throws {
        let data = (try? JSONEncoder().encode(output)) ?? Data()
        if data.count > maxBytes {
            throw ToolRuntimeError.outputTooLarge
        }
    }

    private func sanitize(_ result: ToolResult) -> ToolResult {
        var updated = result
        updated.output = secretRedactor.redact(output: result.output)
        return updated
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ToolRuntimeError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum ToolRuntimeError: Error {
    case timeout
    case outputTooLarge
}
