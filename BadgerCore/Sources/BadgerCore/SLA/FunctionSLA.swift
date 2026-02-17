import Foundation
import CryptoKit
import Darwin

// MARK: - Function SLA

public struct FunctionSLA: Sendable, Equatable {
    public let maxLatencyMs: Int
    public let maxMemoryMb: Int
    public let deterministic: Bool
    public let timeoutSeconds: Int
    public let version: String
    
    public init(
        maxLatencyMs: Int,
        maxMemoryMb: Int,
        deterministic: Bool,
        timeoutSeconds: Int,
        version: String
    ) {
        self.maxLatencyMs = maxLatencyMs
        self.maxMemoryMb = maxMemoryMb
        self.deterministic = deterministic
        self.timeoutSeconds = timeoutSeconds
        self.version = version
    }
}

// MARK: - Function Errors

public enum FunctionError: Error, Sendable, Equatable {
    case invalidInput(String)
    case timeoutExceeded(seconds: Int)
    case cancellationRequested
    case memoryBudgetExceeded(limitMb: Int, observedMb: Int)
    case deterministicViolation(String)
    case executionFailed(String)
    case auditLoggingFailed(String)
}

// MARK: - Function Clock

public protocol FunctionClock: Sendable {
    func now() -> Date
}

public struct SystemFunctionClock: FunctionClock {
    public init() {}
    
    public func now() -> Date {
        Date()
    }
}

// MARK: - Deterministic Hashing

public enum DeterministicHasher {
    public static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Memory Snapshot

public enum MemorySnapshot {
    public static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), integerPointer, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return UInt64(info.resident_size)
    }
    
    public static func bytesToMb(_ bytes: UInt64) -> Int {
        Int(bytes / 1_048_576)
    }
}
