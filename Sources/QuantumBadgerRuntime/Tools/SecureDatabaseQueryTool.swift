import Foundation
import SQLite3

struct SecureDatabaseQueryTool: SecureInjectionTool {
    let toolName: String = "db.query"

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

        guard let dbPath = resolveConnectionPath(from: request, vaultStore: vaultStore, redactor: secretRedactor) else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Missing database connection reference."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        guard fileSizeOK(dbPath, maxBytes: limits.maxFileBytes) else {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Database file is too large."],
                succeeded: false,
                finishedAt: Date()
            )
        }

        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Unable to open database."],
                succeeded: false,
                finishedAt: Date()
            )
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            return ToolResult(
                id: request.id,
                toolName: request.toolName,
                output: ["error": "Query failed to prepare."],
                succeeded: false,
                finishedAt: Date()
            )
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var columns: [String] = []
        columns.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
            if let name = sqlite3_column_name(statement, index) {
                columns.append(String(cString: name))
            } else {
                columns.append("column\(index)")
            }
        }

        var rows: [[String]] = []
        var estimatedBytes = 0
        let maxRows = 200
        while sqlite3_step(statement) == SQLITE_ROW {
            if Task.isCancelled { break }
            var row: [String] = []
            row.reserveCapacity(Int(columnCount))
            for index in 0..<columnCount {
                if let value = sqlite3_column_text(statement, index) {
                    let stringValue = String(cString: value)
                    row.append(stringValue)
                    estimatedBytes += stringValue.utf8.count
                } else {
                    row.append("")
                }
            }
            rows.append(row)
            if rows.count >= maxRows { break }
            if limits.maxOutputBytes > 0 && estimatedBytes > limits.maxOutputBytes {
                break
            }
        }

        let output: [String: String] = [
            "columns": encode(columns),
            "rows": encode(rows),
            "truncated": (limits.maxOutputBytes > 0 && estimatedBytes > limits.maxOutputBytes) ? "true" : "false"
        ]
        return ToolResult(
            id: request.id,
            toolName: request.toolName,
            output: output,
            succeeded: true,
            finishedAt: Date()
        )
    }

    private func resolveConnectionPath(
        from request: ToolRequest,
        vaultStore: VaultStore,
        redactor: SecretRedactor
    ) -> String? {
        if let refLabel = request.input["connectionRef"],
           let references = request.vaultReferences,
           let reference = references.first(where: { $0.label == refLabel }),
           let secretPath = vaultStore.secret(for: reference) {
            redactor.register(secretPath)
            return normalizeSQLitePath(secretPath)
        }
        if let rawPath = request.input["connectionString"] {
            redactor.register(rawPath)
            return normalizeSQLitePath(rawPath)
        }
        return nil
    }

    private func normalizeSQLitePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sqlite:///") {
            return String(trimmed.dropFirst("sqlite:///".count - 1))
        }
        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)?.path
        }
        return trimmed
    }

    private func fileSizeOK(_ path: String, maxBytes: Int) -> Bool {
        guard maxBytes > 0 else { return true }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attributes?[.size] as? NSNumber {
            return size.intValue <= maxBytes
        }
        return true
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
