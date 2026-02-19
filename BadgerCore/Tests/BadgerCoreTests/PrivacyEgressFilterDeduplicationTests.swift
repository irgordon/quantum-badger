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

        // Correct logic prioritizes High confidence over position.
        // Detection B (High) should be kept, Detection A (Low) should be discarded.
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.confidence == .high)
        #expect(deduplicated.first?.type == .creditCard)
        #expect(deduplicated.first?.range == rangeB)
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
        #expect(deduplicated.first?.range == rangeB)
    }

    @Test("Nested detections: High inside Low")
    func testNestedHighInsideLow() async throws {
        let filter = PrivacyEgressFilter()
        let text = "Context sensitive data here"
        let start = text.startIndex

        // Detection A: Low confidence, longer range covering the whole text
        let rangeA = start..<text.endIndex
        let detectionA = PrivacyEgressFilter.Detection(
            type: .bankAccount,
            matchedText: text,
            range: rangeA,
            confidence: .low
        )

        // Detection B: High confidence, nested inside A
        // "sensitive" starts at index 8, length 9
        let rangeB = text.index(start, offsetBy: 8)..<text.index(start, offsetBy: 17)
        let detectionB = PrivacyEgressFilter.Detection(
            type: .creditCard,
            matchedText: "sensitive",
            range: rangeB,
            confidence: .high
        )

        let detections = [detectionA, detectionB]
        let deduplicated = filter.deduplicateOverlappingDetections(detections)

        // High confidence (B) should be prioritized, even if shorter and nested.
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.confidence == .high)
        #expect(deduplicated.first?.type == .creditCard)
        #expect(deduplicated.first?.range == rangeB)
    }

    @Test("Nested detections: Low inside High")
    func testNestedLowInsideHigh() async throws {
        let filter = PrivacyEgressFilter()
        let text = "Very sensitive data context"
        let start = text.startIndex

        // Detection A: High confidence, longer range covering the whole text
        let rangeA = start..<text.endIndex
        let detectionA = PrivacyEgressFilter.Detection(
            type: .apiKey,
            matchedText: text,
            range: rangeA,
            confidence: .high
        )

        // Detection B: Low confidence, nested inside A
        // "sensitive" starts at index 5, length 9
        let rangeB = text.index(start, offsetBy: 5)..<text.index(start, offsetBy: 14)
        let detectionB = PrivacyEgressFilter.Detection(
            type: .bankAccount,
            matchedText: "sensitive",
            range: rangeB,
            confidence: .low
        )

        let detections = [detectionA, detectionB]
        let deduplicated = filter.deduplicateOverlappingDetections(detections)

        // High confidence (A) should be prioritized. It is also longer, which is a tie-breaker win anyway.
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.confidence == .high)
        #expect(deduplicated.first?.type == .apiKey)
        #expect(deduplicated.first?.range == rangeA)
    }

    @Test("Multiple overlaps: High-Low-High chain")
    func testPartialChainOverlap() async throws {
        let filter = PrivacyEgressFilter()
        let text = "AAAAABBBBBCCCCC"
        let start = text.startIndex

        // Detection A: High confidence "AAAAA" (0-5)
        let rangeA = start..<text.index(start, offsetBy: 5)
        let detectionA = PrivacyEgressFilter.Detection(
            type: .socialSecurityNumber,
            matchedText: "AAAAA",
            range: rangeA,
            confidence: .high
        )

        // Detection B: Low confidence "ABBBBC" (4-10) - overlaps A and C
        let rangeB = text.index(start, offsetBy: 4)..<text.index(start, offsetBy: 10)
        let detectionB = PrivacyEgressFilter.Detection(
            type: .bankAccount,
            matchedText: "ABBBBC",
            range: rangeB,
            confidence: .low
        )

        // Detection C: High confidence "CCCCC" (10-15) - overlaps B (partially or adjacent? 10 is end of B and start of C)
        // Let's make B overlap C significantly: 4-11 ("ABBBBCC")
        let rangeBOverlap = text.index(start, offsetBy: 4)..<text.index(start, offsetBy: 11)
        let detectionBOverlap = PrivacyEgressFilter.Detection(
            type: .bankAccount,
            matchedText: "ABBBBCC",
            range: rangeBOverlap,
            confidence: .low
        )

        let rangeC = text.index(start, offsetBy: 10)..<text.index(start, offsetBy: 15)
        let detectionC = PrivacyEgressFilter.Detection(
            type: .apiKey,
            matchedText: "CCCCC",
            range: rangeC,
            confidence: .high
        )

        let detections = [detectionA, detectionBOverlap, detectionC]
        let deduplicated = filter.deduplicateOverlappingDetections(detections)

        // Sorted order: A (High), C (High), B (Low).
        // 1. Process A. Kept.
        // 2. Process C. Kept (no overlap with A: 0-5 vs 10-15).
        // 3. Process B. Overlaps A (4 < 5)? Yes. Discarded.

        #expect(deduplicated.count == 2)
        #expect(deduplicated.contains { $0.range == rangeA })
        #expect(deduplicated.contains { $0.range == rangeC })
        #expect(!deduplicated.contains { $0.range == rangeBOverlap })
    }
}
