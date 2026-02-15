import Foundation

// MARK: - SLA Audit Record

public struct FunctionAuditRecord: Sendable, Codable {
    public let functionName: String
    public let startTimestamp: Date
    public let endTimestamp: Date
    public let durationMs: Int
    public let inputHash: String
    public let outputHash: String
    public let memorySnapshotMb: Int
    public let slaVersion: String
    public let slaCompliant: Bool
    public let failureReason: String?
}

// MARK: - SLA Runtime Guard

public enum SLARuntimeGuard {
    public static func run<Output: Sendable>(
        functionName: String,
        inputMaterial: String,
        sla: FunctionSLA,
        auditService: AuditLogService,
        clock: FunctionClock = SystemFunctionClock(),
        operation: @escaping @Sendable () async throws -> Output,
        outputMaterial: @escaping @Sendable (Output) -> String = { String(reflecting: $0) }
    ) async -> Result<Output, FunctionError> {
        let startTimestamp = clock.now()
        let inputHash = DeterministicHasher.sha256Hex(inputMaterial)
        let startMemoryMb = MemorySnapshot.bytesToMb(MemorySnapshot.residentMemoryBytes())
        
        let timedOutcome = await runWithTimeout(
            timeoutSeconds: sla.timeoutSeconds,
            operation: operation
        )
        
        let endTimestamp = clock.now()
        let durationMs = Int(endTimestamp.timeIntervalSince(startTimestamp) * 1000)
        let endMemoryMb = MemorySnapshot.bytesToMb(MemorySnapshot.residentMemoryBytes())
        let memorySnapshotMb = max(startMemoryMb, endMemoryMb)
        
        let outcome = evaluateOutcome(
            timedOutcome: timedOutcome,
            durationMs: durationMs,
            memorySnapshotMb: memorySnapshotMb,
            sla: sla
        )
        
        let outputHash = outputHashForOutcome(outcome, outputMaterial: outputMaterial)
        await logAuditRecord(
            functionName: functionName,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            durationMs: durationMs,
            inputHash: inputHash,
            outputHash: outputHash,
            memorySnapshotMb: memorySnapshotMb,
            sla: sla,
            outcome: outcome,
            auditService: auditService
        )
        
        return outcome
    }
    
    private static func runWithTimeout<Output: Sendable>(
        timeoutSeconds: Int,
        operation: @escaping @Sendable () async throws -> Output
    ) async -> Result<Output, FunctionError> {
        await withTaskGroup(of: Result<Output, FunctionError>.self) { group in
            group.addTask {
                do {
                    try Task.checkCancellation()
                    let value = try await operation()
                    return .success(value)
                } catch is CancellationError {
                    return .failure(.cancellationRequested)
                } catch {
                    return .failure(.executionFailed(error.localizedDescription))
                }
            }
            
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    return .failure(.timeoutExceeded(seconds: timeoutSeconds))
                } catch {
                    return .failure(.cancellationRequested)
                }
            }
            
            let first = await group.next() ?? .failure(.executionFailed("Guard failed to return an outcome"))
            group.cancelAll()
            return first
        }
    }
    
    private static func evaluateOutcome<Output: Sendable>(
        timedOutcome: Result<Output, FunctionError>,
        durationMs: Int,
        memorySnapshotMb: Int,
        sla: FunctionSLA
    ) -> Result<Output, FunctionError> {
        if case .failure = timedOutcome {
            return timedOutcome
        }
        
        if durationMs > sla.maxLatencyMs {
            return .failure(.timeoutExceeded(seconds: sla.timeoutSeconds))
        }
        
        if memorySnapshotMb > sla.maxMemoryMb {
            return .failure(.memoryBudgetExceeded(limitMb: sla.maxMemoryMb, observedMb: memorySnapshotMb))
        }
        
        return timedOutcome
    }
    
    private static func outputHashForOutcome<Output: Sendable>(
        _ outcome: Result<Output, FunctionError>,
        outputMaterial: @Sendable (Output) -> String
    ) -> String {
        switch outcome {
        case .success(let value):
            return DeterministicHasher.sha256Hex(outputMaterial(value))
        case .failure(let error):
            return DeterministicHasher.sha256Hex(String(describing: error))
        }
    }
    
    private static func logAuditRecord<Output: Sendable>(
        functionName: String,
        startTimestamp: Date,
        endTimestamp: Date,
        durationMs: Int,
        inputHash: String,
        outputHash: String,
        memorySnapshotMb: Int,
        sla: FunctionSLA,
        outcome: Result<Output, FunctionError>,
        auditService: AuditLogService
    ) async {
        let failureReason = outcome.failureDescription
        let record = FunctionAuditRecord(
            functionName: functionName,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            durationMs: durationMs,
            inputHash: inputHash,
            outputHash: outputHash,
            memorySnapshotMb: memorySnapshotMb,
            slaVersion: sla.version,
            slaCompliant: failureReason == nil,
            failureReason: failureReason
        )
        
        guard let payload = encodeRecord(record) else {
            return
        }
        
        _ = try? await auditService.log(
            type: .functionExecution,
            source: functionName,
            details: payload
        )
    }
    
    private static func encodeRecord(_ record: FunctionAuditRecord) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(record) else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
}

private extension Result where Failure == FunctionError {
    var failureDescription: String? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return String(describing: error)
        }
    }
}
