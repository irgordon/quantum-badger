
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Mock URL for a large file (e.g., 1GB)
// In a real reproduction, this would point to a local server or a dummy file generator.
let largeFileURL = URL(string: "https://localhost:8080/largefile.bin")!
let destinationURL = URL(fileURLWithPath: "downloaded_model.bin")

func measureMemory(operation: () async throws -> Void) async throws {
    let startMemory = reportMemory()
    print("Start Memory: \(startMemory) MB")

    try await operation()

    let endMemory = reportMemory()
    print("End Memory: \(endMemory) MB")
    print("Peak Memory Difference: \(endMemory - startMemory) MB (Approximation)")
}

func reportMemory() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    if kerr == KERN_SUCCESS {
        return Double(info.resident_size) / 1024.0 / 1024.0
    } else {
        return 0.0
    }
}

// Inefficient implementation (Current Code)
func inefficientDownload() async throws {
    print("Starting inefficient download...")
    let (data, response) = try await URLSession.shared.data(from: largeFileURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    try data.write(to: destinationURL, options: .atomic)
    print("Inefficient download complete.")
}

// Efficient implementation (Proposed Fix)
func efficientDownload() async throws {
    print("Starting efficient download...")
    let (tempURL, response) = try await URLSession.shared.download(from: largeFileURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    print("Efficient download complete.")
}

// Main execution
// Note: This requires a running server at localhost:8080 serving a large file.
// Since I cannot run a server here, this script is for demonstration purposes.

print("--- Reproduction Script ---")
print("This script demonstrates the memory usage difference between data(from:) and download(from:).")
print("To run this, you would need a local server hosting a large file.")

// Usage Example:
/*
Task {
    do {
        print("\n--- Testing Inefficient Method ---")
        try await measureMemory {
             try await inefficientDownload()
        }

        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)

        print("\n--- Testing Efficient Method ---")
        try await measureMemory {
             try await efficientDownload()
        }
    } catch {
        print("Error: \(error)")
    }
}
*/
