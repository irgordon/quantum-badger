import Foundation
import LocalAuthentication

enum AuthenticationError: Error, LocalizedError {
    case unavailable
    case failed
    case cancelled
    case biometryLocked

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Authentication isn’t available on this Mac."
        case .failed:
            return "Authentication failed."
        case .cancelled:
            return "Authentication was cancelled."
        case .biometryLocked:
            return "Touch ID is locked. Use your password to continue."
        }
    }
}

@MainActor
final class AuthenticationManager {
    func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AuthenticationError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                return context
            } else {
                throw AuthenticationError.failed
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel, .userFallback, .touchIDNotAvailable:
                throw AuthenticationError.cancelled
            case .biometryLockout, .biometryNotAvailable:
                context.invalidate()
                throw AuthenticationError.biometryLocked
            default:
                context.invalidate()
                throw AuthenticationError.failed
            }
        }
    }
}
