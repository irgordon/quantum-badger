import Foundation
import Metal
import Testing
@testable import BadgerRuntime

@Suite("Hardware Monitor Tests")
struct HardwareMonitorTests {
    
    @Test("VRAM Monitor availability check")
    func testVRAMMonitorAvailability() async throws {
        let monitor = VRAMMonitor()
        let isAvailable = await monitor.isAvailable()
        
        // Assert consistency with system device creation
        let systemDevice = MTLCreateSystemDefaultDevice()
        #expect(isAvailable == (systemDevice != nil))
    }

    @Test("VRAM Monitor live logic")
    func testVRAMMonitorLiveLogic() async throws {
        let monitor = VRAMMonitor()
        let isAvailable = await monitor.isAvailable()
        let status = await monitor.getCurrentStatus()
        let recommendedSize = await monitor.getRecommendedMaxWorkingSetSize()

        #expect(status.recommendedMaxWorkingSetSize == recommendedSize)

        if isAvailable {
            #expect(recommendedSize > 0)

            // Test canFitModel
            #expect(await monitor.canFitModel(requiredBytes: 0) == true)
            #expect(await monitor.canFitModel(requiredBytes: .max) == false)

            // Test estimateMaxModelSize
            let estimatedMax = await monitor.estimateMaxModelSize()
            let availableVRAM = status.availableVRAM
            let buffer: UInt64 = 1536 * 1024 * 1024 // 1.5GB buffer

            if availableVRAM > buffer {
                #expect(estimatedMax == availableVRAM - buffer)
            } else {
                #expect(estimatedMax == 0)
            }

            // Test getRecommendedQuantization
            let recommendedQuant = try await monitor.getRecommendedQuantization()
            #expect(recommendedQuant == status.recommendedQuantization)
        } else {
            #expect(recommendedSize == 0)
            #expect(await monitor.canFitModel(requiredBytes: 1) == false)
            #expect(await monitor.estimateMaxModelSize() == 0)
        }
    }
    
    @Test("VRAM Status calculation")
    func testVRAMStatus() async throws {
        let status = VRAMStatus(
            recommendedMaxWorkingSetSize: 16 * 1024 * 1024 * 1024, // 16GB
            currentAllocatedSize: 4 * 1024 * 1024 * 1024          // 4GB
        )
        
        // Available should be 75% of max minus allocated (implementation uses 0.75 safe limit)
        let expectedAvailable = UInt64(Double(16 * 1024 * 1024 * 1024) * 0.75) - (4 * 1024 * 1024 * 1024)
        #expect(status.availableVRAM == expectedAvailable)
        #expect(status.hasSufficientVRAM == true) // Should have more than 4GB
    }
    
    @Test("VRAM quantization recommendations")
    func testVRAMQuantizationRecommendations() async throws {
        let highVRAM = VRAMStatus(
            recommendedMaxWorkingSetSize: 32 * 1024 * 1024 * 1024, // 32GB
            currentAllocatedSize: nil
        )
        #expect(highVRAM.recommendedQuantization == .none || highVRAM.recommendedQuantization == .q8)
        
        let mediumVRAM = VRAMStatus(
            recommendedMaxWorkingSetSize: 12 * 1024 * 1024 * 1024, // 12GB
            currentAllocatedSize: nil
        )
        #expect(mediumVRAM.recommendedQuantization == .q8 || mediumVRAM.recommendedQuantization == .q4)
        
        let lowVRAM = VRAMStatus(
            recommendedMaxWorkingSetSize: 4 * 1024 * 1024 * 1024, // 4GB
            currentAllocatedSize: nil
        )
        #expect(lowVRAM.recommendedQuantization == .q4 || lowVRAM.recommendedQuantization == .q3)
    }
    
    @Test("Quantization level properties")
    func testQuantizationLevelProperties() async throws {
        #expect(QuantizationLevel.none.bits == 16)
        #expect(QuantizationLevel.q8.bits == 8)
        #expect(QuantizationLevel.q4.bits == 4)
        #expect(QuantizationLevel.q3.bits == 3)
        
        #expect(QuantizationLevel.none.isQualityPreserving == true)
        #expect(QuantizationLevel.q8.isQualityPreserving == true)
        #expect(QuantizationLevel.q2.isQualityPreserving == false)
    }
    
