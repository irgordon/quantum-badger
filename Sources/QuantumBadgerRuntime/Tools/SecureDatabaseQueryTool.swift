import Foundation

struct SecureDatabaseQueryTool: SecureInjectionTool {
    let toolName: String = "db.query"
    private let dbClient = DatabaseQueryXPCClient()

    func run(
        request: ToolRequest,
        vaultStore: VaultStore,
        secretRedactor: SecretRedactor,
        limits: ToolExecutionLimits
    ) async throws -> ToolResult {
        let query = request.input["query"] ?? ""
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Query is empty."],
                succeeded: false,
                finishedAt: Date()
            )
        }
        guard SQLSelectValidator.validate(query, maxTokens: limits.maxQueryTokens) else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Only read-only SELECT queries are supported."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        guard let bookmarkData = resolveBookmarkData(from: request, vaultStore: vaultStore) else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Missing secure database reference."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        do {
            let response = try await dbClient.query(
                requestId: request.id,
                bookmarkData: bookmarkData,
                sql: query,
                parametersJSON: request.input["parameters"],
                maxOutputBytes: limits.maxOutputBytes,
                maxFileBytes: limits.maxFileBytes,
                maxQueryTokens: limits.maxQueryTokens
            )
            if response.isStale {
                return ToolResult(
                    id: request.id,
                    toolName: request.toolName,
                    output: [
                        "error": "Saved database location needs to be chosen again.",
                        "staleBookmark": "true"
                    ],
                    succeeded: false,
                    finishedAt: Date()
                )
            }
            let output: [String: String] = [
                "columns": response.columnsJSON,
                "rows": response.rowsJSON,
                "truncated": response.truncated ? "true" : "false"
            ]
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: output,
                succeeded: true,
                finishedAt: Date()
            )
        } catch {
            let message = error is CancellationError ? "Database query cancelled." : "Unable to query database."
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": message],
                succeeded: false,
                finishedAt: Date()
            )
        }
    }

    private func resolveBookmarkData(from request: ToolRequest, vaultStore: VaultStore) -> Data? {
        guard let refLabel = request.input["connectionRef"],
              let references = request.vaultReferences,
              let reference = references.first(where: { $0.label == refLabel }) else {
            return nil
        }
        return vaultStore.bookmarkData(for: reference)
    }
}

