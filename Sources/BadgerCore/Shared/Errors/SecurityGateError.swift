import Foundation

/// Errors arising from the security gate during identity operations.
///
/// Every case represents a distinct failure in the Secure Enclave–backed
/// identity pipeline. Persisted enums are `@frozen` and `String`‑raw‑value
/// backed for iCloud / disk stability.
@frozen
public enum SecurityGateError: String, Error, Sendable, Codable, Equatable, Hashable {

    /// The Secure Enclave key has been rotated unexpectedly.
    /// Triggers a mandatory re‑audit / re‑onboarding flow.
    case keyRotated

    /// The Secure Enclave is not available on this hardware.
    case enclaveUnavailable

    /// The derived fingerprint does not match the stored reference.
    case fingerprintMismatch

    /// Biometric or passcode authentication failed.
    case authenticationFailed

    /// Keychain read/write operation failed.
    case keychainOperationFailed

    /// The public key raw representation could not be exported.
    case publicKeyExportFailed
}