    @Test("VRAM Monitor memory estimation")
    func testMemoryEstimation() async throws {
        let monitor = VRAMMonitor()
        
        // Test 7B model with Q4 quantization
        let memory7BQ4 = monitor.estimateModelMemory(
            parameterCountBillions: 7,
            quantization: .q4
        )
        // 7B * 4 bits / 8 bits per byte * 1.2 overhead = ~4.2GB
        #expect(memory7BQ4 > 3_500_000_000)
        #expect(memory7BQ4 < 5_000_000_000)
        
        // Test 14B model with Q8 quantization
        let memory14BQ8 = monitor.estimateModelMemory(
            parameterCountBillions: 14,
            quantization: .q8
        )
        // 14B * 8 bits / 8 * 1.2 = ~16.8GB
        #expect(memory14BQ8 > 15_000_000_000)
    }
    
    @Test("VRAM Monitor model recommendations")
    func testModelRecommendations() async throws {
        let monitor = VRAMMonitor()
        let status = await monitor.getCurrentStatus()
        let availableGB = Double(status.availableVRAM) / (1024 * 1024 * 1024)

        let recommendedClass = await monitor.recommendModelClass()
        let batchSize = await monitor.getOptimalBatchSize()

        // Verify consistency with VRAM thresholds in VRAMMonitor.swift
        switch availableGB {
        case 16...:
            #expect(recommendedClass == .phi4)
        case 10..<16:
            #expect(recommendedClass == .llama31)
        case 6..<10:
            #expect(recommendedClass == .mistral)
        case 4..<6:
            #expect(recommendedClass == .qwen25)
        default:
            #expect(recommendedClass == .gemma2)
        }
        
        switch availableGB {
        case 24...:
            #expect(batchSize == 8)
        case 16..<24:
            #expect(batchSize == 4)
        case 8..<16:
            #expect(batchSize == 1)
        default:
            #expect(batchSize == 1)
        }
    }
    
    @Test("Thermal Guard initial state")
    func testThermalGuardInitialState() async throws {
        let guard_monitor = ThermalGuard()
        let status = await guard_monitor.getCurrentStatus()
        
        // Should have some valid state
        #expect(status.state == .nominal || status.state == .fair || 
                status.state == .serious || status.state == .critical)
    }
    
    @Test("Thermal Guard stress detection")
    func testThermalStressDetection() async throws {
        let guard_monitor = ThermalGuard()
        
        // Test with nominal state
        let nominalStatus = ThermalStatus(state: .nominal, timestamp: Date())
        #expect(nominalStatus.isUnderStress == false)
        #expect(nominalStatus.shouldThrottle == false)
        #expect(nominalStatus.shouldSuspend == false)
        #expect(nominalStatus.recommendedAction == .proceed)
        
        // Test with fair state
        let fairStatus = ThermalStatus(state: .fair, timestamp: Date())
        #expect(fairStatus.isUnderStress == false)
        #expect(fairStatus.shouldThrottle == true)
        #expect(fairStatus.recommendedAction == .throttle)
        
        // Test with serious state
        let seriousStatus = ThermalStatus(state: .serious, timestamp: Date())
        #expect(seriousStatus.isUnderStress == true)
        #expect(seriousStatus.shouldSuspend == false)
        #expect(seriousStatus.recommendedAction == .offloadToCloud)
        
        // Test with critical state
        let criticalStatus = ThermalStatus(state: .critical, timestamp: Date())
        #expect(criticalStatus.isUnderStress == true)
        #expect(criticalStatus.shouldSuspend == true)
        #expect(criticalStatus.recommendedAction == .suspend)
    }
    
    @Test("Thermal State Change tracking")
    func testThermalStateChange() async throws {
        let change = ThermalStateChange(
            previous: .nominal,
            current: .serious,
            timestamp: Date()
        )
        
        #expect(change.isWorsening == true)
        #expect(change.isImproving == false)
        
        let improvement = ThermalStateChange(
            previous: .serious,
            current: .fair,
            timestamp: Date()
        )
        
        #expect(improvement.isWorsening == false)
        #expect(improvement.isImproving == true)
    }
    
    @Test("Static VRAM check")
    func testStaticVRAMCheck() async throws {
        // Assert consistency with system device creation
        let systemDevice = MTLCreateSystemDefaultDevice()
        let hasVRAM = VRAMMonitor.hasSufficientVRAM()
        
        if let device = systemDevice {
            let expectedHasVRAM = device.recommendedMaxWorkingSetSize >= 5 * 1024 * 1024 * 1024
            #expect(hasVRAM == expectedHasVRAM)
            #expect(VRAMMonitor.getDeviceName() == device.name)
        } else {
            #expect(hasVRAM == false)
            #expect(VRAMMonitor.getDeviceName() == nil)
        }
    }
}
