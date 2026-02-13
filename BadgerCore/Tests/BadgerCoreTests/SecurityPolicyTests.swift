import Foundation
import Testing
@testable import BadgerCore

@Suite("Security Policy Tests")
struct SecurityPolicyTests {
    
    @Test("Default security policy initialization")
    func testDefaultPolicy() async throws {
        let policy = SecurityPolicy()
        
        #expect(policy.riskLevel == .standard)
        #expect(policy.executionPolicy == .balanced)
        #expect(policy.isLockdown == false)
        #expect(policy.allowsRemoteOperations == true)
        #expect(policy.prefersLocalInference == true)
    }
    
    @Test("Custom security policy initialization")
    func testCustomPolicy() async throws {
        let policy = SecurityPolicy(
            riskLevel: .advanced,
            executionPolicy: .safeMode,
            isLockdown: true
        )
        
        #expect(policy.riskLevel == .advanced)
        #expect(policy.executionPolicy == .safeMode)
        #expect(policy.isLockdown == true)
        #expect(policy.allowsRemoteOperations == false)
        #expect(policy.prefersLocalInference == false)
    }
    
    @Test("Lockdown mode operations")
    func testLockdownMode() async throws {
        let policy = SecurityPolicy(
            riskLevel: .standard,
            executionPolicy: .balanced
        )
        let lockdownPolicy = policy.enableLockdown()
        
        #expect(lockdownPolicy.isLockdown == true)
        #expect(lockdownPolicy.riskLevel == .advanced)
        #expect(lockdownPolicy.executionPolicy == .safeMode)
        #expect(lockdownPolicy.allowsRemoteOperations == false)
        
        let unlockedPolicy = lockdownPolicy.disableLockdown()
        #expect(unlockedPolicy.isLockdown == false)
        // Should restore original settings
        #expect(unlockedPolicy.riskLevel == .standard)
        #expect(unlockedPolicy.executionPolicy == .balanced)
    }
    
    @Test("Performance policy prefers local inference")
    func testPerformancePolicy() async throws {
        let policy = SecurityPolicy(executionPolicy: .performance)
        #expect(policy.prefersLocalInference == true)
        #expect(policy.allowsRemoteOperations == true)
    }
    
    @Test("Security policy manager thread safety")
    func testPolicyManager() async throws {
        let manager = SecurityPolicyManager()
        
        let initialPolicy = await manager.getPolicy()
        #expect(initialPolicy.isLockdown == false)
        
        await manager.enableLockdown()
        let lockedPolicy = await manager.getPolicy()
        #expect(lockedPolicy.isLockdown == true)
        #expect(await manager.canPerformRemoteOperations() == false)
        
        await manager.disableLockdown()
        let unlockedPolicy = await manager.getPolicy()
        #expect(unlockedPolicy.isLockdown == false)
        #expect(await manager.canPerformRemoteOperations() == true)
    }
    
    @Test("Policy equality")
    func testPolicyEquality() async throws {
        let policy1 = SecurityPolicy(
            riskLevel: .advanced,
            executionPolicy: .performance,
            isLockdown: false
        )
        let policy2 = SecurityPolicy(
            riskLevel: .advanced,
            executionPolicy: .performance,
            isLockdown: false
        )
        let policy3 = SecurityPolicy(
            riskLevel: .standard,
            executionPolicy: .balanced,
            isLockdown: false
        )
        
        #expect(policy1 == policy2)
        #expect(policy1 != policy3)
    }
    
    @Test("Policy codable conformance")
    func testPolicyCodable() async throws {
        let policy = SecurityPolicy(
            riskLevel: .advanced,
            executionPolicy: .safeMode,
            isLockdown: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(policy)
        let decoded = try decoder.decode(SecurityPolicy.self, from: data)
        
        #expect(policy.riskLevel == decoded.riskLevel)
        #expect(policy.executionPolicy == decoded.executionPolicy)
        #expect(policy.isLockdown == decoded.isLockdown)
    }
}
