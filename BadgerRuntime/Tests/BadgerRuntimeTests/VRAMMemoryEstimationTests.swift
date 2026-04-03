import Foundation
import Testing
@testable import BadgerRuntime
import BadgerCore

@Suite("VRAM Memory Estimation Tests")
struct VRAMMemoryEstimationTests {

    // MARK: - VRAMStatus Tests

    @Test("VRAMStatus availableVRAM calculation")
    func testAvailableVRAM() {
        // Safe limit is 75% of recommendedMaxWorkingSetSize
        let max: UInt64 = 16 * 1024 * 1024 * 1024 // 16GB
        let safeLimit = UInt64(Double(max) * 0.75) // 12GB

        // Case 1: No allocated memory
        let status1 = VRAMStatus(recommendedMaxWorkingSetSize: max, currentAllocatedSize: nil)
        #expect(status1.availableVRAM == safeLimit)

        // Case 2: Allocated memory within safe limit
        let allocated: UInt64 = 4 * 1024 * 1024 * 1024 // 4GB
        let status2 = VRAMStatus(recommendedMaxWorkingSetSize: max, currentAllocatedSize: allocated)
        #expect(status2.availableVRAM == safeLimit - allocated)

        // Case 3: Allocated memory exceeding safe limit
        let overAllocated: UInt64 = 14 * 1024 * 1024 * 1024 // 14GB
        let status3 = VRAMStatus(recommendedMaxWorkingSetSize: max, currentAllocatedSize: overAllocated)
        #expect(status3.availableVRAM == 0)
    }

    @Test("VRAMStatus hasSufficientVRAM threshold")
    func testHasSufficientVRAM() {
        // 4GB minimum threshold
        let fourGB: UInt64 = 4 * 1024 * 1024 * 1024

        // Exactly 4GB available (using 0 allocated for simplicity)
        // availableVRAM = max * 0.75
        // max = availableVRAM / 0.75
        let maxForExactly4GB = UInt64(Double(fourGB) / 0.75)
        let status1 = VRAMStatus(recommendedMaxWorkingSetSize: maxForExactly4GB, currentAllocatedSize: 0)
        #expect(status1.hasSufficientVRAM == true)

        // Just below 4GB
        let status2 = VRAMStatus(recommendedMaxWorkingSetSize: maxForExactly4GB - 100, currentAllocatedSize: 0)
        #expect(status2.hasSufficientVRAM == false)
    }

    @Test("VRAMStatus usageRatio calculation")
    func testUsageRatio() {
        let max: UInt64 = 100

        // Case 1: Nil allocated
        let status1 = VRAMStatus(recommendedMaxWorkingSetSize: max, currentAllocatedSize: nil)
        #expect(status1.usageRatio == 0.0)

        // Case 2: 50% allocated
        let status2 = VRAMStatus(recommendedMaxWorkingSetSize: max, currentAllocatedSize: 50)
        #expect(status2.usageRatio == 0.5)

        // Case 3: Zero max
        let status3 = VRAMStatus(recommendedMaxWorkingSetSize: 0, currentAllocatedSize: 50)
        #expect(status3.usageRatio == 0.0)
    }

    @Test("VRAMStatus recommendedQuantization thresholds")
    func testRecommendedQuantization() {
        // Thresholds from code:
        // case 24...: return .none
        // case 12..<24: return .q8
        // case 6..<12: return .q4
        // default: return .q4

        func statusWithAvailable(_ gb: Double) -> VRAMStatus {
            let availableBytes = UInt64(gb * 1024 * 1024 * 1024)
            let maxBytes = UInt64(Double(availableBytes) / 0.75)
            return VRAMStatus(recommendedMaxWorkingSetSize: maxBytes, currentAllocatedSize: 0)
        }

        #expect(statusWithAvailable(25).recommendedQuantization == .none)
        #expect(statusWithAvailable(24).recommendedQuantization == .none)
        #expect(statusWithAvailable(23.9).recommendedQuantization == .q8)
        #expect(statusWithAvailable(12).recommendedQuantization == .q8)
        #expect(statusWithAvailable(11.9).recommendedQuantization == .q4)
        #expect(statusWithAvailable(6).recommendedQuantization == .q4)
        #expect(statusWithAvailable(5.9).recommendedQuantization == .q4)
    }

    // MARK: - VRAMMonitor Calculation Helper Tests

    @Test("calculateMaxModelSize buffer logic")
    func testCalculateMaxModelSize() {
        let monitor = VRAMMonitor()
        let buffer: UInt64 = 1536 * 1024 * 1024 // 1.5GB

        // More than buffer
        let avail1 = buffer + 1024
        #expect(monitor.calculateMaxModelSize(availableVRAM: avail1) == 1024)

        // Less than buffer
        let avail2 = buffer - 1024
        #expect(monitor.calculateMaxModelSize(availableVRAM: avail2) == 0)

        // Exactly buffer
        #expect(monitor.calculateMaxModelSize(availableVRAM: buffer) == 0)
    }

    @Test("calculateRecommendedModelClass thresholds")
    func testCalculateRecommendedModelClass() {
        let monitor = VRAMMonitor()
        let gb: UInt64 = 1024 * 1024 * 1024

        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 16 * gb) == .phi4)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 15 * gb) == .llama31)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 10 * gb) == .llama31)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 9 * gb) == .mistral)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 6 * gb) == .mistral)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 5 * gb) == .qwen25)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 4 * gb) == .qwen25)
        #expect(monitor.calculateRecommendedModelClass(availableVRAM: 3 * gb) == .gemma2)
    }

    @Test("calculateOptimalBatchSize thresholds")
    func testCalculateOptimalBatchSize() {
        let monitor = VRAMMonitor()
        let gb: UInt64 = 1024 * 1024 * 1024

        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 25 * gb) == 8)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 24 * gb) == 8)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 23 * gb) == 4)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 16 * gb) == 4)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 15 * gb) == 1)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 8 * gb) == 1)
        #expect(monitor.calculateOptimalBatchSize(availableVRAM: 4 * gb) == 1)
    }

    // MARK: - Model Memory Estimation Tests

    @Test("estimateModelMemory formula verification")
    func testEstimateModelMemory() {
        let monitor = VRAMMonitor()

        // Formula: parameterCountBillions * 1,000,000,000 * bits / 8 * 1.2

        // 7B model, Q4 (4 bits)
        // 7 * 10^9 * 4 / 8 * 1.2 = 7 * 10^9 * 0.5 * 1.2 = 7 * 10^9 * 0.6 = 4.2 * 10^9
        let mem7BQ4 = monitor.estimateModelMemory(parameterCountBillions: 7, quantization: .q4)
        #expect(mem7BQ4 == 4_200_000_000)

        // 14B model, Q8 (8 bits)
        // 14 * 10^9 * 8 / 8 * 1.2 = 14 * 10^9 * 1 * 1.2 = 16.8 * 10^9
        let mem14BQ8 = monitor.estimateModelMemory(parameterCountBillions: 14, quantization: .q8)
        #expect(mem14BQ8 == 16_800_000_000)

        // 0B model
        let mem0 = monitor.estimateModelMemory(parameterCountBillions: 0, quantization: .q4)
        #expect(mem0 == 0)

        // Test all quantization levels
        for level in QuantizationLevel.allCases {
            let params = 10.0
            let expected = UInt64(params * 1_000_000_000 * Double(level.bits) / 8 * 1.2)
            #expect(monitor.estimateModelMemory(parameterCountBillions: params, quantization: level) == expected)
        }
    }
}
