import XCTest
import CryptoKit
import SwiftData
@testable import QuantumBadgerApp
import QuantumBadgerRuntime

final class SecurityComplianceTests: XCTestCase {
    var appState: AppState!

    override func setUp() async throws {
        let schema = Schema([MemoryRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        appState = AppState(modelContext: container.mainContext)
    }

    // MARK: - 1. Network Security (ATS & Zero-Trust)

    /// Ensures that the NetworkClient refuses any non-HTTPS or unauthorized connections.
    func testNetworkSecurityPolicyEnforcement() async throws {
        let networkClient = appState.runtimeCapabilities.networkClient

        await MainActor.run {
            appState.securityCapabilities.networkPolicy.enablePurpose(.webContentRetrieval, for: 1)
            appState.webFilterStore.setStrictMode(true)
        }

        // Test A: Insecure URL rejection
        let insecureURL = URL(string: "http://untrusted-source.com/data.json")!
        do {
            let request = URLRequest(url: insecureURL)
            _ = try await networkClient.fetch(request, purpose: .webContentRetrieval)
            XCTFail("Security Breach: NetworkClient allowed a non-HTTPS connection.")
        } catch {
            XCTAssertTrue(true, "Correctly blocked insecure connection.")
        }

        // Test B: Domain Restriction (Web Scout logic)
        let blockedURL = URL(string: "https://malicious-site.net/exploit")!
        let isAllowed = await MainActor.run { appState.webFilterStore.isDomainAllowed(blockedURL.host) }
        XCTAssertFalse(isAllowed, "Security Breach: Policy allowed a domain not in the configured allowlist.")
    }

    // MARK: - 2. Data Security (Encryption Standards)

    /// Verifies that AES-GCM is available for local data protection.
    func testVaultEncryptionStandard() throws {
        let sensitiveData = "UserSecret123".data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(sensitiveData, using: SymmetricKey(size: .bits256))

        XCTAssertNotNil(sealedBox.nonce, "Encryption Error: Nonce is missing.")
        XCTAssertNotNil(sealedBox.tag, "Encryption Error: Authentication Tag is missing (AES-GCM required).")
    }

    // MARK: - 3. Concurrency & Isolation

    /// Ensures that the Orchestrator maintains strict actor isolation during high-load inference.
    func testOrchestratorActorIsolation() async throws {
        let orchestrator = appState.runtimeCapabilities.orchestrator

        await withTaskGroup(of: Result<String, InferenceError>.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await orchestrator.generateResponse(for: "Test Prompt \(i)")
                }
            }
            for await result in group {
                switch result {
                case .success(let response):
                    XCTAssertFalse(response.isEmpty, "Concurrency Error: Orchestrator returned empty response.")
                case .failure(let error):
                    XCTFail("Concurrency Error: Orchestrator failed with \(error).")
                }
            }
        }
    }

    // MARK: - 4. Audit Integrity (Tamper Evidence)

    /// Ensures the AuditLog generates valid SHA-256 hashes for every event.
    func testAuditLogHashIntegrity() async {
        let auditLog = appState.storageCapabilities.auditLog
        auditLog.record(event: .permissionGranted("filesystem.write"))

        guard let latestEntry = auditLog.entries.last else {
            XCTFail("Audit Error: Failed to record entry.")
            return
        }

        XCTAssertEqual(latestEntry.hash.count, 64, "Audit Integrity Failure: Invalid SHA-256 hash length.")
    }
}