private enum SQLSelectValidator {
    private static let forbiddenKeywords: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "ATTACH", "DETACH",
        "PRAGMA", "VACUUM", "REINDEX", "REPLACE", "UPSERT", "BEGIN", "COMMIT", "ROLLBACK"
    ]

    private static let clauseKeywords: Set<String> = [
        "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION"
    ]

    static func validate(_ sql: String, maxTokens: Int) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let tokens = tokenize(trimmed) else { return false }
        let resolvedMaxTokens = maxTokens > 0 ? maxTokens : 512
        guard tokens.count <= resolvedMaxTokens else { return false }
        let parser = Parser(tokens: tokens)
        return parser.parse()
    }

    private enum Token: Equatable {
        case keyword(String)
        case identifier(String)
        case number
        case string
        case symbol(String)
    }

    private static func tokenize(_ sql: String) -> [Token]? {
        var tokens: [Token] = []
        var index = sql.startIndex

        func advance() { index = sql.index(after: index) }

        while index < sql.endIndex {
            let char = sql[index]
            if char.isWhitespace {
                advance()
                continue
            }

            if char == "-" {
                let next = sql.index(after: index)
                if next < sql.endIndex, sql[next] == "-" { return nil }
            }
            if char == "/" {
                let next = sql.index(after: index)
                if next < sql.endIndex, sql[next] == "*" { return nil }
            }
            if char == ";" { return nil }

            if char == "'" {
                advance()
                var closed = false
                while index < sql.endIndex {
                    let c = sql[index]
                    if c == "'" {
                        let next = sql.index(after: index)
                        if next < sql.endIndex, sql[next] == "'" {
                            index = sql.index(after: next)
                            continue
                        } else {
                            advance()
                            closed = true
                            break
                        }
                    }
                    advance()
                }
                guard closed else { return nil }
                tokens.append(.string)
                continue
            }

            if char.isNumber {
                var cursor = index
                while cursor < sql.endIndex, sql[cursor].isNumber || sql[cursor] == "." {
                    cursor = sql.index(after: cursor)
                }
                index = cursor
                tokens.append(.number)
                continue
            }

            if char.isLetter || char == "_" {
                var cursor = index
                while cursor < sql.endIndex {
                    let c = sql[cursor]
                    if c.isLetter || c.isNumber || c == "_" {
                        cursor = sql.index(after: cursor)
                    } else {
                        break
                    }
                }
                let raw = String(sql[index..<cursor])
                let upper = raw.uppercased()
                if forbiddenKeywords.contains(upper) {
                    return nil
                }
                if clauseKeywords.contains(upper) || upper == "SELECT" || upper == "WITH" || upper == "RECURSIVE" || upper == "AS" || upper == "BY" || upper == "DISTINCT" || upper == "ALL" {
                    tokens.append(.keyword(upper))
                } else {
                    tokens.append(.identifier(raw))
                }
                index = cursor
                continue
            }

            let symbol = String(char)
            tokens.append(.symbol(symbol))
            advance()
        }
        return tokens
    }

    private struct Parser {
        private var tokens: [Token]
        private var index: Int = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func parse() -> Bool {
            guard !tokens.isEmpty else { return false }
            if consumeKeyword("WITH") {
                if !parseWithClause() { return false }
            }
            if !parseSelectCompound() { return false }
            return index == tokens.count
        }

        private mutating func parseWithClause() -> Bool {
            _ = consumeKeyword("RECURSIVE")
            while true {
                guard consumeIdentifier() else { return false }
                if consumeSymbol("(") {
                    if !parseIdentifierList() { return false }
                    guard consumeSymbol(")") else { return false }
                }
                guard consumeKeyword("AS") else { return false }
                guard consumeSymbol("(") else { return false }
                if !parseSelectCompound() { return false }
                guard consumeSymbol(")") else { return false }
                if !consumeSymbol(",") { break }
            }
            return true
        }

        private mutating func parseSelectCompound() -> Bool {
            guard parseSelectCore() else { return false }
            while consumeKeyword("UNION") {
                _ = consumeKeyword("ALL")
                _ = consumeKeyword("DISTINCT")
                guard parseSelectCore() else { return false }
            }
            if consumeKeyword("ORDER") {
                guard consumeKeyword("BY") else { return false }
                guard parseExpressionList() else { return false }
            }
            if consumeKeyword("LIMIT") {
                guard parseExpressionList() else { return false }
                if consumeKeyword("OFFSET") {
                    guard parseExpressionList() else { return false }
                }
            } else if consumeKeyword("OFFSET") {
                guard parseExpressionList() else { return false }
            }
            return true
        }

        private mutating func parseSelectCore() -> Bool {
            guard consumeKeyword("SELECT") else { return false }
            _ = consumeKeyword("DISTINCT")
            _ = consumeKeyword("ALL")
            guard parseExpressionList(stopAt: ["FROM", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION"]) else { return false }
            if consumeKeyword("FROM") {
                guard parseExpressionList(stopAt: ["WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION"]) else { return false }
            }
            if consumeKeyword("WHERE") {
                guard parseExpressionList(stopAt: ["GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION"]) else { return false }
            }
            if consumeKeyword("GROUP") {
                guard consumeKeyword("BY") else { return false }
                guard parseExpressionList(stopAt: ["HAVING", "ORDER", "LIMIT", "OFFSET", "UNION"]) else { return false }
            }
            if consumeKeyword("HAVING") {
                guard parseExpressionList(stopAt: ["ORDER", "LIMIT", "OFFSET", "UNION"]) else { return false }
            }
            if consumeKeyword("ORDER") {
                guard consumeKeyword("BY") else { return false }
                guard parseExpressionList(stopAt: ["LIMIT", "OFFSET", "UNION"]) else { return false }
            }
            if consumeKeyword("LIMIT") {
                guard parseExpressionList(stopAt: ["OFFSET", "UNION"]) else { return false }
                if consumeKeyword("OFFSET") {
                    guard parseExpressionList(stopAt: ["UNION"]) else { return false }
                }
            } else if consumeKeyword("OFFSET") {
                guard parseExpressionList(stopAt: ["UNION"]) else { return false }
            }
            return true
        }

        private mutating func parseIdentifierList() -> Bool {
            guard consumeIdentifier() else { return false }
            while consumeSymbol(",") {
                guard consumeIdentifier() else { return false }
            }
            return true
        }

        private mutating func parseExpressionList(stopAt: Set<String>? = nil) -> Bool {
            return parseExpressionList(stopAt: stopAt ?? [])
        }

        private mutating func parseExpressionList(stopAt: [String]) -> Bool {
            var depth = 0
            var consumedAny = false
            while index < tokens.count {
                if let keyword = peekKeyword(), stopAt.contains(keyword), depth == 0 {
                    break
                }
                if case .symbol("(") = tokens[index] {
                    depth += 1
                } else if case .symbol(")") = tokens[index] {
                    if depth == 0 { break }
                    depth -= 1
                }
                consumedAny = true
                index += 1
            }
            return consumedAny
        }

        private func peekKeyword() -> String? {
            guard index < tokens.count else { return nil }
            if case .keyword(let value) = tokens[index] {
                return value
            }
            return nil
        }

        @discardableResult
        private mutating func consumeKeyword(_ value: String) -> Bool {
            guard index < tokens.count else { return false }
            if case .keyword(let keyword) = tokens[index], keyword == value {
                index += 1
                return true
            }
            return false
        }

        @discardableResult
        private mutating func consumeIdentifier() -> Bool {
            guard index < tokens.count else { return false }
            switch tokens[index] {
            case .identifier:
                index += 1
                return true
            case .keyword(let value) where !clauseKeywords.contains(value) && value != "SELECT" && value != "WITH" && value != "AS":
                index += 1
                return true
            default:
                return false
            }
        }

        @discardableResult
        private mutating func consumeSymbol(_ value: String) -> Bool {
            guard index < tokens.count else { return false }
            if case .symbol(let symbol) = tokens[index], symbol == value {
                index += 1
                return true
            }
            return false
        }
    }
}
