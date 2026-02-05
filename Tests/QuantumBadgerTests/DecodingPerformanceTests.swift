import XCTest
import QuantumBadgerRuntime

final class DecodingPerformanceTests: XCTestCase {
    func testWebScoutDecodingPerformance() {
        let payload = makeWebScoutJSON(count: 2000)
        measure {
            _ = WebScoutACL.decodeResultsJSON(payload)
        }
    }

    func testLocalSearchDecodingPerformance() {
        let payload = makeLocalSearchJSON(count: 5000)
        measure {
            _ = LocalSearchACL.decodeMatches(from: payload)
        }
    }

    private func makeWebScoutJSON(count: Int) -> String {
        var items: [[String: String]] = []
        items.reserveCapacity(count)
        for idx in 0..<count {
            items.append([
                "title": "Result \(idx)",
                "url": "https://example.com/\(idx)",
                "snippet": "This is a snippet for result \(idx)."
            ])
        }
        let data = try? JSONSerialization.data(withJSONObject: items, options: [])
        return String(data: data ?? Data(), encoding: .utf8) ?? "[]"
    }

    private func makeLocalSearchJSON(count: Int) -> String {
        var items: [[String: Any]] = []
        items.reserveCapacity(count)
        for idx in 0..<count {
            items.append([
                "filePath": "/tmp/file\(idx).txt",
                "lineNumber": idx + 1,
                "linePreview": "Preview \(idx)"
            ])
        }
        let data = try? JSONSerialization.data(withJSONObject: items, options: [])
        return String(data: data ?? Data(), encoding: .utf8) ?? "[]"
    }
}
