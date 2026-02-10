import Foundation

/// Validates the cryptographic integrity of inbound messages.
///
/// Bridges the raw content and signature to the Secure Enclave's verification logic.
public final class InboundIdentityValidator: Sendable {
    
    public static let shared = InboundIdentityValidator()
    
    private let fingerprinter = IdentityFingerprinter()
    
    private init() {}
    
    /// Verify the integrity of a message content against its signature.
    public func integrityStatus(for data: Data, signature: Data?) -> MessageIntegrityStatus {
        guard let signature = signature else {
            // No signature present.
            // If the system requires signatures for everything, this is .unverified.
            // For user messages (local), maybe we sign them on creation?
            // For now, if missing, it's Unverified.
            return .unverified
        }
        
        if fingerprinter.verify(signature: signature, for: data) {
            return .verified
        } else {
            return .unverified
        }
    }
    
    /// Verify a payload against a hex-string signature.
    public func verifyPayload(_ data: Data, signature: String) -> Bool {
        // Assume signature is hex string. Convert to Data.
        // If signature is raw bytes in string? User snippet says "signature: result.output['matchesSignature']".
        // Likely hex.
        // Simplistic hex to data:
        guard let sigData = Data(hexString: signature) else { return false }
        return fingerprinter.verify(signature: sigData, for: data)
    }
}

fileprivate extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if let num = UInt8(bytes, radix: 16) {
                data.append(num)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}
