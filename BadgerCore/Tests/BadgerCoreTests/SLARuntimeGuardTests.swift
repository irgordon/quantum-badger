import Testing
import Foundation
@testable import BadgerCore

@Suite("SLA Runtime Guard Tests")
struct SLARuntimeGuardTests {

    @Test("SLA breach should return success but log non-compliance")
    func testSLABreachReturnsSuccess() async throws {
        // Setup temporary audit log
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = AuditLogConfiguration(logDirectory: tempDir)
        let auditService = AuditLogService(configuration: config)

        // SLA with very strict latency (0ms) but generous timeout (1s)
        // This guarantees a latency breach.
        let strictSLA = FunctionSLA(
            maxLatencyMs: 0,
            maxMemoryMb: 100,
            deterministic: false,
            timeoutSeconds: 1,
            version: "1.0"
        )

        // Run function that takes ~10ms
        let result = await SLARuntimeGuard.run(
            functionName: "SlowFunction",
            inputMaterial: "input",
            sla: strictSLA,
            auditService: auditService,
            operation: {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return "Success"
            }
        )

        // Verify result is success
        switch result {
        case .success(let value):
            #expect(value == "Success")
        case .failure(let error):
            Issue.record("Expected success but got failure: \(error)")
        }

        // Verify audit log
        let events = try await auditService.getAllEvents()
        let executionEvent = events.last { $0.type == .functionExecution }

        #expect(executionEvent != nil)

        if let details = executionEvent?.details,
           let data = details.data(using: .utf8),
           let record = try? JSONDecoder().decode(FunctionAuditRecord.self, from: data) {

            // Should be non-compliant due to latency breach
            #expect(record.slaCompliant == false, "Record should be marked non-compliant due to latency breach")

            // Verify failure reason contains info about the breach if possible,
            // or at least is not nil?
            // The requirement didn't specify what failureReason should be on success-with-breach.
            // But usually non-compliant implies there's a reason.
            // For now, let's just assert compliance is false.
        } else {
            Issue.record("Could not decode audit record")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Memory breach should return success but log non-compliance")
    func testMemoryBreachReturnsSuccess() async throws {
        // Setup temporary audit log
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = AuditLogConfiguration(logDirectory: tempDir)
        let auditService = AuditLogService(configuration: config)

        // SLA with strict memory limit (0MB)
        let strictSLA = FunctionSLA(
            maxLatencyMs: 1000,
            maxMemoryMb: 0, // Impossible to meet
            deterministic: false,
            timeoutSeconds: 1,
            version: "1.0"
        )

        let result = await SLARuntimeGuard.run(
            functionName: "MemoryHog",
            inputMaterial: "input",
            sla: strictSLA,
            auditService: auditService,
            operation: {
                return "Success"
            }
        )

        switch result {
        case .success(let value):
            #expect(value == "Success")
        case .failure(let error):
            Issue.record("Expected success but got failure: \(error)")
        }

        let events = try await auditService.getAllEvents()
        let executionEvent = events.last { $0.type == .functionExecution }

        if let details = executionEvent?.details,
           let data = details.data(using: .utf8),
           let record = try? JSONDecoder().decode(FunctionAuditRecord.self, from: data) {
            #expect(record.slaCompliant == false, "Record should be marked non-compliant due to memory breach")
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
