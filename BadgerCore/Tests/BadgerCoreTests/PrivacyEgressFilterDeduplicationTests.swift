import Foundation
import Testing
@testable import BadgerCore

@Suite("Privacy Egress Filter Deduplication Tests")
struct PrivacyEgressFilterDeduplicationTests {

    @Test("Overlapping detections: High confidence starts after Low confidence")
    func testOverlappingHighAfterLow() async throws {
        let filter = PrivacyEgressFilter()
        let text = "12345678901234567890"
        let start = text.startIndex

        // Detection A: Low confidence, starts at 0, length 10
        let rangeA = start..<text.index(start, offsetBy: 10)
        let detectionA = PrivacyEgressFilter.Detection(
            type: .bankAccount,
            matchedText: "1234567890",
            range: rangeA,
            confidence: .low
        )

        // Detection B: High confidence, starts at 5, length 10
        let rangeB = text.index(start, offsetBy: 5)..<text.index(start, offsetBy: 15)
        let detectionB = PrivacyEgressFilter.Detection(
            type: .creditCard,
            matchedText: "6789012345",
            range: rangeB,
            confidence: .high
        )

        let detections = [detectionA, detectionB]
        let deduplicated = filter.deduplicateOverlappingDetections(detections)

        // The bug: Current logic sorts by range start first, so it picks detectionA and skips detectionB.
        // We want it to pick detectionB because it has higher confidence.
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.confidence == .high)
        #expect(deduplicated.first?.type == .creditCard)
    }

    @Test("Overlapping detections: Longer match same confidence")
    func testOverlappingLongerMatch() async throws {
        let filter = PrivacyEgressFilter()
        let text = "12345678901234567890"
        let start = text.startIndex

        // Detection A: High confidence, starts at 0, length 10
        let rangeA = start..<text.index(start, offsetBy: 10)
        let detectionA = PrivacyEgressFilter.Detection(
            type: .creditCard,
            matchedText: "1234567890",
            range: rangeA,
            confidence: .high
        )

        // Detection B: High confidence, starts at 2, length 15
        let rangeB = text.index(start, offsetBy: 2)..<text.index(start, offsetBy: 17)
        let detectionB = PrivacyEgressFilter.Detection(
            type: .creditCard,
            matchedText: "345678901234567",
            range: rangeB,
            confidence: .high
        )

        let detections = [detectionA, detectionB]
        let deduplicated = filter.deduplicateOverlappingDetections(detections)

        // We want the longer match
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.matchedText.count == 15)
    }
}
