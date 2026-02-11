import Foundation
import BadgerCore

/// Normalizes raw text into a secure QuantumMessage.
public enum IntentResultNormalizer {
    public struct NormalizedResult: Sendable {
        public let message: QuantumMessage
    }
    
    public static func normalize(
        rawText: String,
        kind: QuantumMessageKind,
        source: QuantumMessageSource,
        toolName: String?,
        createdAt: Date
    ) async -> NormalizedResult {
        // In a real implementation, this might perform PII redaction (via OutboundPrivacyFilter logic reused for internal consistency?)
        // or other sanitization.
        
        // We'll create the message.
        // Note: Signatures are required. We'll sign it if possible, or leave unverified if we lack the signer here.
        // Ideally, Runtime shouldn't sign? Or should it?
        // QuantumMessage init allows signature: nil.
        
        let message = QuantumMessage(
            kind: kind,
            source: source,
            toolName: toolName,
            content: rawText,
            createdAt: createdAt,
            isVerified: false, // Runtime generated, not yet signed by MemoryController?
            signature: nil
        )
        
        return NormalizedResult(message: message)
    }
}
