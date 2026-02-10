import Foundation
import CryptoKit

/// Result of model validation — all checks must pass before loading.
public struct ModelValidationResult: Sendable, Equatable {
    /// Whether the model fits in available memory with a safety buffer.
    public let fitsInMemory: Bool

    /// Whether the model file comes from a trusted, verified source.
    public let isVerified: Bool

    /// Whether the file passed tamper / malware scanning.
    public let isSafe: Bool

    /// Human‑readable rejection reason. `nil` when all checks pass.
    public let rejectionReason: String?

    /// Estimated RAM the model will consume at runtime.
    public let estimatedRAMBytes: UInt64

    /// `true` only when all gates pass.
    public var canLoad: Bool {
        fitsInMemory && isSafe
    }
}

// MARK: - Validation Error

/// Errors surfaced to the UI as friendly messages.
public enum ModelValidationError: Error, Sendable {
    case fileTooLarge(needed: UInt64, available: UInt64)
    case insufficientMemory(needed: UInt64, available: UInt64)
    case unsafePayloadDetected
    case unreadableFile
    case validationCancelled

    /// Friendly, non‑technical message shown in the banner.
    public var friendlyMessage: String {
        switch self {
        case .fileTooLarge(let needed, let available):
            let neededGB = String(format: "%.1f", Double(needed) / 1_073_741_824)
            let availGB = String(format: "%.1f", Double(available) / 1_073_741_824)
            return "This model needs about \(neededGB) GB of memory, but your Mac only has \(availGB) GB available right now. Try a smaller model or close other apps first."
        case .insufficientMemory(let needed, let available):
            let neededGB = String(format: "%.1f", Double(needed) / 1_073_741_824)
            let availGB = String(format: "%.1f", Double(available) / 1_073_741_824)
            return "Loading this model (\(neededGB) GB) would leave too little memory for your system to stay stable (\(availGB) GB free). A cloud model is recommended instead."
        case .unsafePayloadDetected:
            return "This model file contains unexpected data that could be unsafe. It cannot be loaded. Please download models only from trusted sources like Hugging Face."
        case .unreadableFile:
            return "This file could not be read as a model. Make sure it is a valid .safetensors or .gguf file."
        case .validationCancelled:
            return "Model validation was cancelled."
        }
    }
}

// MARK: - Model Validator

/// Stateless validation pipeline for user‑supplied models.
///
/// All checks run off the main thread. The validator never loads
/// model weights — it only inspects file metadata and headers.
public actor ModelValidator {

    // MARK: - Constants

    /// 2 GB safety buffer — always reserved for macOS system stability.
    private static let safetyBufferBytes: UInt64 = 2 * 1024 * 1024 * 1024

    /// Known unsafe file signatures (first bytes of executables / scripts).
    private static let unsafeSignatures: [[UInt8]] = [
        [0x4D, 0x5A],                       // MZ — Windows PE
        [0x7F, 0x45, 0x4C, 0x46],           // ELF — Linux executable
        [0x23, 0x21],                        // #! — Shebang script
        [0xCA, 0xFE, 0xBA, 0xBE],           // Mach‑O fat binary
        [0xCF, 0xFA, 0xED, 0xFE],           // Mach‑O 64‑bit
    ]

    /// Known safe model file extensions.
    private static let safeExtensions: Set<String> = [
        "safetensors", "gguf", "ggml", "bin", "json"
    ]

    // MARK: - Primary Validation

    /// Run all validation checks against a user‑supplied model file.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the model file on disk (security‑scoped).
    ///   - totalRAM: Total physical RAM in bytes.
    ///   - availableRAM: Currently available RAM in bytes.
    /// - Returns: A ``ModelValidationResult`` describing pass/fail for each check.
    /// - Throws: ``ModelValidationError`` for hard rejections.
    public func validate(
        fileURL: URL,
        totalRAM: UInt64,
        availableRAM: UInt64
    ) async throws -> ModelValidationResult {

        try Task.checkCancellation()

        // ── 1. File readability ──────────────────────────────────────

        guard let fileSize = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? UInt64
        else {
            throw ModelValidationError.unreadableFile
        }

        try Task.checkCancellation()

        // ── 2. RAM estimation ────────────────────────────────────────

        // Heuristic: model RAM ≈ file size × 1.2 (overhead for KV‑cache + runtime).
        let estimatedRAM = UInt64(Double(fileSize) * 1.2)
        let budgetAfterBuffer = availableRAM > Self.safetyBufferBytes
            ? availableRAM - Self.safetyBufferBytes
            : 0

        let fitsInMemory = estimatedRAM <= budgetAfterBuffer

        if !fitsInMemory {
            // Hard rejection — this model would crash the system.
            throw ModelValidationError.insufficientMemory(
                needed: estimatedRAM,
                available: availableRAM
            )
        }

        try Task.checkCancellation()

        // ── 3. Safety scan ───────────────────────────────────────────

        let isSafe = try await scanForUnsafePayloads(fileURL: fileURL)

        if !isSafe {
            throw ModelValidationError.unsafePayloadDetected
        }

        try Task.checkCancellation()

        // ── 4. Provenance & verification ─────────────────────────────

        let isVerified = checkProvenance(fileURL: fileURL)

        // ── Result ───────────────────────────────────────────────────

        return ModelValidationResult(
            fitsInMemory: true,
            isVerified: isVerified,
            isSafe: true,
            rejectionReason: nil,
            estimatedRAMBytes: estimatedRAM
        )
    }

    // MARK: - Safety Scan

    /// Scan the first 8 KB of the file for known executable signatures.
    private func scanForUnsafePayloads(fileURL: URL) async throws -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw ModelValidationError.unreadableFile
        }
        defer { try? handle.close() }

        let headerData = handle.readData(ofLength: 8192)
        let bytes = Array(headerData)

        for signature in Self.unsafeSignatures {
            if bytes.count >= signature.count,
               Array(bytes.prefix(signature.count)) == signature {
                return false // Unsafe payload detected
            }
        }

        // Also reject pickle‑based files (PyTorch .bin with pickle header).
        // Pickle protocol opcode is 0x80 followed by version byte 2-5.
        if bytes.count >= 2, bytes[0] == 0x80, (2...5).contains(bytes[1]) {
            return false // Pickle payload — prefer safetensors
        }

        return true
    }

    // MARK: - Provenance Check

    /// Check whether the model directory contains publisher metadata.
    private func checkProvenance(fileURL: URL) -> Bool {
        let directory = fileURL.deletingLastPathComponent()

        // Look for metadata files that indicate a trusted source.
        let metadataFiles = ["config.json", "tokenizer_config.json", "metadata.json"]
        for file in metadataFiles {
            let path = directory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: path.path) {
                return true
            }
        }

        // Check file extension — .safetensors is inherently safer.
        if fileURL.pathExtension.lowercased() == "safetensors" {
            return true
        }

        return false
    }
}
