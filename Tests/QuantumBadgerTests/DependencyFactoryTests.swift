import XCTest
import SwiftData
@testable import BadgerCore
@testable import QuantumBadgerRuntime
// Note: If your app target is named "Quantum_Badger", import that too via @testable
#if canImport(BadgerApp)
@testable import BadgerApp

final class DependencyFactoryTests: XCTestCase {

    // We need a MainActor context because the Factory is @MainActor
    @MainActor
    func testDependencyGraphConstruction() throws {
        // 1. Setup: Create an In-Memory SwiftData Container
        // This simulates the app launching without writing to disk
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MemoryRecord.self, configurations: config)
        
        // 2. Execution: trigger the "Big Bang"
        // We measure how long it takes to ensure startup doesn't regress
        let startTime = Date()
        let bundle = AppDependencyFactory.buildDependencies(modelContext: container.mainContext)
        let duration = Date().timeIntervalSince(startTime)
        
        print("🚀 Dependency Graph built in \(String(format: "%.4f", duration))s")
        
        // 3. Verification: The "Pulse Check"
        
        // A. Critical Runtime Capabilities
        XCTAssertNotNil(bundle.runtimeCapabilities.orchestrator, "Orchestrator must be alive")
        XCTAssertNotNil(bundle.runtimeCapabilities.networkClient, "Network Client must be alive")
        
        // B. Security Policy Integrity
        XCTAssertNotNil(bundle.securityCapabilities.policy, "Policy Engine must be active")
        XCTAssertNotNil(bundle.securityCapabilities.systemOperator, "System Operator caps must be present")
        
        // C. Storage Links
        XCTAssertNotNil(bundle.storageCapabilities.auditLog, "Audit Log must be active")
        XCTAssertNotNil(bundle.storageCapabilities.memoryManager, "Memory Manager must be connected to SwiftData")
        
        // D. Split-Brain Accessors (Top-Level)
        XCTAssertNotNil(bundle.identityRecoveryManager, "Identity Recovery must be accessible at top level")
        XCTAssertNotNil(bundle.executionRecoveryManager, "Execution Recovery must be accessible at top level")
        
        // 4. Reference check (Optional but good)
        // Ensure the AuditLog instance is shared, not duplicated
        let securityLog = bundle.securityCapabilities.networkPolicy.auditLog // You'll need to expose this in NetworkPolicy for testing, or check identity
        let storageLog = bundle.storageCapabilities.auditLog
        
        // This implies that both systems are writing to the SAME log, which is critical for compliance
        XCTAssertTrue(securityLog === storageLog, "Audit Log instance must be a shared singleton reference")
    }
}
#endif

